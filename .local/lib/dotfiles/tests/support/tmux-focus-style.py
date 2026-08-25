#!/usr/bin/env python3
"""Verify leaf-focus styles through real per-client tmux format expansion."""

from __future__ import annotations

import argparse
import os
import pathlib
import pty
import select
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
        self.pump(0.25)

    def _find_tty(self) -> bool:
        listing = self.test.tmux("list-clients", "-F", "#{client_pid} #{client_tty}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == str(self.pid):
                tty = fields[1]
                self.tty = tty
                return True
        return False

    def pump(self, duration: float) -> None:
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            ready, _, _ = select.select([self.master], [], [], 0.02)
            if not ready:
                continue
            payload = os.read(self.master, 65536)
            if b"\x1b[?996n" in payload:
                os.write(self.master, b"\x1b[?997;1n")

    def set_focus(self, focused: bool) -> None:
        os.write(self.master, b"\x1b[I" if focused else b"\x1b[O")
        self.pump(0.08)
        expected = "focused" if focused else "unfocused"
        wait_until(
            lambda: self.test.client_is_focused(self.tty) is focused,
            f"{expected} client flag",
        )

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
    """Check background, border, and label styles in each client context."""

    config: pathlib.Path

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
        self.socket = self.root / "tmux.sock"
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

    def test_focus_hooks_are_client_scoped_and_ignore_control_mode(self) -> None:
        start_hooks = self.hook("client-attached") + "\n" + self.hook("client-focus-in")
        stop_hooks = self.hook("client-focus-out") + "\n" + self.hook("client-detached")
        for hooks in (start_hooks, stop_hooks):
            self.assertIn("#{==:#{client_control_mode},0}", hooks)
            self.assertIn("--tmux-socket #{q:socket_path}", hooks)
            self.assertIn("--client-pid #{client_pid}", hooks)
            self.assertIn("--client-tty #{q:client_tty}", hooks)
        self.assertIn("termnav-tmux-focus watch", start_hooks)
        self.assertIn("termnav-tmux-focus stop", stop_hooks)

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
            "bg=#010d17",
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

        self.tmux(
            "set-option",
            "-p",
            "-t",
            self.active,
            "@termnav_child_focus",
            "0123456789abcdef01234567:9999999999999999",
        )
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

        self.tmux("set-option", "-pu", "-t", self.active, "@termnav_child_focus")
        second.set_focus(True)
        self.assertEqual(
            "bg=#011627",
            self.expand(second.tty, self.active, "window-active-style"),
        )
        self.assertEqual(
            "bg=#010d17",
            self.expand(second.tty, self.inactive, "window-active-style"),
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=pathlib.Path)
    arguments, unittest_arguments = parser.parse_known_args()
    LeafStyleTest.config = arguments.config
    program = unittest.main(argv=[__file__, *unittest_arguments], verbosity=2, exit=False)
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
