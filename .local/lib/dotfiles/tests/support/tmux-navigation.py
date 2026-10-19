#!/usr/bin/env python3
"""Verify tmux pane navigation across editor and nested layers through real PTYs."""

from __future__ import annotations

import argparse
import fcntl
import itertools
import os
import pathlib
import pty
import re
import select
import shlex
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest

from tmux_paths import short_temporary_parent


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

    def __init__(self, test: NavigationTest | ClickRoutingTest, session: str = "navigation"):
        self.test = test
        self.pid, self.master = pty.fork()
        if self.pid == 0:
            os.environ.clear()
            os.environ.update(test.environment)
            os.environ["TERM"] = "xterm-256color"
            # A fixed size keeps click coordinates on the pane everywhere.
            fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
            os.execvp(
                "tmux",
                ["tmux", "-S", str(test.socket), "attach-session", "-t", session],
            )
        self.tty = ""
        wait_until(self._find_tty, "tmux client attachment")
        self.pump_until_quiet("initial tmux render")

    def _find_tty(self) -> bool:
        listing = self.test.tmux("list-clients", "-F", "#{client_pid} #{client_tty}", check=False)
        for line in listing.stdout.splitlines():
            fields = line.split(maxsplit=1)
            if len(fields) == 2 and fields[0] == str(self.pid):
                self.tty = fields[1]
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

    def send(self, payload: bytes) -> None:
        """Write raw terminal input without asking tmux to synthesize a key."""
        os.write(self.master, payload)

    def set_focus(self, focused: bool) -> None:
        """Send a focus transition and wait for tmux to observe it."""
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


class NavigationTest(unittest.TestCase):
    """Check Ctrl-backslash dispatch in an isolated real tmux client."""

    config: pathlib.Path

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="dot-navigation-", dir=short_temporary_parent()
        )
        self.root = pathlib.Path(self.temporary.name)
        self.socket = self.root / "tmux socket.sock"
        self.environment = os.environ.copy()
        for variable in (
            "TMUX",
            "TMUX_PANE",
            "TERMNAV_PARENT_RELAY",
            "TERMNAV_TMUX_SESSION",
        ):
            self.environment.pop(variable, None)
        self.environment["XDG_RUNTIME_DIR"] = str(self.root)
        self.tmux(
            "-f",
            str(self.config),
            "new-session",
            "-d",
            "-s",
            "navigation",
            "sleep 30",
        )
        self.active = self.active_pane()
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
                return "focused" in fields[1].split(",")
        return None

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

    def test_ctrl_backslash_selects_the_local_previous_pane(self) -> None:
        client = Client(self)
        self.clients.append(client)
        client.set_focus(True)
        self.tmux("select-pane", "-t", self.active)
        self.tmux("select-pane", "-t", self.inactive)
        self.assertEqual(self.inactive, self.active_pane())
        client.send(b"\x1c")
        wait_until(
            lambda: self.active_pane() == self.active,
            "Ctrl-backslash pane selection",
        )

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
            inner(
                "-f",
                str(self.config),
                "new-session",
                "-d",
                "-s",
                "nested",
                "sleep 30",
            )
            inner_first = inner("display-message", "-p", "#{pane_id}").stdout.strip()
            inner_second = inner(
                "split-window", "-d", "-P", "-F", "#{pane_id}", "sleep 30"
            ).stdout.strip()
            inner("select-pane", "-t", inner_first)
            inner("select-pane", "-t", inner_second)

            # tmux runs pane commands through `default-shell -c`. Only some
            # shells (bash, zsh) exec a lone simple command; dash and mksh
            # keep the shell in the foreground, so exec explicitly to make the
            # nested client the pane's foreground process everywhere.
            command = "exec " + shlex.join(
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
                        "display-message",
                        "-p",
                        "-t",
                        self.active,
                        "#{pane_current_command}",
                    ).stdout.strip()
                    == "tmux"
                ),
                "nested tmux foreground process",
            )

            def nested_owns_mouse() -> bool:
                client.pump(0.02)
                return (
                    self.tmux(
                        "display-message",
                        "-p",
                        "-t",
                        self.active,
                        "#{mouse_any_flag}",
                    ).stdout.strip()
                    == "1"
                )

            wait_until(nested_owns_mouse, "nested tmux mouse ownership")
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


