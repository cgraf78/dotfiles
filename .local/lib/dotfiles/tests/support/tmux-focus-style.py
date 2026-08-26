#!/usr/bin/env python3
"""Verify client-scoped tmux styling and navigation through real PTYs."""

from __future__ import annotations

import argparse
import os
import pathlib
import pty
import re
import select
import shlex
import signal
import subprocess
import tempfile
import time
import unittest


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
        short_root = pathlib.Path("/tmp")
        short_root_usable = short_root.is_dir() and os.access(short_root, os.W_OK | os.X_OK)
        temporary_parent = str(short_root) if short_root_usable else None
        self.temporary = tempfile.TemporaryDirectory(prefix="dot-focus-", dir=temporary_parent)
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
        return self.tmux(
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

    def active_pane(self, socket: pathlib.Path | None = None) -> str:
        """Return the active pane from this server or a nested fixture."""
        target = socket or self.socket
        completed = subprocess.run(
            ["tmux", "-S", str(target), "display-message", "-p", "#{pane_id}"],
            env=self.environment,
            text=True,
            capture_output=True,
            check=True,
        )
        return completed.stdout.strip()

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
        start_hooks = self.hook("client-attached") + "\n" + self.hook("client-focus-in")
        stop_hooks = self.hook("client-focus-out") + "\n" + self.hook("client-detached")
        sync_hooks = (
            self.hook("after-select-pane")
            + "\n"
            + self.hook("after-select-window")
            + "\n"
            + self.hook("client-session-changed")
        )
        for hooks in (start_hooks, stop_hooks):
            self.assertIn("#{==:#{client_control_mode},0}", hooks)
            self.assertIn("--tmux-socket #{q:socket_path}", hooks)
            self.assertIn("--client-pid #{client_pid}", hooks)
            self.assertIn("--client-tty #{q:client_tty}", hooks)
        self.assertIn("termnav-tmux-focus watch", start_hooks)
        self.assertIn("termnav-tmux-focus stop", stop_hooks)
        self.assertIn("termnav-tmux-focus sync", sync_hooks)
        self.assertIn("#{!=:#{@termnav_client_unfocused},}", sync_hooks)

    def test_styles_follow_each_client_and_child_claim(self) -> None:
        first = Client(self)
        second = Client(self)
        self.clients.extend((first, second))
        first.set_focus(True)
        second.set_focus(False)

        self.assertEqual(
            "bg=#011627",
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
            "bg=#011627",
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
            "bg=#011627",
            self.expand(second.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "bg=#010d17",
            self.expand(second.tty, self.inactive, "window-style"),
        )

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

        leaf_render = client.redraw()
        self.assertEqual(
            (1, 22, 39),
            self.rendered_background(leaf_render),
            repr(leaf_render),
        )

        client.set_focus(False)
        self.sync_client(client)
        # set_focus() drains the asynchronous hook repaint while waiting for
        # the authoritative client flag to settle. Request a deterministic
        # redraw here rather than depending on a second, optional repaint.
        blurred_render = client.redraw()
        self.assertEqual(
            (1, 13, 23),
            self.rendered_background(blurred_render),
            repr(blurred_render),
        )

        client.set_focus(True)
        self.sync_client(client)
        refocused_render = client.redraw()
        self.assertEqual(
            (1, 22, 39),
            self.rendered_background(refocused_render),
            repr(refocused_render),
        )

        self.claim_child()
        container_render = client.pump_until_quiet("child-claim repaint")
        self.assertEqual(
            (1, 13, 23),
            self.rendered_background(container_render),
            repr(container_render),
        )

        self.release_child()
        restored_render = client.pump_until_quiet("child-release repaint")
        self.assertEqual(
            (1, 22, 39),
            self.rendered_background(restored_render),
            repr(restored_render),
        )

    def test_ctrl_backslash_selects_the_local_previous_pane(self) -> None:
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)

        # Establish a deterministic last-pane pair, then send the exact C0
        # byte produced by WezTerm and VS Code. Going through the PTY catches
        # tmux key-name and escaping regressions that list-keys alone cannot.
        self.tmux("select-pane", "-t", self.active)
        self.tmux("select-pane", "-t", self.inactive)
        self.assertEqual(self.inactive, self.active_pane())
        client.send(b"\x1c")
        wait_until(lambda: self.active_pane() == self.active, "Ctrl-backslash pane selection")

    def test_ctrl_backslash_forwards_through_a_nested_tmux(self) -> None:
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)

        inner_socket = self.root / "inner socket.sock"
        inner_environment = self.environment.copy()
        inner_environment.pop("TMUX", None)
        inner_environment.pop("TMUX_PANE", None)

        def inner(*arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
            return subprocess.run(
                ["tmux", "-S", str(inner_socket), *arguments],
                env=inner_environment,
                text=True,
                capture_output=True,
                check=check,
            )

        try:
            inner("-f", str(self.config), "new-session", "-d", "-s", "nested", "sleep 30")
            inner_first = inner("display-message", "-p", "#{pane_id}").stdout.strip()
            inner_second = inner(
                "split-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
            ).stdout.strip()
            inner("select-pane", "-t", inner_first)
            inner("select-pane", "-t", inner_second)

            # Clear TMUX only for the nested client's startup check. The
            # terminal protocol still crosses the real outer PTY, which is
            # what sets mouse_any_flag and exercises the production forward.
            command = shlex.join(
                [
                    "env",
                    "TMUX=",
                    "TERM=tmux-256color",
                    "tmux",
                    "-S",
                    str(inner_socket),
                    "attach-session",
                    "-t",
                    "nested",
                ]
            )
            self.tmux("respawn-pane", "-k", "-t", self.active, command)
            self.tmux("select-pane", "-t", self.active)
            wait_until(
                lambda: (
                    self.tmux(
                        "display-message", "-p", "-t", self.active, "#{pane_current_command}"
                    ).stdout.strip()
                    == "tmux"
                ),
                "nested tmux foreground process",
            )

            # Service redraws and context probes while the inner client turns
            # on mouse reporting; then require the outer tmux to observe it.
            def nested_owns_mouse() -> bool:
                client.pump(0.02)
                return (
                    self.tmux(
                        "display-message", "-p", "-t", self.active, "#{mouse_any_flag}"
                    ).stdout.strip()
                    == "1"
                )

            wait_until(
                nested_owns_mouse,
                "nested tmux mouse ownership",
            )

            client.send(b"\x1c")
            wait_until(
                lambda: self.active_pane(inner_socket) == inner_first,
                "nested Ctrl-backslash previous-pane selection",
            )
            self.assertEqual(
                self.active,
                self.active_pane(),
                "the outer tmux must forward rather than consume the nested chord",
            )
        finally:
            inner("kill-server", check=False)


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
