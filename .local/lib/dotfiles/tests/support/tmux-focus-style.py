#!/usr/bin/env python3
"""Verify client-scoped base tmux focus styling through real PTYs."""

from __future__ import annotations

import argparse
import errno
import os
import pathlib
import pty
import re
import select
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from tmux_paths import short_temporary_parent


def termux_tmux_never_renames() -> bool:
    """Whether automatic rename is known not to run here.

    Under Termux, tmux 3.8 (as packaged in CI's emulator) never marks a task
    window's active pane changed, even after the pane prints output; its log
    reads "active pane not changed" on every check, so the rename that output
    should trigger never runs. The name format itself evaluates correctly, and
    the same case passes with tmux 3.8 on Linux, so no config change can fix
    it. Skip only the name wait there; the rest of the case still runs.
    """
    if "com.termux" not in os.environ.get("PREFIX", ""):
        return False
    version = subprocess.run(["tmux", "-V"], text=True, capture_output=True, check=False).stdout
    match = re.search(r"(\d+)\.(\d+)", version)
    return match is not None and (int(match[1]), int(match[2])) >= (3, 8)


def wait_until(predicate, description: str, timeout: float = 4.0) -> None:
    """Poll authoritative tmux state instead of sleeping for guessed timing."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {description}")


class Client:
    """One controllable terminal attachment to the isolated tmux server."""

    def __init__(self, test: LeafStyleTest):
        self.test = test
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.environ.clear()
            os.environ.update(test.environment)
            os.environ["TERM"] = "xterm-256color"
            os.execvp(
                "tmux",
                ["tmux", "-S", str(test.socket), "attach-session", "-t", "focus"],
            )
        self.tty = ""
        wait_until(self._find_tty, "tmux client attachment")
        self.pump_until_quiet("initial tmux render")

    def _find_tty(self) -> bool:
        listing = self.test.tmux("list-clients", "-F", "#{client_pid} #{client_tty}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == str(self.pid):
                tty = fields[1]
                self.tty = tty
                return True
        return False

    def pump(self, duration: float) -> bytes:
        """Drain terminal output while answering Termnav's context query."""
        output = bytearray()
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if not ready:
                continue
            payload = os.read(self.master, 65536)
            output.extend(payload)
            if b"\x1b[?996n" in payload:
                os.write(self.master, b"\x1b[?997;1n")
        return bytes(output)

    def drain(self) -> None:
        """Discard bytes already queued before requesting a new render."""
        while select.select([self.master], [], [], 0)[0]:
            payload = os.read(self.master, 65536)
            if b"\x1b[?996n" in payload:
                os.write(self.master, b"\x1b[?997;1n")

    def pump_until_quiet(self, description: str, timeout: float = 2.0) -> bytes:
        """Collect one terminal update until its output has settled."""
        output = bytearray()
        deadline = time.monotonic() + timeout
        quiet_deadline: float | None = None
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if ready:
                payload = os.read(self.master, 65536)
                output.extend(payload)
                quiet_deadline = time.monotonic() + 0.1
                if b"\x1b[?996n" in payload:
                    os.write(self.master, b"\x1b[?997;1n")
                continue
            if output and quiet_deadline is not None and time.monotonic() >= quiet_deadline:
                return bytes(output)
        raise AssertionError(f"timed out waiting for {description}: {bytes(output)!r}")

    def redraw(self) -> bytes:
        """Return a fresh full-screen render for this exact tmux client."""
        self.drain()
        self.test.tmux("refresh-client", "-t", self.tty)
        return self.pump_until_quiet("full tmux redraw")

    def redraw_until_background(
        self,
        expected: tuple[int, int, int],
        description: str,
        timeout: float = 2.0,
    ) -> bytes:
        """Request full redraws until the pane body reaches the expected color.

        tmux can acknowledge the option update before its client renderer has
        consumed the new pane style. A single explicit refresh may therefore
        still paint the previous style on a busy host. Poll the terminal's
        observable output with a bounded deadline instead of guessing how long
        that handoff needs.
        """
        deadline = time.monotonic() + timeout
        last_render = b""
        last_background = None
        while time.monotonic() < deadline:
            last_render = self.redraw()
            last_background = self.test.rendered_background(last_render)
            if last_background == expected:
                return last_render
        raise AssertionError(
            f"timed out waiting for {description}: "
            f"expected {expected}, got {last_background}; {last_render!r}"
        )

    def send(self, payload: bytes) -> None:
        """Write raw terminal input without asking tmux to synthesize a key."""
        os.write(self.master, payload)

    def set_focus(self, focused: bool) -> None:
        """Send a focus transition and wait for tmux to observe it.

        tmux may legitimately emit no terminal bytes when the requested state
        already matches the client flag.  Waiting for output first therefore
        makes a correct no-op transition look like a timeout.  Poll the
        authoritative flag while continuing to service terminal queries, then
        require a short quiet period so asynchronous hook output is drained
        before the caller performs its next assertion.
        """
        os.write(self.master, b"\x1b[I" if focused else b"\x1b[O")
        expected = "focused" if focused else "unfocused"
        deadline = time.monotonic() + 2.0
        quiet_deadline: float | None = None
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if ready:
                payload = os.read(self.master, 65536)
                quiet_deadline = time.monotonic() + 0.1
                if b"\x1b[?996n" in payload:
                    os.write(self.master, b"\x1b[?997;1n")

            if self.test.client_is_focused(self.tty) is not focused:
                quiet_deadline = None
                continue

            if quiet_deadline is None:
                quiet_deadline = time.monotonic() + 0.1
            elif time.monotonic() >= quiet_deadline:
                return

        raise AssertionError(f"timed out waiting for {expected} client flag")

    def close(self) -> None:
        """Release the terminal before bounded reaping of its owned child."""
        master, self.master = self.master, -1
        close_error = None
        if master >= 0:
            try:
                os.close(master)
            except OSError as error:
                if error.errno != errno.EBADF:
                    close_error = error
        # On macOS an exiting session leader can wait for tty output to drain.
        # A publisher may still hold the slave: keeping its undrained master
        # open while waitpid blocks creates a cleanup deadlock, even after KILL.
        pid = self.pid
        if pid is not None:

            def reaped() -> bool:
                try:
                    waited, _ = os.waitpid(pid, os.WNOHANG)
                except ChildProcessError:
                    waited = pid
                if waited == pid:
                    self.pid = None
                    return True
                return False

            for action in (signal.SIGTERM, signal.SIGKILL):
                if reaped():
                    break
                try:
                    os.kill(pid, action)
                except ProcessLookupError:
                    pass
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    if reaped():
                        break
                    time.sleep(0.02)
                if self.pid is None:
                    break
            else:
                if not reaped():
                    raise AssertionError(f"owned terminal child {pid} did not exit after KILL")
        if close_error is not None:
            raise close_error


class ClientCloseTest(unittest.TestCase):
    """Keep teardown bounded even when a terminal's output queue is full."""

    def test_backpressured_pty_closes_before_reaping(self) -> None:
        ready_read, ready_write = os.pipe()
        pid, master = pty.fork()
        if pid == 0:
            os.close(ready_read)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            os.set_blocking(1, False)
            try:
                while True:
                    os.write(1, b"x" * 65536)
            except BlockingIOError:
                os.write(ready_write, b"ready")
            os.close(ready_write)
            os.set_blocking(1, True)
            try:
                while True:
                    os.write(1, b"x" * 65536)
            except OSError:
                os._exit(0)
        os.close(ready_write)
        client = Client.__new__(Client)
        client.pid, client.master = pid, master
        waitpid = os.waitpid
        try:
            self.assertTrue(select.select([ready_read], [], [], 4)[0], "PTY never filled")
            self.assertEqual(b"ready", os.read(ready_read, 5))

            def checked_reap(child: int, options: int) -> tuple[int, int]:
                # The real saturated PTY reproduces the macOS exit-drain
                # boundary. Check ordering without hanging older cleanup code.
                with self.assertRaises(OSError) as closed:
                    os.fstat(master)
                self.assertEqual(errno.EBADF, closed.exception.errno)
                self.assertEqual(os.WNOHANG, options, "every reap must stay bounded")
                return waitpid(child, options)

            with patch.object(os, "waitpid", side_effect=checked_reap):
                client.close()
            self.assertIsNone(client.pid)
            self.assertEqual(-1, client.master)
            client.close()
        finally:
            os.close(ready_read)
            if client.master >= 0:
                os.close(client.master)
                client.master = -1
            try:
                waited, _ = waitpid(pid, os.WNOHANG)
            except ChildProcessError:
                waited = pid
            if waited == 0:
                os.kill(pid, signal.SIGKILL)
                wait_until(lambda: waitpid(pid, os.WNOHANG)[0] == pid, "owned PTY reaped")

    def test_already_closed_master_and_reaped_child_are_safe(self) -> None:
        master, writer = os.pipe()
        os.close(master)
        os.close(writer)
        client = Client.__new__(Client)
        client.pid, client.master = 42, master
        with (
            patch.object(os, "waitpid", side_effect=ChildProcessError),
            patch.object(os, "kill") as kill,
        ):
            client.close()
            client.close()
        kill.assert_not_called()

    def test_master_close_error_still_reaps_before_reporting(self) -> None:
        master, writer = os.pipe()
        os.close(writer)
        client = Client.__new__(Client)
        client.pid, client.master = 42, master
        try:
            with (
                patch.object(os, "close", side_effect=OSError(errno.EIO, "close failed")),
                patch.object(os, "waitpid", return_value=(42, 0)),
                patch.object(os, "kill") as kill,
            ):
                with self.assertRaises(OSError) as failure:
                    client.close()
            self.assertEqual(errno.EIO, failure.exception.errno)
            self.assertIsNone(client.pid)
            self.assertEqual(-1, client.master)
            kill.assert_not_called()
        finally:
            os.close(master)

    def test_final_reap_has_a_deadline(self) -> None:
        master, writer = os.pipe()
        os.close(writer)
        client = Client.__new__(Client)
        client.pid, client.master = 42, master
        ticks = iter(range(100))
        with (
            patch.object(os, "waitpid", return_value=(0, 0)) as reap,
            patch.object(os, "kill"),
            patch.object(time, "monotonic", side_effect=lambda: next(ticks)),
            patch.object(time, "sleep"),
        ):
            with self.assertRaisesRegex(AssertionError, "did not exit"):
                client.close()
        self.assertTrue(reap.call_args_list)
        self.assertTrue(all(call.args[1] == os.WNOHANG for call in reap.call_args_list))