# A fake terminal app: optional SGR mouse reporting (1 for button events, 2
# adds motion while a button is held), three link rows, then a raw-mode read
# loop logging every input byte. It runs under a copy of bash named after the
# app, so tmux reports that name as pane_current_command.
APP_SCRIPT = r"""
log=$1 mouse=$2
[ "$mouse" = 1 ] && printf '\033[?1000h\033[?1006h'
[ "$mouse" = 2 ] && printf '\033[?1002h\033[?1006h'
printf 'L1 \033]8;;https://example.com/osc8\033\\linked-text\033]8;;\033\\ end\n'
printf 'L2 \033]8;;file:///etc/hosts\033\\file-link\033]8;;\033\\ end\n'
printf 'L3 plain https://example.com/plain here\n'
stty raw -echo
while IFS= read -r -s -n 1 -d '' c; do printf '%s' "$c" >>"$log"; done
"""

# The binding runs ~/.local/bin/termnav; this one appends each click record
# follow-click would receive, ended by a "--" line, and ignores every other
# command. One write per record keeps a reader from seeing half of one.
TERMNAV_STUB = r"""#!/bin/sh
if [ "$1 $2 $3" = "tmux follow-click --stdin" ]; then
  record=$(cat)
  printf '%s\n--\n' "$record" >>"$DOT_TEST_FOLLOW_LOG"
fi
"""

# tmux forwards mouse events in pane coordinates, so match any cell.
CTRL_PRESS = re.compile(rb"\x1b\[<16;\d+;\d+M")
CTRL_RELEASE = re.compile(rb"\x1b\[<16;\d+;\d+m")
CTRL_DRAG = re.compile(rb"\x1b\[<48;\d+;\d+M")

# The config makes zsh the default shell when one is on PATH. This one keeps
# host startup files (and their writes) out of the fixture: it runs commands
# with /bin/sh.
SHELL_STUB = """#!/bin/sh
[ "$1" = -l ] && shift
exec /bin/sh "$@"
"""


def tmux_version() -> tuple[int, int]:
    """Return tmux's (major, minor); builds without a version number count as current."""
    text = subprocess.run(["tmux", "-V"], text=True, capture_output=True).stdout
    version = text.split()[-1].removeprefix("next-") if text.split() else ""
    major, _, rest = version.partition(".")
    minor = "".join(itertools.takewhile(str.isdigit, rest))
    if not major.isdigit():
        return (99, 0)
    return int(major), int(minor or 0)


