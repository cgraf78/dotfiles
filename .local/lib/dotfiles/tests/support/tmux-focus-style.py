#!/usr/bin/env python3
"""Verify client-scoped base tmux focus styling through real PTYs."""

from __future__ import annotations

import argparse
import os
import pathlib
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

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
        try:
            os.kill(self.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            waited, _ = os.waitpid(self.pid, os.WNOHANG)
            if waited == self.pid:
                break
            time.sleep(0.02)
        else:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(self.pid, 0)
        os.close(self.master)


class LeafStyleTest(unittest.TestCase):
    """Check rendering and key dispatch in an isolated real tmux client."""

    config: pathlib.Path
    focus: pathlib.Path | None

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
        self.clients: list[Client] = []

    def tearDown(self) -> None:
        for client in reversed(self.clients):
            client.close()
        self.tmux("kill-server", check=False)
        self.temporary.cleanup()

    def tmux(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["tmux", "-S", str(self.socket), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
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

    def test_pending_panes_are_marked_until_visited(self) -> None:
        if not self.supports_hook("pane-focus-in"):
            self.skipTest("tmux does not expose pane focus hooks")
        client = Client(self)
        self.clients.append(client)
        if not self.supports_client_format_context(client.tty):
            self.skipTest("tmux does not support client-targeted format expansion")
        client.set_focus(True)
        tab = "window-status-current-format"

        # An agent beside the focused pane notified: its border and the
        # current tab both say so.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "1")
        self.assertIn("●", self.expand(client.tty, self.inactive, "pane-border-format"))
        self.assertIn(" ●", self.expand(client.tty, self.active, tab))
        self.assertNotIn("●", self.expand(client.tty, self.active, "pane-border-format"))

        # Visiting the pane acknowledges it.
        self.tmux("select-pane", "-t", self.inactive)
        wait_until(lambda: self.pending(self.inactive) == "", "pending cleared on focus-in")
        self.assertNotIn("●", self.expand(client.tty, self.inactive, tab))

        # A pane that notified while focused is not advertised, and leaving
        # it does not light it up.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "1")
        self.assertNotIn("●", self.expand(client.tty, self.inactive, tab))
        self.assertNotIn("●", self.expand(client.tty, self.inactive, "pane-border-format"))
        self.tmux("select-pane", "-t", self.active)
        wait_until(lambda: self.pending(self.inactive) == "", "pending cleared on focus-out")

        # While the terminal is unfocused the active pane is not being looked
        # at, so it shows as pending until the terminal regains focus.
        client.set_focus(False)
        self.tmux("set-option", "-p", "-t", self.active, "@term_notify_pending", "1")
        self.assertIn("●", self.expand(client.tty, self.active, "pane-border-format"))
        client.set_focus(True)
        wait_until(lambda: self.pending(self.active) == "", "pending cleared on refocus")

        # A failed command in the side pane carries a red status until visited.
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_exit_status", "2")
        self.tmux("set-option", "-p", "-t", self.inactive, "@term_notify_pending", "1")
        self.assertIn("! exit 2", self.expand(client.tty, self.inactive, "pane-border-format"))
        self.assertIn(" !", self.expand(client.tty, self.active, tab))
        # Check drawn colors, not just format strings: pop-default alone does
        # not reset the drawing style, and nested pushes overwrite tmux's own.
        self.tmux("set-window-option", "window-status-current-style", "fg=#123456,bg=#234567")
        self.tmux("set-window-option", tab, "BEFORE#{E:@window_marker} AFTER")
        rendered = client.redraw()
        suffix = re.search(rb" !(.*?) AFTER", rendered, re.DOTALL)
        self.assertIsNotNone(suffix, repr(rendered))
        self.assertRegex(suffix.group(1), rb"\x1b\[38(?:;2;18;52;86|:2::18:52:86)m")
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
        self.assertNotIn("! exit", self.expand(client.tty, self.inactive, "pane-border-format"))

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
        self.assertIn(" ●", self.expand(client.tty, background, "window-status-format"))
        self.tmux("select-window", "-t", background)
        wait_until(lambda: self.pending(background) == "", "pending cleared on window visit")

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
        background = self.tmux(
            "new-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
        ).stdout.strip()
        for pane in (background, self.inactive):
            self.tmux("set-option", "-p", "-t", pane, "@term_notify_pending", "1")

        # Tab order wins over the order the panes asked: the pane beside you
        # in window 1 comes before the one in window 2.
        self.press(client, b"a")
        wait_until(
            lambda: self.current_pane(client) == self.inactive, "jump to the first pending pane"
        )
        wait_until(lambda: self.pending(self.inactive) == "", "arrival acknowledges the pane")
        self.assertEqual("1", self.pending(background))

        self.press(client, b"a")
        wait_until(
            lambda: self.current_pane(client) == background, "jump into the background window"
        )
        wait_until(lambda: self.pending(background) == "", "arrival acknowledges the window's pane")

        # With nothing pending the key says so and stays put.
        self.press(client, b"a")
        wait_until(
            lambda: "Nothing is waiting" in self.tmux("show-messages").stdout,
            "empty-queue message",
        )
        self.assertEqual(background, self.current_pane(client))

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
            f'[ -e "{self.root}/empty" ] && exit 3\n'
            f'[ -e "{self.root}/old" ] && exit 64\n'
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
            self.press(client, b"A")

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
    arguments, unittest_arguments = parser.parse_known_args()
    LeafStyleTest.config = arguments.config
    LeafStyleTest.focus = arguments.focus
    program = unittest.main(argv=[__file__, *unittest_arguments], verbosity=2, exit=False)
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