class LeafStyleTest(unittest.TestCase):
    """Check rendering and key dispatch in an isolated real tmux client."""

    config: pathlib.Path
    focus: pathlib.Path | None
    clip: pathlib.Path | None
    prompt: pathlib.Path | None

    def setUp(self) -> None:
        # macOS limits Unix socket paths to roughly 104 bytes. `dot test`
        # intentionally nests TMPDIR below an isolated suite root, so adding a
        # descriptive fixture directory there can exceed the kernel limit
        # before tmux starts. Prefer the conventional short temporary root when
        # it exists; Termux and other platforms without /tmp keep their native
        # tempfile location.
        self.temporary = tempfile.TemporaryDirectory(
            prefix="dot-focus-", dir=short_temporary_parent()
        )
        self.root = pathlib.Path(self.temporary.name)
        # The production config interpolates this path into several run-shell
        # commands. Keeping whitespace in the fixture makes every real-client
        # test exercise tmux's q: quoting instead of only checking the common
        # whitespace-free /tmp path.
        self.socket = self.root / "tmux socket.sock"
        self.clients: list[Client] = []
        # unittest does not call tearDown when startup fails. Register cleanup
        # before the server/client launch so a timeout cannot leave fixtures.
        self.addCleanup(self.cleanup)
        self.environment = os.environ.copy()
        inherited_scope = (
            "TMUX",
            "TMUX_PANE",
            "TERMNAV_PARENT_RELAY",
            "TERMNAV_TMUX_SESSION",
        )
        for variable in inherited_scope:
            self.environment.pop(variable, None)
        self.environment["XDG_RUNTIME_DIR"] = str(self.root)
        self.tmux(
            "-f",
            str(self.config),
            "new-session",
            "-d",
            "-s",
            "focus",
            "sleep 30",
        )
        self.active = self.tmux("display-message", "-p", "#{pane_id}").stdout.strip()
        self.inactive = self.tmux(
            "split-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
        ).stdout.strip()

    def cleanup(self) -> None:
        """Release all invocation-owned processes, including partial startup."""
        errors: list[Exception] = []
        for client in reversed(self.clients):
            try:
                client.close()
            except Exception as error:
                errors.append(error)
        try:
            self.tmux("kill-server", check=False)
        except Exception as error:
            errors.append(error)
        finally:
            self.temporary.cleanup()
        if errors:
            raise AssertionError(f"owned fixture cleanup failed: {errors}")

    def tmux(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["tmux", "-S", str(self.socket), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
            timeout=10,
        )

    def client_is_focused(self, tty: str) -> bool | None:
        listing = self.tmux("list-clients", "-F", "#{client_tty} #{client_flags}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == tty:
                flags = fields[1]
                return "focused" in flags.split(",")
        return None

    def expand(self, tty: str, pane: str, option: str) -> str:
        # -u keeps UTF-8 labels intact where the suite runs without a UTF-8
        # locale, as some CI images do.
        return self.tmux(
            "-u",
            "display-message",
            "-c",
            tty,
            "-p",
            "-t",
            pane,
            f"#{{E:{option}}}",
        ).stdout.strip()

    def hook(self, name: str) -> str:
        """Return the parsed global hook exactly as tmux will execute it."""
        return self.tmux("show-hooks", "-g", name).stdout.strip()

    def supports_hook(self, name: str) -> bool:
        """Probe hook support without treating a missing production hook as old tmux."""
        probe = f"{name}[999999]"
        self.tmux(
            "set-hook",
            "-g",
            probe,
            "display-message -p dot-test-probe",
            check=False,
        )
        result = self.tmux("show-hooks", "-g", name, check=False)
        self.tmux("set-hook", "-gu", probe, check=False)
        return result.returncode == 0 and probe in result.stdout

    def supports_client_format_context(self, tty: str) -> bool:
        """Return whether display-message can evaluate for a specific client."""
        return (
            self.tmux(
                "display-message",
                "-c",
                tty,
                "-p",
                "#{client_tty}",
                check=False,
            ).returncode
            == 0
        )

    def claim_child(self) -> None:
        """Apply the pane state that Termnav publishes for a focused child."""
        if self.focus is not None:
            subprocess.run(
                [
                    str(self.focus),
                    "claim",
                    "--parent-tmux",
                    str(self.socket),
                    "--parent-pane",
                    self.active,
                    "--token",
                    "0123456789abcdef01234567",
                    "--lease-ms",
                    "30000",
                ],
                env=self.environment,
                check=True,
            )
            return
        inactive_style = self.tmux(
            "show-options",
            "-gqv",
            "@termnav_inactive_style",
        ).stdout.strip()
        self.tmux(
            "set-option",
            "-p",
            "-t",
            self.active,
            "window-active-style",
            inactive_style,
        )
        self.tmux(
            "set-option",
            "-p",
            "-t",
            self.active,
            "@termnav_child_focus",
            "0123456789abcdef01234567:9999999999999999",
        )

    def release_child(self) -> None:
        """Restore inherited pane styling after the simulated child releases."""
        if self.focus is not None:
            subprocess.run(
                [
                    str(self.focus),
                    "release",
                    "--parent-tmux",
                    str(self.socket),
                    "--parent-pane",
                    self.active,
                    "--token",
                    "0123456789abcdef01234567",
                ],
                env=self.environment,
                check=True,
            )
            return
        self.tmux("set-option", "-pu", "-t", self.active, "window-active-style")
        self.tmux("set-option", "-pu", "-t", self.active, "@termnav_child_focus")

    def sync_client(self, client: Client) -> None:
        """Reconcile client focus through Termnav or its documented contract."""
        if self.focus is not None:
            subprocess.run(
                [
                    str(self.focus),
                    "sync",
                    "--tmux-socket",
                    str(self.socket),
                    "--client-pid",
                    str(client.pid),
                    "--client-tty",
                    client.tty,
                ],
                env=self.environment,
                check=True,
            )
            return
        if self.client_is_focused(client.tty):
            self.tmux("set-option", "-pu", "-t", self.active, "window-active-style")
            self.tmux("set-option", "-pu", "-t", self.active, "@termnav_client_unfocused")
            return
        inactive_style = self.tmux(
            "show-options",
            "-gqv",
            "@termnav_inactive_style",
        ).stdout.strip()
        self.tmux(
            "set-option",
            "-p",
            "-t",
            self.active,
            "window-active-style",
            inactive_style,
        )
        self.tmux(
            "set-option",
            "-p",
            "-t",
            self.active,
            "@termnav_client_unfocused",
            "1",
        )

    def rendered_background(self, payload: bytes) -> tuple[int, int, int] | None:
        """Read the last true-color background painted during a full redraw."""
        pattern = re.compile(rb"\x1b\[48(?:(?:;2;(\d+);(\d+);(\d+))|(?::2::(\d+):(\d+):(\d+)))m")
        matches = list(pattern.finditer(payload))
        if not matches:
            return None
        groups = matches[-1].groups()
        components = groups[:3] if groups[0] is not None else groups[3:]
        red, green, blue = (int(component) for component in components)
        return red, green, blue

    def test_focus_hooks_are_client_scoped_and_ignore_control_mode(self) -> None:
        if not self.supports_hook("client-focus-in"):
            self.skipTest("tmux does not expose client focus hooks")
        start_hooks = self.hook("client-attached") + "\n" + self.hook("client-focus-in")
        stop_hooks = self.hook("client-focus-out") + "\n" + self.hook("client-detached")
        sync_hooks = (
            self.hook("after-select-pane")
            + "\n"
            + self.hook("after-select-window")
            + "\n"
            + self.hook("client-session-changed")
        )
        # Notification hooks can expand #{client_*} for another client, so they
        # name the client that raised them. tmux 3.2 lacks #{hook_client}, so
        # the exact identity stays as a fallback behind the control-mode guard.
        client = (
            "#{?hook_client,--client-name #{q:hook_client},"
            "--client-pid #{client_pid} --client-tty #{q:client_tty}}"
        )
        guard = "#{||:#{hook_client},#{==:#{client_control_mode},0}}"
        for name in (
            "client-attached",
            "client-focus-in",
            "client-focus-out",
            "client-detached",
            "client-session-changed",
        ):
            # Check each hook on its own so one reverted hook cannot hide
            # behind another; client-attached[100] is the separate context hook.
            hook = "\n".join(line for line in self.hook(name).splitlines() if "tmux focus" in line)
            with self.subTest(hook=name):
                self.assertIn(f"--tmux-socket #{{q:socket_path}} {client}", hook)
                self.assertIn(guard, hook)
        # Command hooks run with the invoking client, so its identity is exact.
        command_hooks = self.hook("after-select-pane") + "\n" + self.hook("after-select-window")
        self.assertIn("#{==:#{client_control_mode},0}", command_hooks)
        self.assertIn("--client-pid #{client_pid}", command_hooks)
        self.assertIn("--client-tty #{q:client_tty}", command_hooks)
        self.assertIn("termnav tmux focus watch", start_hooks)
        self.assertIn("termnav tmux focus stop", stop_hooks)
        self.assertIn("termnav tmux focus sync", sync_hooks)
        self.assertIn("#{!=:#{@termnav_client_unfocused},}", sync_hooks)

    def test_styles_follow_each_client_and_child_claim(self) -> None:
        first = Client(self)
        self.clients.append(first)
        if not self.supports_client_format_context(first.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        second = Client(self)
        self.clients.append(second)
        first.set_focus(True)
        second.set_focus(False)

        self.assertEqual(
            "bg=#021c30",
            self.expand(first.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "fg=cyan,bold",
            self.expand(first.tty, self.active, "pane-active-border-style"),
        )
        self.assertNotIn(
            "#[fg=#898989]",
            self.expand(first.tty, self.active, "pane-border-format"),
        )

        self.assertEqual(
            "bg=#021c30",
            self.expand(second.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "fg=#333333",
            self.expand(second.tty, self.active, "pane-active-border-style"),
        )
        self.assertIn(
            "#[fg=#898989]",
            self.expand(second.tty, self.active, "pane-border-format"),
        )

        self.claim_child()
        self.assertEqual(
            "bg=#010d17",
            self.expand(first.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "fg=#333333",
            self.expand(first.tty, self.active, "pane-active-border-style"),
        )
        self.assertIn(
            "#[fg=#898989]",
            self.expand(first.tty, self.active, "pane-border-format"),
        )

        self.release_child()
        second.set_focus(True)
        self.assertEqual(
            "bg=#021c30",
            self.expand(second.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "bg=#010d17",
            self.expand(second.tty, self.inactive, "window-style"),
        )

    def pending(self, pane: str) -> str:
        return self.tmux("show-options", "-pqv", "-t", pane, "@term_notify_pending").stdout.strip()

    def program_pane(self, name: str, *, window: bool = False) -> str:
        """Start a pane whose foreground command reports as NAME.

        The program is a copy of bash, so pane_current_command reports the
        copy's name on every platform, and the trailing no-op keeps bash from
        exec-ing sleep in its place.
        """
        tools = self.root / "programs"
        tools.mkdir(exist_ok=True)
        program = tools / name
        if not program.exists():
            bash = shutil.which("bash")
            self.assertIsNotNone(bash, "bash is required for fake programs")
            shutil.copy2(str(bash), program)
        command = shlex.join([str(program), "-c", "sleep 30; :"])
        if window:
            created = self.tmux("new-window", "-d", "-P", "-F", "#{pane_id}", command)
        else:
            created = self.tmux(
                "split-window", "-d", "-t", self.active, "-P", "-F", "#{pane_id}", command
            )
        pane = created.stdout.strip()
        self.assertRegex(pane, r"^%[0-9]+$", "tmux returned no pane id")
        wait_until(
            lambda: (
                self.tmux(
                    "display-message", "-p", "-t", pane, "#{pane_current_command}"
                ).stdout.strip()
                == name
            ),
            f"{name} becomes the pane's foreground command",
        )
        return pane

    def test_pending_panes_are_marked_until_visited(self) -> None:
        if not self.supports_hook("pane-focus-in"):
            self.skipTest("tmux does not expose pane focus hooks")
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        tab = "window-status-current-format"

        # An agent beside the focused pane finished a turn: its border and the
        # current tab both show a green dot. The legacy value 1 means done.
        for value in ("done", "1"):
            with self.subTest(value=value):
                self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", value)
                self.assertIn(
                    "#22da6e", self.expand(client.tty, self.inactive, "pane-border-format")
                )
                self.assertIn("#22da6e]●", self.expand(client.tty, self.active, tab))
                self.assertNotIn("●", self.expand(client.tty, self.active, "pane-border-format"))

        # Visiting the pane acknowledges it.
        self.tmux("select-pane", "-t", self.inactive)
        wait_until(lambda: self.pending(self.inactive) == "", "pending cleared on focus-in")
        self.assertNotIn("●", self.expand(client.tty, self.inactive, tab))

        # A pane that notified while focused is not advertised, and leaving
        # it does not light it up.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "done")
        self.assertNotIn("●", self.expand(client.tty, self.inactive, tab))
        self.assertNotIn("●", self.expand(client.tty, self.inactive, "pane-border-format"))
        self.tmux("select-pane", "-t", self.active)
        wait_until(lambda: self.pending(self.inactive) == "", "pending cleared on focus-out")

        # While the terminal is unfocused the active pane is not being looked
        # at, so it shows as pending until the terminal regains focus.
        client.set_focus(False)
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_pending", "done")
        self.assertIn("●", self.expand(client.tty, self.active, "pane-border-format"))
        client.set_focus(True)
        wait_until(lambda: self.pending(self.active) == "", "pending cleared on refocus")

        # A failed command in the side pane carries a red dot and its exit
        # status until visited.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_exit_status", "2")
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "done")
        self.assertIn(
            "#ff5370,bold]● exit 2", self.expand(client.tty, self.inactive, "pane-border-format")
        )
        self.assertIn("#ff5370]●", self.expand(client.tty, self.active, tab))
        self.assertNotIn("#22da6e", self.expand(client.tty, self.active, tab))
        # Check drawn colors, not just format strings: the dot sits on the bar
        # background inside the blue current tab, and the reset after it must
        # restore the tab's own style. pop-default alone does not reset the
        # drawing style, and nested pushes overwrite tmux's own.
        self.tmux(
            "set-window-option", "window-status-current-style", "fg=#123456,bg=#234567,underscore"
        )
        self.tmux("set-window-option", tab, "BEFORE#{E:@window_marker} AFTER")
        rendered = client.redraw()
        # A client without a UTF-8 locale (Alpine CI) draws the dot as tmux's
        # "_" placeholder; the colors around it are what this checks.
        drawn = re.search(rb"BEFORE(.*?)(?:\xe2\x97\x8f|_)(.*?) AFTER", rendered, re.DOTALL)
        self.assertIsNotNone(drawn, repr(rendered))
        self.assertRegex(drawn.group(1), rb"\x1b\[(?:[0-9;:]*;)?38(?:;2;255;83;112|:2::255:83:112)")
        self.assertRegex(drawn.group(1), rb"\x1b\[(?:[0-9;:]*;)?48(?:;2;11;41;66|:2::11:41:66)")
        self.assertRegex(drawn.group(2), rb"\x1b\[(?:[0-9;:]*;)?38(?:;2;18;52;86|:2::18:52:86)")
        self.assertRegex(drawn.group(2), rb"\x1b\[(?:[0-9;:]*;)?48(?:;2;35;69;103|:2::35:69:103)")
        # The current tab is underlined but its dots are not: the underline
        # stops before the dot and resumes for the rest of the tab.
        self.assertRegex(drawn.group(1), rb"\x1b\[(?:0|24)?m|\x1b\[[0-9;:]*;24m")
        self.assertRegex(drawn.group(2), rb"\x1b\[(?:[0-9;:]*;)?4(?:;|:|m)")
        self.tmux("select-pane", "-t", self.inactive)
        wait_until(lambda: self.pending(self.inactive) == "", "failed command acknowledged")
        wait_until(
            lambda: (
                not self.tmux(
                    "show-options", "-pqv", "-t", self.inactive, "@term_notify_exit_status"
                ).stdout.strip()
            ),
            "acknowledged failure status cleared",
        )
        self.assertNotIn("exit", self.expand(client.tty, self.inactive, "pane-border-format"))

    def test_attention_predicates_keep_the_publisher_invariants(self) -> None:
        """term-pane-state rejects a whole snapshot if a pane breaks these."""
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        shell = self.program_pane("zsh")
        predicates = "#{E:@pane_pending}#{E:@pane_waiting}#{E:@pane_failed}#{E:@pane_busy}"
        for pane, seen, at_shell in (
            (self.active, True, False),
            (self.inactive, False, False),
            (shell, False, True),
        ):
            for kind in ("", "1", "done", "waiting", "blocked", "later"):
                for exit_status in ("", "2"):
                    for busy in ("", "1"):
                        for option, value in (
                            ("@term_notify_pending", kind),
                            ("@term_notify_exit_status", exit_status),
                            ("@term_busy", busy),
                        ):
                            if value:
                                self.tmux("set-option", "-p", "-t", pane, option, value)
                            else:
                                self.tmux("set-option", "-pu", "-t", pane, option)
                        sticky = kind in ("waiting", "blocked")
                        marked = bool(kind) and not (sticky and at_shell) and not seen
                        failed = marked and (
                            kind == "blocked" or (not sticky and bool(exit_status))
                        )
                        waiting = marked and kind == "waiting"
                        expected = "".join(
                            "1" if flag else "0"
                            for flag in (marked, waiting, failed, busy and not at_shell)
                        )
                        context = (
                            f"{pane} seen={seen} shell={at_shell} {kind!r} {exit_status!r} {busy!r}"
                        )
                        with self.subTest(context=context):
                            # The publisher's two views: the client's own
                            # pane, and list-panes without client context.
                            self.assertEqual(
                                expected,
                                self.tmux(
                                    "display-message",
                                    "-c",
                                    client.tty,
                                    "-p",
                                    "-t",
                                    pane,
                                    predicates,
                                ).stdout.strip(),
                            )
                            if not seen:
                                listed = self.tmux(
                                    "list-panes", "-s", "-F", f"#{{pane_id}} {predicates}"
                                ).stdout.split()
                                self.assertEqual(expected, listed[listed.index(pane) + 1])
            for option in ("@term_notify_pending", "@term_notify_exit_status", "@term_busy"):
                self.tmux("set-option", "-pu", "-t", pane, option)

    def test_a_glance_keeps_attention_that_needs_an_action(self) -> None:
        if not self.supports_hook("pane-focus-in"):
            self.skipTest("tmux does not expose pane focus hooks")
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        tab = "window-status-current-format"
        agent = self.program_pane("claude")
        sandboxed = self.program_pane("bwrap")

        # A waiting agent is yellow and a blocked one red, beside the pane you
        # are in. A visit hides the dot only while you look.
        for kind, color in (("waiting", "#ffcb6b"), ("blocked", "#ff5370")):
            with self.subTest(kind=kind):
                self.tmux("set-option", "-p", "-t", agent, "@term_notify_pending", kind)
                self.assertIn(
                    f"{color},bold]●", self.expand(client.tty, agent, "pane-border-format")
                )
                self.assertNotIn("exit", self.expand(client.tty, agent, "pane-border-format"))
                self.assertIn(f"{color}]●", self.expand(client.tty, self.active, tab))
                self.tmux("select-pane", "-t", agent)
                wait_until(
                    lambda: (
                        self.tmux(
                            "display-message", "-c", client.tty, "-p", "#{pane_id}"
                        ).stdout.strip()
                        == agent
                    ),
                    "the agent pane is selected",
                )
                client.pump(0.1)
                self.assertEqual(kind, self.pending(agent))
                self.assertNotIn("●", self.expand(client.tty, agent, tab))
                self.assertEqual("0", self.expand(client.tty, agent, "@pane_pending"))
                self.tmux("select-pane", "-t", self.active)
                client.pump(0.1)
                self.assertEqual(kind, self.pending(agent))
                self.assertIn(f"{color}]●", self.expand(client.tty, self.active, tab))

        # Focus-out acknowledges the pane losing focus, never the one gaining
        # it: a hook that resolved the wrong pane would leave the done mark
        # behind and clear the waiting agent instead.
        self.tmux("set-option", "-p", "-t", agent, "@term_notify_pending", "waiting")
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_pending", "done")
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_exit_status", "3")
        self.tmux("select-pane", "-t", agent)
        wait_until(lambda: self.pending(self.active) == "", "focus-out clears the pane it leaves")
        wait_until(
            lambda: (
                not self.tmux(
                    "show-options", "-pqv", "-t", self.active, "@term_notify_exit_status"
                ).stdout.strip()
            ),
            "focus-out clears the exit status it leaves",
        )
        self.assertEqual("waiting", self.pending(agent))
        # And focus-in on a done pane clears it while leaving a sticky one.
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_pending", "done")
        self.tmux("select-pane", "-t", self.active)
        wait_until(lambda: self.pending(self.active) == "", "focus-in clears a done pane")
        self.assertEqual("waiting", self.pending(agent))

        # A sandboxed agent reports its wrapper's name; its sticky mark stays.
        self.tmux("set-option", "-p", "-t", sandboxed, "@term_notify_pending", "waiting")
        self.tmux("select-pane", "-t", sandboxed)
        self.tmux("select-pane", "-t", self.active)
        client.pump(0.1)
        self.assertEqual("waiting", self.pending(sandboxed))

        # Another window's waiting agent survives selecting that window too.
        background = self.program_pane("codex", window=True)
        self.tmux("set-option", "-p", "-t", background, "@term_notify_pending", "blocked")
        self.assertIn("#ff5370]●", self.expand(client.tty, background, "window-status-format"))
        self.tmux("select-window", "-t", background)
        self.tmux("last-window")
        client.pump(0.1)
        self.assertEqual("blocked", self.pending(background))

    def test_sticky_attention_ends_with_its_agent(self) -> None:
        if not self.supports_hook("pane-focus-in"):
            self.skipTest("tmux does not expose pane focus hooks")
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        tab = "window-status-current-format"

        # A pane back at its shell cannot still run the agent that is waiting
        # or blocked, so the mark shows nothing there, and a visit clears it.
        shell = self.program_pane("zsh")
        for kind in ("waiting", "blocked"):
            with self.subTest(kind=kind):
                self.tmux("set-option", "-p", "-t", shell, "@term_notify_pending", kind)
                self.assertNotIn("●", self.expand(client.tty, shell, "pane-border-format"))
                self.assertNotIn("●", self.expand(client.tty, self.active, tab))
                self.assertEqual("0", self.expand(client.tty, shell, "@pane_pending"))
                self.tmux("select-pane", "-t", shell)
                wait_until(lambda: self.pending(shell) == "", "a visit clears the agent's leftover")
                self.tmux("select-pane", "-t", self.active)

        # Another program that is not an agent shows a leftover until a visit
        # clears it; a later vim in that pane shows nothing.
        program = self.program_pane("vim")
        self.tmux("set-option", "-p", "-t", program, "@term_notify_pending", "waiting")
        self.assertIn("#ffcb6b]●", self.expand(client.tty, self.active, tab))
        self.tmux("select-pane", "-t", program)
        wait_until(lambda: self.pending(program) == "", "a visit clears a non-agent's mark")
        self.tmux("select-pane", "-t", self.active)
        self.assertNotIn("●", self.expand(client.tty, self.active, tab))
        self.assertNotIn("●", self.expand(client.tty, program, "pane-border-format"))

    def test_background_window_agents_mark_their_tab(self) -> None:
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        # An agent alone in a background window is that window's active pane,
        # which the focused-leaf predicate alone would treat as being looked at.
        background = self.tmux(
            "new-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
        ).stdout.strip()
        self.tmux("set-option", "-p", "-t", background, "@term_notify_pending", "1")
        self.assertEqual("1", self.expand(client.tty, background, "@pane_pending"))
        self.assertIn("#22da6e]●", self.expand(client.tty, background, "window-status-format"))
        # A busy agent there is blue only while it shows no attention.
        self.tmux("set-option", "-p", "-t", background, "@term_busy", "1")
        self.assertNotIn("#82aaff", self.expand(client.tty, background, "window-status-format"))
        self.tmux("set-option", "-p", "-t", background, "@term_notify_pending", "waiting")
        self.assertEqual("1", self.expand(client.tty, background, "@pane_waiting"))
        self.assertIn("#ffcb6b]●", self.expand(client.tty, background, "window-status-format"))
        self.tmux("set-option", "-p", "-t", background, "@term_notify_pending", "1")
        self.tmux("select-window", "-t", background)
        wait_until(lambda: self.pending(background) == "", "pending cleared on window visit")
        # The visited agent is still working: its own tab now shows blue.
        self.assertIn(
            "#82aaff]●", self.expand(client.tty, background, "window-status-current-format")
        )

    def test_another_focused_client_does_not_strand_a_mark(self) -> None:
        if not self.supports_hook("client-focus-in"):
            self.skipTest("tmux does not expose client focus hooks")
        first = Client(self)
        self.clients.append(first)
        if not self.supports_client_format_context(first.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        # The second client never reports focus, like an idle second machine,
        # so it keeps the active pane focused server-wide and the first
        # client's return fires no pane-focus transition.
        second = Client(self)
        self.clients.append(second)
        first.set_focus(False)
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_pending", "1")
        self.assertIn("●", self.expand(first.tty, self.active, "pane-border-format"))
        first.set_focus(True)
        wait_until(lambda: self.pending(self.active) == "", "pending cleared on client refocus")

    def test_view_changes_publish_their_session_at_once(self) -> None:
        """The terminal's attention must not wait for the deduplicated status job."""
        # A stand-in publisher records session publishes (the status job uses
        # the --client form) and fails noisily: a background run-shell would
        # print its output into a pane unless the hook discards it.
        publisher = self.root / "publisher"
        publisher.mkdir()
        published = self.root / "published"
        stub = publisher / "term-pane-state"
        stub.write_text(
            "#!/bin/sh\n"
            'case " $* " in *" --session "*) printf "%s\\n" "$*" >>'
            + shlex.quote(str(published))
            + " ;; esac\necho noise\necho noise >&2\nexit 1\n"
        )
        stub.chmod(0o700)
        self.tmux("set-environment", "-g", "PATH", f"{publisher}:{self.environment['PATH']}")

        def runs() -> list[str]:
            try:
                return published.read_text().splitlines()
            except FileNotFoundError:
                return []

        def publishes(session: str, description: str, change) -> None:
            before = len(runs())
            change()
            wait_until(lambda: len(runs()) > before, description, timeout=2.0)
            self.assertEqual({f"--socket {self.socket} --session {session}"}, set(runs()[before:]))

        def stays_quiet(description: str, change) -> None:
            before = len(runs())
            change()
            time.sleep(0.5)
            self.assertEqual(before, len(runs()), description)

        client = Client(self)
        self.clients.append(client)

        def modes() -> list[str]:
            listing = self.tmux("list-panes", "-a", "-F", "#{pane_id} #{pane_mode}").stdout
            return [line.split()[0] for line in listing.splitlines() if len(line.split()) > 1]

        # The fixture HOME has none of the config's startup helpers, whose
        # load-time run-shell failures already opened view mode; start clean.
        for pane in modes():
            self.tmux("send-keys", "-t", pane, "-X", "cancel")
        self.assertEqual([], modes())
        session = self.tmux("display-message", "-p", "#{session_id}").stdout.strip()
        self.tmux("new-window", "-d", "-t", "focus:", "sleep 30")
        # Termnav switches tabs with next-window from its own tmux client.
        # Without a marked pane, focus cannot change any snapshot: no process.
        stays_quiet("unmarked next-window", lambda: self.tmux("next-window", "-t", "focus"))
        stays_quiet("unmarked select-window", lambda: self.tmux("select-window", "-t", "focus:^"))
        stays_quiet("unmarked select-pane", lambda: self.tmux("select-pane", "-t", self.inactive))
        # A mark in a window these switches never visit keeps the guard true.
        marked = self.tmux(
            "new-window", "-d", "-P", "-F", "#{pane_id}", "-t", "focus:", "sleep 30"
        ).stdout.strip()
        self.tmux("set-option", "-p", "-t", marked, "@term_notify_pending", "done")
        publishes(
            session, "publish on next-window", lambda: self.tmux("next-window", "-t", "focus")
        )
        publishes(
            session, "publish on select-window", lambda: self.tmux("select-window", "-t", "focus:^")
        )
        publishes(
            session, "publish on select-pane", lambda: self.tmux("select-pane", "-t", self.active)
        )
        if self.supports_hook("client-focus-in"):
            publishes(session, "publish on focus-out", lambda: client.set_focus(False))
            publishes(session, "publish on focus-in", lambda: client.set_focus(True))
        # Visiting the only marked pane acknowledges it before the guard above
        # runs; the acknowledgement itself must publish the cleared mark.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "done")
        self.tmux("set-option", "-pu", "-t", marked, "@term_notify_pending")
        publishes(
            session,
            "publish on visiting the only marked pane",
            lambda: self.tmux("select-pane", "-t", self.inactive),
        )
        self.assertEqual("", self.pending(self.inactive))
        self.tmux("set-option", "-p", "-t", marked, "@term_notify_pending", "done")
        publishes(
            session,
            "publish on visiting the only marked window",
            lambda: self.tmux("select-window", "-t", marked),
        )
        self.assertEqual("", self.pending(marked))
        self.tmux("select-window", "-t", "focus:^")
        self.tmux("set-option", "-p", "-t", marked, "@term_notify_pending", "done")
        # A new session needs its whole snapshot, marked or not.
        other = self.tmux(
            "new-session", "-d", "-P", "-F", "#{session_id}", "-s", "other", "sleep 30"
        ).stdout.strip()
        publishes(
            other,
            "publish on switch-client",
            lambda: self.tmux("switch-client", "-c", client.tty, "-t", other),
        )
        # The first session is now detached: its changes start no process.
        stays_quiet("detached next-window", lambda: self.tmux("next-window", "-t", session))
        self.assertEqual("done", self.pending(marked))
        self.assertEqual([], modes())

    def current_pane(self, client: Client) -> str:
        return self.tmux("display-message", "-c", client.tty, "-p", "#{pane_id}").stdout.strip()

    def window_of(self, pane: str) -> str:
        return self.tmux("display-message", "-p", "-t", pane, "#{window_id}").stdout.strip()

    def press(self, client: Client, keys: bytes) -> None:
        """Send keys after the default prefix and service the resulting redraw."""
        client.send(b"\x02" + keys)
        client.pump(0.1)

    def tree_keys(self, client: Client, *keys: bytes) -> None:
        """Type into choose-tree one key at a time.

        A cursor-key sequence followed in the same write by another key can be
        split at the escape-time boundary on a busy host, so tmux sees a bare
        Escape that closes the tree. Servicing the redraw between keys keeps
        each sequence whole.
        """
        for key in keys:
            client.send(key)
            client.pump(0.15)

    def test_prefix_a_visits_pending_panes_in_order(self) -> None:
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        waiting = self.program_pane("claude")
        blocked = self.program_pane("codex", window=True)
        done = self.tmux(
            "split-window", "-d", "-t", blocked, "-P", "-F", "#{pane_id}", "sleep 30"
        ).stdout.strip()
        self.assertRegex(done, r"^%[0-9]+$", "tmux returned no pane id")
        self.tmux("set-option", "-p", "-t", waiting, "@term_notify_pending", "waiting")
        self.tmux("set-option", "-p", "-t", blocked, "@term_notify_pending", "blocked")
        self.tmux("set-option", "-p", "-t", done, "@term_notify_pending", "done")

        def jump(expected: str, description: str) -> None:
            self.press(client, b"a")
            wait_until(lambda: self.current_pane(client) == expected, description)

        # Severity wins over tab order: red in window 2 comes before yellow
        # beside you in window 1, and green comes last.
        jump(blocked, "jump to the red pane first")
        self.assertEqual("blocked", self.pending(blocked))
        jump(waiting, "jump on to the yellow pane")
        self.assertEqual("waiting", self.pending(waiting))
        jump(done, "jump on to the green pane")
        wait_until(lambda: self.pending(done) == "", "arrival acknowledges the green pane")
        # Sticky panes stay marked, so repeated presses cycle through them
        # rather than bouncing between the first two.
        jump(blocked, "wrap around to the red pane")
        jump(waiting, "cycle on to the yellow pane")
        jump(blocked, "cycle back to the red pane")

        # With only the current pane left the key says so and stays put.
        self.tmux("set-option", "-pu", "-t", waiting, "@term_notify_pending")
        self.press(client, b"a")
        wait_until(
            lambda: "Nothing else is waiting" in self.tmux("show-messages").stdout,
            "empty-queue message",
        )
        self.assertEqual(blocked, self.current_pane(client))

    def test_prefix_j_and_J_move_panes_between_windows(self) -> None:
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        other = self.tmux("new-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30").stdout.strip()
        home = self.window_of(self.active)

        # Send the current pane into the last window in the tree (End).
        self.press(client, b"j")
        wait_until(
            lambda: (
                self.tmux("display-message", "-c", client.tty, "-p", "#{pane_mode}").stdout.strip()
                == "tree-mode"
            ),
            "window chooser",
        )
        self.tree_keys(client, b"\x1b[F", b"\r")
        wait_until(
            lambda: self.window_of(self.active) == self.window_of(other), "pane sent to the window"
        )
        self.assertEqual(home, self.window_of(self.inactive))

        # You go with the pane you sent, so you can keep working in it.
        wait_until(lambda: self.current_pane(client) == self.active, "client follows the sent pane")

        # Pull the pane left behind in the first window back in beside it.
        self.press(client, b"J")
        wait_until(
            lambda: (
                self.tmux("display-message", "-c", client.tty, "-p", "#{pane_mode}").stdout.strip()
                == "tree-mode"
            ),
            "pane chooser",
        )
        # Home is the session row; window 1 sits just below it.
        self.tree_keys(client, b"\x1bOH", b"\x1b[B", b"\r")
        wait_until(
            lambda: self.window_of(self.inactive) == self.window_of(self.active), "pane pulled in"
        )

    def test_prefix_A_pastes_the_last_output_into_the_agent(self) -> None:
        """Press prefix A from a shell pane and watch the agent receive it.

        The agent is a bash copy named codex, an agent name, so it stays the
        pane's foreground command while a builtin loop records each byte it
        receives; raw mode delivers the paste unbuffered. A stub output source
        names the pane it was asked to capture, and flag files make it report
        no block (status 3) or behave like an older tmux-copy-last-output
        without --print (64).
        """
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        stub = self.root / "bin"
        stub.mkdir()
        source = stub / "tmux-copy-last-output"
        source.write_text(
            "#!/bin/sh\n"
            '[ "$1" = --print ] || exit 2\n'
            "result=0\n"
            f'[ -e "{self.root}/empty" ] && result=3\n'
            f'[ -e "{self.root}/old" ] && result=64\n'
            f'printf "%s\\n" "$result" >>"{self.root}/calls"\n'
            '[ "$result" = 0 ] || exit "$result"\n'
            'printf "%s\\n" "% make test ($TMUX_PANE)" "FAIL: widget"\n'
        )
        source.chmod(0o755)
        agent_program = stub / "codex"
        shutil.copy(shutil.which("bash") or "/bin/bash", agent_program)
        agent_program.chmod(0o755)
        recorder = self.root / "recorder"
        recorder.write_text(
            "printf '\\033[?2004h'\n"
            "stty raw -echo\n"
            "while IFS= read -r -d '' -n 1 byte; do printf '%s' \"$byte\" >>\"$1\"; done\n"
        )
        received = self.root / "received"
        path = self.tmux("show-environment", "-g", "PATH", check=False).stdout.strip()
        base_path = path.partition("=")[2] if path.startswith("PATH=") else os.environ["PATH"]
        self.tmux("set-environment", "-g", "PATH", f"{stub}:{base_path}")

        agent = self.tmux(
            "new-window",
            "-P",
            "-F",
            "#{pane_id}",
            f"'{agent_program}' '{recorder}' '{received}'",
        ).stdout.strip()
        shell = self.tmux(
            "split-window", "-P", "-F", "#{pane_id}", "-t", agent, "sleep 30"
        ).stdout.strip()
        wait_until(
            lambda: (
                self.tmux(
                    "display-message", "-p", "-t", agent, "#{pane_current_command}"
                ).stdout.strip()
                == "codex"
            ),
            "fake agent running",
        )

        def pastes() -> str:
            return received.read_text(errors="replace") if received.exists() else ""

        def press_from(pane: str) -> None:
            self.tmux("select-window", "-t", pane)
            self.tmux("select-pane", "-t", pane)
            wait_until(lambda: self.current_pane(client) == pane, f"client on {pane}")
            calls = self.root / "calls"
            before = len(calls.read_text().splitlines()) if calls.exists() else 0
            self.press(client, b"A")
            if pane == shell:
                wait_until(
                    lambda: calls.exists() and len(calls.read_text().splitlines()) > before,
                    "output source observes this invocation before fixture flags change",
                )

        def messages() -> str:
            return self.tmux("show-messages").stdout

        expected = f"\x1b[200~% make test ({shell})\nFAIL: widget\x1b[201~"
        press_from(shell)
        wait_until(lambda: pastes().count("\x1b[201~") == 1, "first paste reaches the agent")
        # tmux's line-ending translation inside a paste varies by release.
        self.assertEqual(expected, pastes().replace("\r", "\n"))
        wait_until(lambda: self.current_pane(client) == agent, "prefix A focuses the agent")
        self.assertNotIn(
            "agent-paste", self.tmux("list-buffers", "-F", "#{buffer_name}").stdout.split()
        )

        # No block pastes nothing and stays quiet; an older
        # tmux-copy-last-output without --print is reported; pressing in the
        # agent pane or a window without an agent only explains why.
        (self.root / "empty").touch()
        press_from(shell)
        (self.root / "empty").unlink()
        (self.root / "old").touch()
        press_from(shell)
        wait_until(
            lambda: "tmux-copy-last-output --print failed with status 64" in messages(),
            "failure from an old output source is reported",
        )
        (self.root / "old").unlink()
        press_from(agent)
        wait_until(lambda: "Press prefix A in a shell pane" in messages(), "agent-pane hint")
        lone = self.tmux("new-window", "-P", "-F", "#{pane_id}", "sleep 30").stdout.strip()
        press_from(lone)
        wait_until(lambda: "No agent in this window" in messages(), "no-agent hint")

        # An agent left in copy mode would take the paste as typed lines; the
        # binding leaves copy mode first. This press is also the sentinel: once
        # its paste lands, the presses above had their turn.
        self.tmux("copy-mode", "-t", agent)
        press_from(shell)
        wait_until(lambda: pastes().count("\x1b[201~") == 2, "second paste reaches the agent")
        self.assertEqual(expected + expected, pastes().replace("\r", "\n"))
        self.assertEqual(
            "0", self.tmux("display-message", "-p", "-t", agent, "#{pane_in_mode}").stdout.strip()
        )
        self.assertEqual(
            1,
            len(re.findall(r"message: .*--print failed with status [0-9]", messages())),
            "only the real failure is reported",
        )

    def test_signal_return_resets_busy_only_for_the_shells_own_pane(self) -> None:
        """Exercise the consumer's tty proof with a real foreground shell."""
        if self.prompt is None:
            self.skipTest("candidate prompt is not supplied")
        tools = self.root / "reset-bin"
        tools.mkdir()
        calls = self.root / "reset-calls"
        marker = tools / "term-pane-mark"
        marker.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >>" + shlex.quote(str(calls)) + "\n")
        marker.chmod(0o700)
        self.tmux("set-environment", "-g", "PATH", f"{tools}:{self.environment['PATH']}")
        script = self.root / "signal-return"
        script.write_text(
            '. "$1"\n'
            '[ -z "$2" ] || export TMUX_PANE="$2"\n'
            '__term_restore 137\nprintf "RECOVERED\\n"\n'
            "while read -r ignored; do :; done\n"
        )
        # new-window takes PATH from its invoking command client, which can
        # override the server's global environment. Pin this fixture's marker
        # in the actual child invocation rather than accidentally testing the
        # installed real marker and waiting for a log it never writes.
        command_prefix = ["env", f"PATH={tools}:{self.environment['PATH']}", "bash"]
        command = shlex.join([*command_prefix, str(script), str(self.prompt), ""])
        own = self.tmux("new-window", "-d", "-P", "-F", "#{pane_id}", command).stdout.strip()
        wait_until(calls.exists, "foreground shell requests a busy reset")
        self.assertRegex(calls.read_text(), r"^reset busy --owner [1-9][0-9]*\n$")
        before = calls.read_bytes()
        other_command = shlex.join([*command_prefix, str(script), str(self.prompt), self.active])
        other = self.tmux(
            "new-window", "-d", "-P", "-F", "#{pane_id}", other_command
        ).stdout.strip()
        wait_until(
            lambda: "RECOVERED" in self.tmux("capture-pane", "-p", "-t", other).stdout,
            "foreign-pane recovery finishes",
        )
        self.assertEqual(before, calls.read_bytes(), "inherited foreign pane cannot be reset")
        self.tmux("kill-pane", "-t", own)
        self.tmux("kill-pane", "-t", other)

    def test_agent_pane_copies_are_cleaned(self) -> None:
        """Copy a wrapped agent reply in copy mode and read what clip published.

        In an agent pane, Enter hands clip the selection with the pane width
        and the column its first line starts at, and clip publishes the cleaned
        text to the pressing client; Y copies the rows as shown, as does a
        rectangle. In any other pane the keys swap. The panes are bash copies
        named claude and worker that print the transcript and wait.
        """
        if self.clip is None:
            self.skipTest("agent copy cleaning requires candidate clip")
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        tools = self.root / "copy-bin"
        tools.mkdir()
        wrapper = tools / "clip"
        broken = self.root / "clip-broken"
        calls = self.root / "clip-calls"
        wrapper.write_text(
            "#!/bin/sh\n"
            f'printf "%s\\n" "$1" >>{shlex.quote(str(calls))}\n'
            f"[ -e {shlex.quote(str(broken))} ] && exit 1\n"
            "exec " + shlex.quote(str(self.clip)) + ' "$@"\n'
        )
        wrapper.chmod(0o700)
        for name in ("claude", "worker"):
            shutil.copy(shutil.which("bash") or "/bin/bash", tools / name)
        data = self.root / "copy-data"
        self.tmux("set-environment", "-g", "PATH", f"{tools}:{self.environment['PATH']}")
        self.tmux("set-environment", "-g", "XDG_DATA_HOME", str(data))

        # Wrap a paragraph and a list item the way Claude Code does, at the
        # width this client gives a window.
        probe = self.tmux("new-window", "-P", "-F", "#{pane_id}", "sleep 30").stdout.strip()
        width = int(self.show(probe, "#{pane_width}"))
        self.tmux("kill-pane", "-t", probe)

        def wrap(words: list[str], first: str, rest: str) -> list[str]:
            rows = [first + words[0]]
            for word in words[1:]:
                if len(rows[-1]) + 1 + len(word) > width:
                    rows.append(rest + word)
                else:
                    rows[-1] += " " + word
            return rows

        paragraph = (
            "Agent replies arrive wrapped at the pane width, so the filter decides for"
            " every row whether the next word could have fit there, and only then joins"
            " the two rows back into the paragraph that the agent actually wrote."
        ).split()
        item = "a list item whose text runs on well past the end of the row".split()
        rows = [*wrap(paragraph, "● ", "  "), "", *wrap(["1.", *item], "  ", "     ")]
        self.assertGreater(len(rows), 4, "the transcript wraps")
        transcript = self.root / "transcript"
        transcript.write_text("\n".join(rows) + "\n")
        shown = "\n".join(rows)
        cleaned = " ".join(paragraph) + "\n\n1. " + " ".join(item)

        def pane(program: str) -> str:
            created = self.tmux(
                "new-window",
                "-P",
                "-F",
                "#{pane_id}",
                shlex.join(
                    [str(tools / program), "-c", 'cat "$1"; sleep 30; :', "-", str(transcript)]
                ),
            ).stdout.strip()
            wait_until(
                lambda: (
                    self.show(created, "#{pane_current_command}") == program
                    and rows[-1] in self.tmux("capture-pane", "-p", "-t", created).stdout
                ),
                f"{program} shows the transcript",
            )
            wait_until(lambda: self.current_pane(client) == created, f"client on {program}")
            return created

        def copy(target: str, key: bytes, *motions: tuple[str, ...]) -> str:
            while self.tmux("delete-buffer", check=False).returncode == 0:
                pass
            self.tmux("copy-mode", "-t", target)
            for motion in motions:
                self.tmux("send-keys", "-t", target, "-X", *motion)
            client.send(key)
            client.pump(0.1)
            wait_until(
                lambda: self.tmux("list-buffers", "-F", "#{buffer_name}").stdout.strip() != "",
                "the copy reaches a tmux buffer",
            )
            return self.tmux("show-buffer").stdout

        whole = [
            ("history-top",),
            ("start-of-line",),
            ("begin-selection",),
            ("-N", str(len(rows) - 1), "cursor-down"),
            ("end-of-line",),
        ]
        agent = pane("claude")
        # Whether a selection ending at the end of a row takes its newline
        # varies by tmux release; the cleaned copy keeps whatever it took.
        raw = copy(agent, b"Y", *whole)
        newline = "\n" if raw.endswith("\n") else ""
        self.assertEqual(shown + newline, raw)
        self.assertEqual(cleaned + newline, copy(agent, b"\r", *whole))
        # Dot-named files are another copy's staging, which may vanish.
        history = [
            entry.read_text()
            for entry in (data / "clip").iterdir()
            if not entry.name.startswith(".")
        ]
        self.assertIn(cleaned + newline, history, "clip history records the cleaned text")

        # A selection may start mid-row, and either end may be the anchor.
        start = rows[0].index(paragraph[3])
        tail = " ".join(paragraph[3 : len(" ".join(rows[:2]).split()) - 1])
        forward = [
            ("history-top",),
            ("start-of-line",),
            ("-N", str(start), "cursor-right"),
            ("begin-selection",),
            ("cursor-down",),
            ("end-of-line",),
        ]
        self.assertEqual(tail + newline, copy(agent, b"\r", *forward))
        backward = [
            ("history-top",),
            ("cursor-down",),
            ("end-of-line",),
            ("begin-selection",),
            ("cursor-up",),
            ("start-of-line",),
            ("-N", str(start), "cursor-right"),
        ]
        self.assertEqual(tail + newline, copy(agent, b"\r", *backward))
        rectangle = [
            ("history-top",),
            ("start-of-line",),
            ("begin-selection",),
            ("rectangle-toggle",),
            ("cursor-down",),
            ("-N", "5", "cursor-right"),
        ]
        self.assertEqual(rows[0][:6] + "\n" + rows[1][:6], copy(agent, b"\r", *rectangle))

        # Without a selection there is nothing to clean: Enter takes the path
        # it always took, which leaves copy mode.
        # The copies above record history in background jobs; let them land.
        def settled() -> bool:
            seen = calls.read_text()
            time.sleep(0.3)
            return calls.read_text() == seen

        wait_until(settled, "earlier clip jobs finish")
        before = calls.read_text()
        self.tmux("copy-mode", "-t", agent)
        client.send(b"\r")
        wait_until(lambda: self.show(agent, "#{pane_in_mode}") == "0", "copy mode ends")
        client.pump(0.3)
        self.assertNotIn(
            "copy", calls.read_text()[len(before) :].split(), "no selection runs no clean copy"
        )

        # A clip that fails has copied nothing, which tmux reports.
        broken.touch()
        self.tmux("copy-mode", "-t", agent)
        for motion in whole:
            self.tmux("send-keys", "-t", agent, "-X", *motion)
        client.send(b"\r")
        # The message log also echoes the binding, which holds the same text.
        wait_until(
            lambda: (
                re.search(
                    r"message: clip could not copy the selection; Y copies it as shown",
                    self.tmux("show-messages").stdout,
                )
                is not None
            ),
            "a failed clean copy is reported",
        )
        broken.unlink()

        other = pane("worker")
        self.assertEqual(shown + newline, copy(other, b"\r", *whole))
        self.assertEqual(cleaned + newline, copy(other, b"Y", *whole))

    def test_clipboard_popup_pastes_into_its_explicit_underlying_pane(self) -> None:
        """Drive the real popup and fzf, preserving trailing newlines."""
        if self.clip is None or shutil.which("fzf") is None:
            self.skipTest("clipboard popup requires candidate clip and fzf")
        helper = shutil.which("tmux-clip-paste")
        if helper is None:
            self.skipTest("clipboard popup requires tmux-tools")
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)
        data = self.root / "data"
        environment = dict(self.environment, XDG_DATA_HOME=str(data))
        payload = b"popup-selected\nline-two\n\n"
        subprocess.run(
            [str(self.clip), "capture", "--history-only"],
            input=payload,
            env=environment,
            check=True,
            timeout=5,
        )
        tools = self.root / "clipboard-bin"
        tools.mkdir()
        finished = self.root / "picker-finished"
        wrapper = tools / "clip"
        wrapper.write_text(
            "#!/bin/sh\n"
            + shlex.quote(str(self.clip))
            + ' "$@"\nresult=$?\n'
            + 'if [ "$1" = pick ]; then printf "%s:%s\\n" "$$" "$result" >>'
            + shlex.quote(str(finished))
            + '; fi\nexit "$result"\n'
        )
        wrapper.chmod(0o700)
        (tools / "tmux-clip-paste").symlink_to(helper)
        inherited_path = self.environment["PATH"]
        self.tmux("set-environment", "-g", "PATH", f"{tools}:{inherited_path}")
        self.tmux("set-environment", "-g", "XDG_DATA_HOME", str(data))
        recorder = self.root / "clipboard-recorder"
        recorder.write_text(
            "stty raw -echo\n"
            "printf '\\033[?2004hREADY\\n'\n"
            "while IFS= read -r -d '' -n 1 byte; do printf '%s' \"$byte\" >>\"$1\"; done\n"
        )
        received = self.root / "clipboard-received"
        target = self.tmux(
            "new-window", "-P", "-F", "#{pane_id}", f"bash '{recorder}' '{received}'"
        ).stdout.strip()
        wait_until(
            lambda: "READY" in self.tmux("capture-pane", "-p", "-t", target).stdout,
            "clipboard destination ready",
        )
        modes_before = self.tmux(
            "list-panes", "-a", "-F", "#{pane_id}:#{pane_in_mode}"
        ).stdout.splitlines()
        self.press(client, b"P")
        seen = bytearray()

        def picker_visible() -> bool:
            # The second identical popup can be drawn as a terminal delta that
            # omits unchanged prompt text. Ask the real client for a complete
            # render rather than mistaking that optimization for an absent UI.
            seen.extend(client.redraw())
            return b"clip>" in seen

        try:
            wait_until(picker_visible, "real clipboard picker visible")
        except AssertionError as error:
            raise AssertionError(
                f"{error}; client={bytes(seen)!r}; messages={self.tmux('show-messages').stdout}"
            ) from error
        client.send(b"\r")
        wait_until(
            lambda: received.exists() and b"\x1b[201~" in received.read_bytes(),
            "popup selection reaches its underlying pane",
        )
        expected = b"\x1b[200~" + payload + b"\x1b[201~"
        self.assertEqual(expected, received.read_bytes().replace(b"\r", b"\n"))

        def picker_reaped(count: int) -> bool:
            if not finished.exists():
                return False
            rows = finished.read_text().splitlines()
            if len(rows) < count:
                return False
            pid = int(rows[count - 1].split(":")[0])
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return True
            return False

        wait_until(lambda: picker_reaped(1), "successful popup process reaped")
        client.pump_until_quiet("successful popup returns to its source pane")
        before = received.read_bytes()
        self.press(client, b"P")
        seen.clear()
        try:
            wait_until(picker_visible, "second picker visible")
        except AssertionError as error:
            raise AssertionError(
                f"{error}; client={bytes(seen)!r}; messages={self.tmux('show-messages').stdout}"
            ) from error
        client.send(b"\x1b")
        wait_until(lambda: picker_reaped(2), "cancelled popup process reaped")
        client.pump_until_quiet("cancelled popup returns to its source pane")
        self.assertEqual(
            modes_before,
            self.tmux("list-panes", "-a", "-F", "#{pane_id}:#{pane_in_mode}").stdout.splitlines(),
            "cancellation preserves existing modes instead of opening an error view",
        )
        # A later sentinel proves the cancellation had its turn; it must not
        # consume an older handoff or inject any cancelled selection.
        client.send(b"CANCEL-SENTINEL")

        def sentinel_received() -> bool:
            # Keep servicing the actual terminal while tmux dispatches input;
            # a blocking send-keys CLI cannot drain this attached client's PTY.
            client.pump(0.02)
            return received.read_bytes().endswith(b"CANCEL-SENTINEL")

        wait_until(sentinel_received, "cancellation sentinel")
        self.assertEqual(before + b"CANCEL-SENTINEL", received.read_bytes())

        # Empty and absent histories are both normal no-selection outcomes.
        # Exercise each through the actual binding, not just clip's exit code:
        # run-shell must not turn them into a view that eats subsequent input.
        subprocess.run(
            [str(self.clip), "clear"], env=environment, check=True, capture_output=True, timeout=5
        )
        for index, history in enumerate(("empty", "absent"), start=3):
            with self.subTest(history=history):
                if history == "absent":
                    (data / "clip").rmdir()
                prior = received.read_bytes()
                self.press(client, b"P")

                def no_selection_finished(expected_count: int = index) -> bool:
                    client.pump(0.02)
                    return picker_reaped(expected_count)

                wait_until(no_selection_finished, f"{history} picker exits without a selection")
                self.assertEqual("3", finished.read_text().splitlines()[index - 1].split(":")[1])
                self.assertEqual(
                    modes_before,
                    self.tmux(
                        "list-panes", "-a", "-F", "#{pane_id}:#{pane_in_mode}"
                    ).stdout.splitlines(),
                )
                sentinel = f"{history.upper()}-SENTINEL".encode()
                client.send(sentinel)

                def typed_after_no_selection(expected: bytes = sentinel) -> bool:
                    client.pump(0.02)
                    return received.read_bytes().endswith(expected)

                wait_until(typed_after_no_selection, f"typing works after {history} history")
                self.assertEqual(prior + sentinel, received.read_bytes())

    def test_prefix_g_and_G_open_popups_in_the_pane_directory(self) -> None:
        """Press prefix g and G and check what each popup ran, and where.

        The popup programs are stand-ins that record their working directory
        and TMUX_PANE, then exit, so each popup closes itself. tmux gives a
        popup no TMUX_PANE, while any pane (a split, a window) has one, so
        an empty TMUX_PANE proves a popup ran it.
        """
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        work = self.root / "work dir"
        work.mkdir()
        stub = self.root / "popup-bin"
        stub.mkdir()
        shell_marker = self.root / "shell-ran"
        git_marker = self.root / "lazygit-ran"
        shell = stub / "scratch-shell"
        record = 'printf "%s %s\\n" "$(pwd)" "${TMUX_PANE:-popup}"'
        shell.write_text(f'#!/bin/sh\n{record} > "{shell_marker}"\n')
        shell.chmod(0o755)
        pane = self.tmux(
            "new-window", "-P", "-F", "#{pane_id}", "-c", str(work), "sleep 30"
        ).stdout.strip()
        wait_until(lambda: self.current_pane(client) == pane, "client on the work pane")
        self.tmux("set-option", "-g", "default-command", str(shell))

        self.press(client, b"g")
        wait_until(shell_marker.exists, "prefix g runs the default shell in a popup")
        # pwd prints the physical path: macOS puts /tmp under /private.
        self.assertEqual(f"{work.resolve()} popup", shell_marker.read_text().strip())

        # Without lazygit on the server's PATH, prefix G only says so.
        path = self.tmux("show-environment", "-g", "PATH", check=False).stdout.strip()
        base_path = path.partition("=")[2] if path.startswith("PATH=") else os.environ["PATH"]
        bare_path = ":".join(
            d for d in base_path.split(":") if d and not (pathlib.Path(d) / "lazygit").exists()
        )
        self.tmux("set-environment", "-g", "PATH", bare_path)
        self.press(client, b"G")
        wait_until(
            lambda: "lazygit is not installed" in self.tmux("show-messages").stdout,
            "prefix G reports a missing lazygit",
        )
        lazygit = stub / "lazygit"
        lazygit.write_text(f'#!/bin/sh\n{record} > "{git_marker}"\n')
        lazygit.chmod(0o755)
        self.tmux("set-environment", "-g", "PATH", f"{stub}:{bare_path}")
        self.press(client, b"G")
        wait_until(git_marker.exists, "prefix G runs lazygit in a popup")
        self.assertEqual(f"{work.resolve()} popup", git_marker.read_text().strip())

    def test_prefix_n_opens_a_task_window(self) -> None:
        """Press prefix n, pick from the menu, check the layout and the name.

        Every pane runs a stand-in shell that records the keys it receives, so
        the test sees what was typed into each pane. The directory name holds a
        quote, which must reach tmux as data, as must the quotes in the typed
        command line. (The directory holds no $: tmux 3.4 itself escapes $ when
        it expands formats, as prefix c shows.)
        """
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        work = self.root / 'task "q" dir'
        work.mkdir()
        recorder = self.root / "task-recorder"
        recorder.write_text(
            "stty raw -echo\n"
            'log="$1/${TMUX_PANE#%}.keys"; : > "$log"\n'
            "while IFS= read -r -d '' -n 1 b; do printf '%s' \"$b\" >> \"$log\"; done\n"
        )
        stand_in = f"bash '{recorder}' '{self.root}'"
        self.tmux("set-option", "-g", "default-command", stand_in)
        start = self.tmux(
            "new-window", "-P", "-F", "#{pane_id}", "-c", str(work), stand_in
        ).stdout.strip()
        wait_until(lambda: self.current_pane(client) == start, "client on the start pane")

        def keys(pane: str) -> str:
            log = self.root / f"{pane.lstrip('%')}.keys"
            return log.read_text() if log.exists() else ""

        def entered(pane: str, line: str) -> bool:
            """Whether pane received line and then Enter, and nothing else."""
            # Enter arrives as \n instead of \r when it beats the stand-in's
            # stty raw, since the terminal then still maps CR to NL.
            return keys(pane) in (line + "\r", line + "\n")

        def show(window: str, fmt: str) -> str:
            return self.tmux("display-message", "-p", "-t", window, fmt).stdout.strip()

        def send_when_shown(needle: bytes, payload: bytes) -> None:
            """Wait until the client draws needle, then type payload."""
            seen = bytearray()

            def shown() -> bool:
                seen.extend(client.pump(0.1))
                return needle in seen

            wait_until(shown, f"{needle.decode()} is shown")
            client.send(payload)

        def open_task(menu_key: bytes, *answers: bytes) -> list[str]:
            """Pick menu_key, then submit each answer once its prompt shows."""
            before = set(self.tmux("list-windows", "-F", "#{window_id}").stdout.split())
            client.send(b"\x02n")
            send_when_shown(b"New task window", menu_key)
            prompts = [b"Command:"] if menu_key == b"o" else []
            self.assertEqual(len(prompts), len(answers), "one answer per prompt")
            # Indexed, not zip(strict=...), which needs Python 3.10.
            for index, prompt in enumerate(prompts):
                send_when_shown(prompt, answers[index])
            created: list[str] = []

            def new_window() -> bool:
                listed = self.tmux("list-windows", "-F", "#{window_id}").stdout.split()
                created[:] = [w for w in listed if w not in before]
                return bool(created)

            wait_until(new_window, "prefix n opens a window")
            panes = self.tmux("list-panes", "-t", created[0], "-F", "#{pane_id}").stdout.split()
            return [created[0], *panes]

        def named_automatically(window: str) -> None:
            """The window keeps tmux's automatic name: here, the directory's."""
            self.assertEqual("1", show(window, "#{automatic-rename}"))
            if termux_tmux_never_renames():
                print(f"note: {window} name wait skipped (Termux tmux 3.8+)", file=sys.stderr)
                return
            try:
                wait_until(
                    lambda: show(window, "#{window_name}") == work.name,
                    f"{window} is named after its directory",
                )
            except AssertionError:
                # Name what it settled on, and what its panes run, rather than
                # only timing out: a slow host and a wrong name read the same.
                panes = []
                for row in self.tmux(
                    "list-panes",
                    "-t",
                    window,
                    "-F",
                    "#{pane_pid}\t#{pane_current_command}\t#{pane_current_path}",
                ).stdout.splitlines():
                    pid, command, path = (row.split("\t") + ["", ""])[:3]
                    try:
                        cwd = os.readlink(f"/proc/{pid}/cwd")
                    except OSError as error:
                        cwd = f"unreadable ({error.strerror})"
                    panes.append(f"{command} path={path!r} /proc cwd={cwd!r}")
                # SIGUSR2 starts the server's log; prompt the pane for output
                # (automatic rename runs only after it changes) and keep the
                # log lines for this window, which name each rename decision.
                server = show(window, "#{pid}")
                server_cwd = os.readlink(f"/proc/{server}/cwd")
                os.kill(int(server), signal.SIGUSR2)
                self.tmux("send-keys", "-t", window, "echo renamed", "Enter")
                time.sleep(2)
                os.kill(int(server), signal.SIGUSR2)
                log_lines = []
                for log in pathlib.Path(server_cwd).glob(f"tmux-server-{server}.log"):
                    log_lines = [
                        line
                        for line in log.read_text(errors="replace").splitlines()
                        if f" {window} " in line
                    ][-15:]
                    log.unlink()
                version = self.tmux("-V").stdout.strip()
                evaluated = show(window, "#{E:automatic-rename-format}")
                apps = show(window, "#{E:@window_apps}")
                self.assertEqual(
                    work.name,
                    show(window, "#{window_name}"),
                    f"{window}'s name ({version}); format evaluates to {evaluated!r}, "
                    f"apps {apps!r}; panes: {panes}; after output the name is "
                    f"{show(window, '#{window_name}')!r}; server log: {log_lines}",
                )
                raise

        # codex
        window, agent, shell = open_task(b"x")
        named_automatically(window)

        def directory(pane: str) -> pathlib.Path:
            return pathlib.Path(show(pane, "#{pane_current_path}")).resolve()

        for pane in (agent, shell):
            # A new pane's directory can read empty, or the server's, until
            # its process has started, so wait for it to settle.
            try:
                wait_until(
                    lambda pane=pane: directory(pane) == work.resolve(),
                    f"{pane} starts in the current pane's directory",
                )
            except AssertionError:
                # Name the directory it settled on rather than only timing out.
                self.assertEqual(work.resolve(), directory(pane), f"{pane}'s directory")
                raise
        widths = [int(show(pane, "#{pane_width}")) for pane in (agent, shell)]
        share = widths[0] / (widths[0] + widths[1] + 1)
        self.assertLess(abs(share - 0.6), 0.05, f"the agent pane takes about 60%: {widths}")
        self.assertEqual(agent, self.current_pane(client), "the agent pane has focus")
        wait_until(lambda: entered(agent, "codex"), "codex and Enter are typed into the agent pane")
        self.assertEqual("", keys(shell), "nothing is typed into the shell pane")

        # claude
        window, agent, shell = open_task(b"c")
        named_automatically(window)
        wait_until(
            lambda: entered(agent, "claude"), "claude and Enter are typed into the agent pane"
        )
        self.assertEqual("", keys(shell))

        # "shell only" types nothing.
        window, left, right = open_task(b"s")
        named_automatically(window)
        self.assertEqual(("", ""), (keys(left), keys(right)))

        # "other" types the command line it is given, quotes and command
        # syntax included.
        line = """codex resume --last 'x' "y;~" $HOME"""
        window, agent, shell = open_task(b"o", line.encode() + b"\r")
        named_automatically(window)
        wait_until(
            lambda: entered(agent, line),
            "other types its command line and Enter into the agent pane",
        )
        self.assertEqual("", keys(shell))

    # Right-click menus and the command palette. These cases read client
    # state through list-clients, which every supported tmux targets
    # correctly (tmux 3.2 cannot aim display-message -c at a client).
    def client_pane(self, client: Client) -> str:
        rows = self.tmux("list-clients", "-F", "#{client_tty} #{pane_id}").stdout.splitlines()
        return next((row.split()[1] for row in rows if row.split()[0] == client.tty), "")

    def show(self, target: str, fmt: str) -> str:
        return self.tmux("display-message", "-p", "-t", target, fmt).stdout.strip()

    def wait_drawn(self, client: Client, needle: bytes, description: str) -> None:
        """Service the client until its terminal output contains needle."""
        seen = bytearray()

        def drawn() -> bool:
            seen.extend(client.pump(0.05))
            return needle in seen

        wait_until(drawn, description)

    def tmux_at_least(self, major: int, minor: int) -> bool:
        match = re.search(r"(\d+)\.(\d+)", self.tmux("-V").stdout)
        return match is not None and (int(match[1]), int(match[2])) >= (major, minor)

    def right_click(
        self, client: Client, x: int, y: int, *, meta: bool = False, opens: bytes = b""
    ) -> None:
        """Press and release the right button at 1-based cell x, y (SGR).

        Earlier output is drained first, so a wait_drawn after the click sees
        only what the click draws, not an earlier menu. With opens, the
        release waits until the menu showing it is drawn, so the release
        reaches that menu rather than arriving before tmux opened it.
        """
        client.pump(0.2)
        button = 2 + (8 if meta else 0)
        client.send(f"\x1b[<{button};{x};{y}M".encode())
        if opens:
            self.wait_drawn(client, opens, f"the menu showing {opens.decode()}")
        else:
            time.sleep(0.05)
        client.send(f"\x1b[<{button};{x};{y}m".encode())

    def click_pane(
        self, client: Client, pane: str, *, meta: bool = False, row: int = 1, opens: bytes = b""
    ) -> None:
        """Right-click column 2 of pane row ROW (0-based), below the top status line."""
        left, top = (int(n) for n in self.show(pane, "#{pane_left} #{pane_top}").split())
        self.right_click(client, left + 3, top + row + 2, meta=meta, opens=opens)

    def recorder_pane(self, name: str, received: pathlib.Path, *, mouse: bool) -> str:
        """Start a window whose program records every byte it receives.

        The program is a bash copy named NAME, so pane_current_command reports
        it; with mouse it turns on mouse reporting first, as Neovim or a nested
        tmux does.
        """
        tools = self.root / "programs"
        tools.mkdir(exist_ok=True)
        program = tools / name
        if not program.exists():
            shutil.copy2(shutil.which("bash") or "/bin/bash", program)
        script = self.root / f"{name}-recorder"
        script.write_text(
            ("printf '\\033[?1000h\\033[?1006h'\n" if mouse else "")
            + "stty raw -echo\n"
            + "while IFS= read -r -d '' -n 1 byte; do printf '%s' \"$byte\" >>\"$1\"; done\n"
        )
        pane = self.tmux(
            "new-window",
            "-P",
            "-F",
            "#{pane_id}",
            shlex.join([str(program), str(script), str(received)]),
        ).stdout.strip()
        self.assertRegex(pane, r"^%[0-9]+$", "tmux returned no pane id")
        wait_until(
            lambda: (
                self.show(pane, "#{pane_current_command} #{mouse_any_flag}")
                == f"{name} {1 if mouse else 0}"
            ),
            f"{name} runs with mouse reporting {'on' if mouse else 'off'}",
        )
        return pane

    def test_right_click_opens_the_pane_menu_on_the_pane_clicked(self) -> None:
        """Right-click an unfocused pane, then split it from its menu.

        The click selects the pane, the menu stays open after the button
        comes up, and its split starts in that pane's directory.
        """
        client = Client(self)
        self.clients.append(client)
        left_dir = self.root / "left dir"
        right_dir = self.root / "right 'dir"
        left_dir.mkdir()
        right_dir.mkdir()
        left = self.tmux(
            "new-window", "-P", "-F", "#{pane_id}", "-c", str(left_dir), "sleep 30"
        ).stdout.strip()
        right = self.tmux(
            "split-window",
            "-h",
            "-d",
            "-t",
            left,
            "-P",
            "-F",
            "#{pane_id}",
            "-c",
            str(right_dir),
            "sleep 30",
        ).stdout.strip()
        self.assertRegex(right, r"^%[0-9]+$", "tmux returned no pane id")
        wait_until(lambda: self.client_pane(client) == left, "client on the left pane")

        self.click_pane(client, right)
        wait_until(lambda: self.client_pane(client) == right, "right-click selects the pane")
        self.wait_drawn(client, b"Split side by side", "the pane menu opens and stays open")
        client.send(b"%")
        window = self.show(right, "#{window_id}")
        wait_until(lambda: self.show(window, "#{window_panes}") == "3", "the menu splits the pane")
        new = self.client_pane(client)
        self.assertNotIn(new, (left, right))
        wait_until(
            lambda: (
                pathlib.Path(self.show(new, "#{pane_current_path}")).resolve()
                == right_dir.resolve()
            ),
            "the split starts in the clicked pane's directory",
        )

        # Closing from the menu asks first, then closes the pane clicked,
        # named explicitly because the confirmation runs without the menu's
        # target before tmux 3.4. A second press within tmux's double-click
        # interval would arrive as a DoubleClick key, so let it pass.
        time.sleep(0.6)
        self.click_pane(client, left)
        wait_until(lambda: self.client_pane(client) == left, "right-click selects the left pane")
        self.wait_drawn(client, b"Close the pane...", "the pane menu offers to close the pane")
        client.send(b"x")
        self.wait_drawn(client, b"? (y/n)", "closing asks first")
        client.send(b"y")
        wait_until(lambda: self.show(window, "#{window_panes}") == "2", "the pane closes")
        panes = self.tmux("list-panes", "-t", window, "-F", "#{pane_id}").stdout.split()
        self.assertNotIn(left, panes)

        # The menu opens the task-window menu with its directory escapes
        # intact: "shell only" opens both panes in the quoted directory.
        self.tmux("select-pane", "-t", right)
        wait_until(lambda: self.client_pane(client) == right, "client on the right pane")
        before = set(self.tmux("list-windows", "-F", "#{window_id}").stdout.split())
        client.send(b"\x02>")
        self.wait_drawn(client, b"New task window...", "the pane menu offers a task window")
        client.send(b"n")
        self.wait_drawn(client, b"shell only", "the task-window menu opens")
        client.send(b"s")

        def task_window() -> str:
            after = self.tmux("list-windows", "-F", "#{window_id}").stdout.split()
            created = [w for w in after if w not in before]
            return created[0] if created else ""

        wait_until(lambda: task_window() != "", "the task window opens")
        task_panes = self.tmux("list-panes", "-t", task_window(), "-F", "#{pane_id}").stdout.split()
        self.assertEqual(2, len(task_panes))
        # The shell pane splits from #{pane_start_path}, which tmux 3.2 lacks.
        if not self.tmux_at_least(3, 3):
            task_panes = task_panes[:1]
        for task_pane in task_panes:
            wait_until(
                lambda task_pane=task_pane: (
                    pathlib.Path(self.show(task_pane, "#{pane_current_path}")).resolve()
                    == right_dir.resolve()
                ),
                f"{task_pane} starts in the menu pane's directory",
            )

        # Text under the pointer is copied as data, even when it starts with
        # - or ~ (a diff line, a path), or holds quotes and $. The lines sit
        # low in the pane, so the menu, too tall to fit below the pointer in
        # this terminal, opens above it.
        line = """-removed ~/x "q" $HOME"""
        home_line = "~/notes q"
        text = self.tmux(
            "new-window",
            "-P",
            "-F",
            "#{pane_id}",
            f"printf '%.0s\\n' $(seq 20); printf '%s\\n%s' '{line}' '{home_line}'; sleep 30",
        ).stdout.strip()
        wait_until(
            lambda: (
                self.tmux("capture-pane", "-p", "-t", text).stdout.splitlines()[20:22]
                == [line, home_line]
            ),
            "the lines show on pane rows 20 and 21",
        )
        wait_until(lambda: self.client_pane(client) == text, "client on the text pane")
        for row, expected in ((20, line), (21, home_line)):
            time.sleep(0.6)
            self.click_pane(client, text, row=row, opens=b"Copy the line")
            client.send(b"l")
            wait_until(
                lambda expected=expected: self.tmux("show-buffer", check=False).stdout == expected,
                f"pane row {row} is copied as it reads",
            )

        # Clicked low in the pane, the menu opens above the pointer rather
        # than over it, where the button coming up would close it or run the
        # item under the pointer: nothing has run when it comes up, and the
        # menu is still open for the split. Row 16 leaves room above for the
        # menu inside the window: since tmux 3.8 a menu cannot cover the
        # status line, which older versions let it borrow.
        time.sleep(0.6)
        self.click_pane(client, text, row=16, opens=b"Close the pane")
        client.pump(0.3)
        self.assertEqual("1", self.show(text, "#{window_panes}"))
        self.assertEqual(text, self.client_pane(client))
        client.send(b"%")
        wait_until(
            lambda: self.show(text, "#{window_panes}") == "2", "the menu stayed open for the split"
        )

    def test_a_program_using_the_mouse_keeps_the_right_click(self) -> None:
        """A mouse-reporting program gets the right-click; Option opens the menu."""
        client = Client(self)
        self.clients.append(client)
        received = self.root / "mouse-received"
        pane = self.recorder_pane("mouseapp", received, mouse=True)
        wait_until(lambda: self.client_pane(client) == pane, "client on the program's pane")

        self.click_pane(client, pane)
        wait_until(
            lambda: received.exists() and b"\x1b[<2;" in received.read_bytes(),
            "the program receives the right-click",
        )
        # The menu is not drawn over it: a following key reaches the program.
        client.send(b"q")
        wait_until(lambda: received.read_bytes().endswith(b"q"), "keys still go to the program")

        time.sleep(0.6)
        self.click_pane(client, pane, meta=True)
        self.wait_drawn(client, b"Split side by side", "Option-right-click opens the menu")
        # The menu takes C-c, which closes it, so only q reaches the program.
        # (A client's first Escape after attaching can be read as the start
        # of a terminal reply, so these cases close menus with C-c.)
        before = received.read_bytes()
        client.send(b"\x03")
        client.pump(0.2)
        client.send(b"q")
        wait_until(lambda: received.read_bytes() == before + b"q", "the menu has closed")

    def test_menu_items_grey_out_where_they_cannot_apply(self) -> None:
        """Greyed items ignore their key; the same items work when they apply.

        After each greyed key the menu must still be open, so a following key
        that applies proves the greyed one was ignored rather than chosen.
        """
        client = Client(self)
        self.clients.append(client)
        # One window holding one pane: zoom and moving the window cannot apply.
        self.tmux("kill-pane", "-t", self.inactive)
        window = self.show(self.active, "#{window_id}")

        def windows() -> list[str]:
            return self.tmux("list-windows", "-F", "#{window_id}").stdout.split()

        client.send(b"\x02>")
        self.wait_drawn(client, b"Zoom", "prefix > opens the pane menu")
        client.send(b"z")
        client.pump(0.3)
        client.send(b"%")
        wait_until(lambda: self.show(window, "#{window_panes}") == "2", "the menu stays open")
        self.assertEqual("0", self.show(window, "#{window_zoomed_flag}"), "zoom is greyed out")

        client.send(b"\x02<")
        self.wait_drawn(client, b"Move left", "prefix < opens the window menu")
        client.send(b"l")
        client.send(b"r")
        client.pump(0.3)
        self.assertEqual([window], windows(), "moving the only window is greyed out")
        client.send(b"c")
        wait_until(lambda: len(windows()) == 2, "the window menu stays open")
        self.assertEqual(window, windows()[0])

        # Back on the first window, which now has two panes, zoom applies.
        self.tmux("select-window", "-t", window)
        wait_until(
            lambda: self.tmux("list-clients", "-F", "#{window_id}").stdout.strip() == window,
            "client back on the first window",
        )
        client.send(b"\x02>")
        self.wait_drawn(client, b"Zoom", "prefix > opens the pane menu again")
        client.send(b"z")
        wait_until(lambda: self.show(window, "#{window_zoomed_flag}") == "1", "zoom applies")

    def test_the_window_menu_acts_on_the_tab_clicked(self) -> None:
        """Right-click background tabs to move, rename and close them."""
        client = Client(self)
        self.clients.append(client)
        # A fixed-width status-left lets the clicks aim at the tabs.
        self.tmux("set-option", "-g", "status-left", "[S] ")
        first = self.show(self.active, "#{window_id}")
        self.tmux("rename-window", "-t", first, "one")
        second = self.tmux(
            "new-window", "-d", "-n", "two", "-P", "-F", "#{window_id}", "sleep 30"
        ).stdout.strip()
        third = self.tmux(
            "new-window", "-d", "-n", "three", "-P", "-F", "#{window_id}", "sleep 30"
        ).stdout.strip()

        def order() -> list[str]:
            return self.tmux("list-windows", "-F", "#{window_id}").stdout.split()

        self.assertEqual([first, second, third], order())
        # "[S] " then " 1:one " then a space: tab two starts at cell 13.
        self.right_click(client, 15, 1)
        self.wait_drawn(client, b"Move right", "a right-click on a tab opens its window menu")
        client.send(b"r")
        wait_until(lambda: order() == [first, third, second], "the clicked window moves right")
        # A right-click selects the tab, as it selects a pane: since tmux 3.8
        # a background tab's menu would draw on that hidden window.
        self.assertEqual(second, self.tmux("list-clients", "-F", "#{window_id}").stdout.strip())

        # Renaming starts from the clicked window's name and renames it.
        time.sleep(0.6)
        self.right_click(client, 15, 1)
        self.wait_drawn(client, b"Rename...", "the moved tab's menu opens")
        client.send(b",")
        self.wait_drawn(client, b"three", "the prompt starts from the clicked window's name")
        # A quote in the answer stays data (tmux 3.2 reparses the template).
        client.send(b'!"\r')
        wait_until(
            lambda: self.show(third, "#{window_name}") == 'three!"', "the clicked window is renamed"
        )
        self.assertEqual("one", self.show(first, "#{window_name}"))
        self.assertEqual(third, self.tmux("list-clients", "-F", "#{window_id}").stdout.strip())

        # ' 2:three!" ' now sits where " 2:two " was; " 3:two " starts at cell 25.
        # Closing asks first, as prefix X does, then returns to the window
        # you were on.
        time.sleep(0.6)
        self.right_click(client, 27, 1)
        self.wait_drawn(client, b"Close the window...", "the last tab's menu opens")
        client.send(b"X")
        self.wait_drawn(client, b"kill-window two? (y/n)", "closing names the window and asks")
        client.send(b"y")
        wait_until(lambda: order() == [first, third], "the clicked window closes")
        self.assertEqual(third, self.tmux("list-clients", "-F", "#{window_id}").stdout.strip())

        # The session name opens the session menu, whose rename renames the
        # client's session.
        time.sleep(0.6)
        self.right_click(client, 2, 1)
        self.wait_drawn(client, b"Renumber windows", "the session menu opens")
        client.send(b"$")
        self.wait_drawn(client, b"focus", "the prompt starts from the session's name")
        client.send(b"!\r")
        wait_until(
            lambda: self.tmux("list-clients", "-F", "#{session_name}").stdout.strip() == "focus!",
            "the session is renamed",
        )

    def test_option_space_opens_the_command_palette(self) -> None:
        """Pick a binding in the palette and see it run on the pane left.

        A stand-in fzf picks the entry named by $PALETTE_PICK. The helper is
        tmux-tools' tmux-command-palette; without it, the key says so.
        """
        client = Client(self)
        self.clients.append(client)
        path = self.tmux("show-environment", "-g", "PATH", check=False).stdout.strip()
        base_path = path.partition("=")[2] if path.startswith("PATH=") else os.environ["PATH"]
        # Dropping the helper's directory may drop this tmux with it (both
        # install into ~/.local/bin), so keep the same tmux first on PATH.
        same_tmux = self.root / "tmux-bin"
        same_tmux.mkdir()
        (same_tmux / "tmux").symlink_to(shutil.which("tmux") or "tmux")
        without_helper = ":".join(
            [str(same_tmux)]
            + [
                d
                for d in base_path.split(":")
                if d and not (pathlib.Path(d) / "tmux-command-palette").exists()
            ]
        )
        self.tmux("set-environment", "-g", "PATH", without_helper)
        client.send(b"\x1b ")
        wait_until(
            lambda: (
                "needs tmux-command-palette" in self.tmux("show-messages", "-t", client.tty).stdout
            ),
            "Option-Space without the helper says what it needs",
        )
        helper = shutil.which("tmux-command-palette", path=base_path)
        if helper is None:
            self.skipTest("tmux-tools' tmux-command-palette is not installed")

        stub = self.root / "palette-bin"
        stub.mkdir()
        (stub / "tmux-command-palette").symlink_to(helper)
        offered = self.root / "offered"
        fzf = stub / "fzf"
        fzf.write_text(
            "#!/bin/sh\n"
            f"cat >'{offered}.tmp' && mv '{offered}.tmp' '{offered}'\n"
            '[ -n "$PALETTE_PICK" ] || exit 130\n'
            f"grep -F -m 1 -- \"$PALETTE_PICK\" '{offered}'\n"
        )
        fzf.chmod(0o755)
        self.tmux("set-environment", "-g", "PATH", f"{stub}:{without_helper}")
        record = self.root / "palette-record"
        self.tmux(
            "bind-key",
            "-N",
            "Record the pane for the palette test",
            "F12",
            "run-shell",
            f"echo #{{pane_id}} >>'{record}'",
        )
        version = self.tmux("-V").stdout
        match = re.search(r"(\d+)\.(\d+)", version)
        types_for_client = match is not None and (int(match[1]), int(match[2])) >= (3, 4)

        def palette(pick: str) -> None:
            offered.unlink(missing_ok=True)
            self.tmux("set-environment", "-g", "PALETTE_PICK", pick)
            client.send(b"\x1b ")
            wait_until(offered.exists, "the palette offers the noted bindings")

        pane = self.client_pane(client)
        palette("Record the pane for the palette test")
        entries = offered.read_text()
        self.assertRegex(entries, r"(?m)^Open the pane menu +prefix >\tprefix\t>$")
        self.assertRegex(entries, r"(?m)^Open the command palette +M-Space\troot\tM-Space$")
        self.assertNotIn("MouseDown3", entries, "mouse bindings are left out")
        if not types_for_client:
            wait_until(
                lambda: "Press F12" in self.tmux("show-messages", "-t", client.tty).stdout,
                "older tmux names the key to press",
            )
            client.send(b"\x1b[24~")
        wait_until(
            lambda: record.exists() and record.read_text() == f"{pane}\n",
            "the picked binding runs on the pane the palette came from",
        )

        # A nested tmux reporting mouse gets the key, so its own palette opens.
        received = self.root / "nested-received"
        nested = self.recorder_pane("tmux", received, mouse=True)
        offered.unlink(missing_ok=True)
        client.send(b"\x1b ")
        wait_until(
            lambda: received.exists() and received.read_bytes().endswith(b"\x1b "),
            "Option-Space goes to the nested tmux",
        )
        self.assertFalse(offered.exists(), "this layer opens no palette")
        # In copy mode the pane shows this layer's history, so it keeps the key.
        self.tmux("copy-mode", "-t", nested)
        palette("")
        self.assertEqual(b"\x1b ", received.read_bytes()[-2:])

    def test_terminal_render_paints_the_focused_leaf_night_owl_blue(self) -> None:
        # Remove unrelated status-line and inactive-pane background sequences
        # so the captured SGR color is the pane body tmux actually painted.
        self.tmux("kill-pane", "-t", self.inactive)
        self.tmux("set-option", "-g", "status", "off")
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)
        # The focus hook is asynchronous. Reconcile explicitly before reading
        # pixels so slower CI hosts cannot capture the inactive style between
        # the client flag transition and the publisher's pane update.
        self.sync_client(client)

        leaf_render = client.redraw_until_background(
            (2, 28, 48),
            "focused leaf background",
        )
        self.assertEqual(
            (2, 28, 48),
            self.rendered_background(leaf_render),
            repr(leaf_render),
        )

        client.set_focus(False)
        self.sync_client(client)
        # set_focus() drains the asynchronous hook repaint while waiting for
        # the authoritative client flag to settle. Request a deterministic
        # redraw here rather than depending on a second, optional repaint.
        blurred_render = client.redraw_until_background(
            (1, 13, 23),
            "unfocused leaf background",
        )
        self.assertEqual(
            (1, 13, 23),
            self.rendered_background(blurred_render),
            repr(blurred_render),
        )

        client.set_focus(True)
        self.sync_client(client)
        refocused_render = client.redraw_until_background(
            (2, 28, 48),
            "refocused leaf background",
        )
        self.assertEqual(
            (2, 28, 48),
            self.rendered_background(refocused_render),
            repr(refocused_render),
        )

        self.claim_child()
        container_render = client.redraw_until_background(
            (1, 13, 23),
            "focused child container background",
        )
        self.assertEqual(
            (1, 13, 23),
            self.rendered_background(container_render),
            repr(container_render),
        )

        self.release_child()
        restored_render = client.redraw_until_background(
            (2, 28, 48),
            "released child background",
        )
        self.assertEqual(
            (2, 28, 48),
            self.rendered_background(restored_render),
            repr(restored_render),
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=pathlib.Path)
    parser.add_argument("--focus", type=pathlib.Path)
    parser.add_argument("--clip", type=pathlib.Path)
    parser.add_argument("--prompt", type=pathlib.Path)
    arguments, unittest_arguments = parser.parse_known_args()
    LeafStyleTest.config = arguments.config
    LeafStyleTest.focus = arguments.focus
    LeafStyleTest.clip = arguments.clip
    LeafStyleTest.prompt = arguments.prompt
    program = unittest.main(argv=[__file__, *unittest_arguments], verbosity=2, exit=False)
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