class ClickRoutingTest(unittest.TestCase):
    """Check which layer receives a Ctrl-click in an isolated real tmux client."""

    config: pathlib.Path

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(
            prefix="dot-click-", dir=short_temporary_parent()
        )
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.socket = self.root / "click.sock"
        self.home = self.root / "home"
        self.bin = self.root / "bin"
        self.follow_log = self.root / "follow.log"
        (self.home / ".local/bin").mkdir(parents=True)
        self.bin.mkdir()
        termnav = self.home / ".local/bin/termnav"
        termnav.write_text(TERMNAV_STUB)
        termnav.chmod(0o755)
        (self.bin / "zsh").write_text(SHELL_STUB)
        (self.bin / "zsh").chmod(0o755)
        bash = shutil.which("bash")
        assert bash, "bash is required"
        for name in ("claude", "nvim", "ssh", "sh-shell"):
            shutil.copy(bash, self.bin / name)
        self.environment = {
            key: value
            for key, value in os.environ.items()
            if key not in ("TMUX", "TMUX_PANE", "TERMNAV_PARENT_RELAY", "TERMNAV_TMUX_SESSION")
        }
        self.environment.update(
            HOME=str(self.home),
            XDG_RUNTIME_DIR=str(self.root),
            PATH=f"{self.bin}:{self.environment.get('PATH', '/usr/bin:/bin')}",
            DOT_TEST_FOLLOW_LOG=str(self.follow_log),
        )
        # Start without the config and then load it, as the shell suites do:
        # an option an older tmux lacks is then a load error, not a message
        # tmux shows in view mode over the first pane.
        self.tmux(
            "-f",
            "/dev/null",
            "new-session",
            "-d",
            "-s",
            "click",
            "-x",
            "100",
            "-y",
            "30",
            "sleep 60",
        )
        self.addCleanup(self.tmux, "kill-server", check=False)
        self.tmux("source-file", str(self.config), check=False)
        # Two presses at one cell within tmux's double-click time (300 ms by
        # default) make the second a SecondClick event, so each click waits
        # that long out first.
        self.double_click_wait = 0.35
        self.client: Client | None = None

    def tearDown(self) -> None:
        if self.client is not None:
            self.client.close()

    def tmux(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["tmux", "-S", str(self.socket), *arguments],
            env=self.environment,
            text=True,
            capture_output=True,
            check=check,
        )

    def app(self, name: str, mouse: bool, motion: bool = False) -> tuple[str, pathlib.Path]:
        """Open a window running the fake app and wait until it is drawn."""
        log = self.root / f"{name}-{len(list(self.root.glob('*.input')))}.input"
        log.touch()
        mode = "2" if mouse and motion else "1" if mouse else "0"
        command = shlex.join([str(self.bin / name), "-c", APP_SCRIPT, name, str(log), mode])
        pane = self.tmux(
            "new-window", "-P", "-F", "#{pane_id}", "-t", "click:", f"exec {command}"
        ).stdout.strip()
        self.assertTrue(pane.startswith("%"), f"no pane id: {pane!r}")

        def drawn() -> bool:
            state = self.tmux(
                "display-message",
                "-p",
                "-t",
                pane,
                "#{pane_current_command} #{mouse_any_flag} #{pane_in_mode}",
            ).stdout.split()
            screen = self.tmux("capture-pane", "-p", "-t", pane).stdout
            return state == [name, "1" if mouse else "0", "0"] and "L3 plain" in screen

        wait_until(drawn, f"{name} drawn")
        if self.client is None:
            self.client = Client(self, session="click")
        self.client.pump(0.2)
        return pane, log

    def position(self, pane: str, needle: str) -> tuple[int, int]:
        """Return the 1-based client cell of the middle of needle's first row."""
        left, top, status, where = self.tmux(
            "display-message",
            "-p",
            "-t",
            pane,
            "#{pane_left} #{pane_top} #{status} #{status-position}",
        ).stdout.split()
        # pane_top counts from the window, which a top status line pushes down.
        status_lines = 0
        if where == "top":
            status_lines = 1 if status == "on" else int(status) if status.isdigit() else 0
        row_offset = int(top) + status_lines
        for row, line in enumerate(self.tmux("capture-pane", "-p", "-t", pane).stdout.splitlines()):
            if needle in line:
                return int(left) + line.index(needle) + len(needle) // 2 + 1, row_offset + row + 1
        raise AssertionError(f"{needle!r} is not on the pane")

    def records(self) -> list[list[str]]:
        """Every complete follow-click record so far, as its fields."""
        text = self.follow_log.read_text() if self.follow_log.exists() else ""
        return [chunk.split("\n") for chunk in text.split("\n--\n")[:-1]]

    def click(self, pane: str, needle: str, log: pathlib.Path) -> str:
        """Ctrl-click needle and return which layer took it: app or termnav."""
        assert self.client is not None
        x, y = self.position(pane, needle)
        before = len(self.records())
        app_before = len(log.read_bytes())
        time.sleep(self.double_click_wait)
        self.client.send(f"\x1b[<16;{x};{y}M\x1b[<16;{x};{y}m".encode())

        def taken() -> str | None:
            self.client.pump(0.02)
            if len(self.records()) > before:
                return "termnav"
            received = log.read_bytes()[app_before:]
            if CTRL_RELEASE.search(received):
                self.assertRegex(received, CTRL_PRESS, "the app must get the press too")
                return "app"
            return None

        result: list[str | None] = []
        wait_until(lambda: bool(result.append(taken()) or result[-1]), f"click on {needle}")
        layer = result[-1]
        if layer == "app":
            self.assertEqual(before, len(self.records()), "termnav must not also take the click")
        else:
            self.assertNotIn(
                b"\x1b[<", log.read_bytes()[app_before:], "the app must not see termnav's click"
            )
        return layer

    def mode(self, pane: str) -> str:
        return self.tmux("display-message", "-p", "-t", pane, "#{pane_mode}").stdout.strip()

    def test_an_agent_click_goes_to_termnav(self) -> None:
        pane, log = self.app("claude", mouse=True)
        self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")
        self.assertIn("https://example.com/plain", self.records()[-1][2])

    def test_an_editor_keeps_a_plain_click(self) -> None:
        pane, log = self.app("nvim", mouse=True)
        self.assertEqual(self.click(pane, "example.com/plain", log), "app")

    def test_a_shell_click_goes_to_termnav(self) -> None:
        pane, log = self.app("sh-shell", mouse=False)
        self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")

    def test_a_copy_mode_click_goes_to_termnav(self) -> None:
        pane, log = self.app("nvim", mouse=True)
        self.tmux("copy-mode", "-t", pane)
        self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")
        self.assertEqual(self.mode(pane), "copy-mode")

    def test_a_fast_second_click_never_reaches_an_agent(self) -> None:
        pane, log = self.app("claude", mouse=True)
        x, y = self.position(pane, "example.com/plain")
        click = f"\x1b[<16;{x};{y}M\x1b[<16;{x};{y}m".encode()
        assert self.client is not None
        time.sleep(self.double_click_wait)
        # The second press is a SecondClick event; which release events
        # follow varies by tmux release. A later click that reaches termnav
        # proves tmux has handled the pair.
        self.client.send(click + click)
        wait_until(lambda: len(self.records()) >= 1, "the first release through termnav")
        self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")
        self.assertNotIn(b"\x1b[<", log.read_bytes())

    def test_a_ctrl_drag_reaches_an_editor_but_never_an_agent(self) -> None:
        for name, forwarded in (("nvim", True), ("claude", False)):
            with self.subTest(app=name):
                pane, log = self.app(name, mouse=True, motion=True)
                x, y = self.position(pane, "example.com/plain")
                assert self.client is not None
                time.sleep(self.double_click_wait)
                self.client.send(
                    f"\x1b[<16;{x};{y}M\x1b[<48;{x + 1};{y}M\x1b[<16;{x + 1};{y}m".encode()
                )
                if forwarded:
                    wait_until(
                        lambda log=log: CTRL_RELEASE.search(log.read_bytes()) is not None,
                        f"{name} release",
                    )
                    self.assertRegex(log.read_bytes(), CTRL_DRAG)
                else:
                    # A release after a drag is a drag end, which termnav
                    # swallows. A later click that reaches termnav proves tmux
                    # has handled the whole drag.
                    self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")
                    self.assertNotIn(b"\x1b[<", log.read_bytes())
                self.assertEqual(self.mode(pane), "", "a drag must not open a view")

    def test_a_ctrl_drag_in_copy_mode_stays_in_copy_mode(self) -> None:
        # Neovim keeps drags outside a mode, so only the mode decides here.
        pane, log = self.app("nvim", mouse=True, motion=True)
        self.tmux("copy-mode", "-t", pane)
        x, y = self.position(pane, "example.com/plain")
        assert self.client is not None
        time.sleep(self.double_click_wait)
        self.client.send(f"\x1b[<16;{x};{y}M\x1b[<48;{x + 1};{y}M\x1b[<16;{x + 1};{y}m".encode())
        self.assertEqual(self.click(pane, "example.com/plain", log), "termnav")
        self.assertNotIn(b"\x1b[<", log.read_bytes())
        self.assertEqual(self.mode(pane), "copy-mode")

    def test_browser_links_go_to_termnav_and_file_links_stay(self) -> None:
        if tmux_version() < (3, 4):
            self.skipTest("tmux before 3.4 has no mouse_hyperlink")
        for name in ("nvim", "ssh"):
            with self.subTest(app=name):
                pane, log = self.app(name, mouse=True)
                self.assertEqual(self.click(pane, "linked-text", log), "termnav")
                self.assertEqual(self.records()[-1][0], "https://example.com/osc8")
                self.assertEqual(self.click(pane, "file-link", log), "app")
                self.assertEqual(self.click(pane, "example.com/plain", log), "app")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=pathlib.Path)
    arguments, unittest_arguments = parser.parse_known_args()
    NavigationTest.config = arguments.config
    ClickRoutingTest.config = arguments.config
    program = unittest.main(argv=[__file__, *unittest_arguments], verbosity=2, exit=False)
    return 0 if program.result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
