#!/usr/bin/env python3
"""Exercise the working tab spinner on a private tmux server."""

from __future__ import annotations

import fcntl
import os
import pty
import shutil
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from pathlib import Path

SOURCE = Path(sys.argv.pop(1)).resolve()
FRAMES = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


class SpinnerTest(unittest.TestCase):
    """Check rendered frames without touching the user's tmux server."""

    def setUp(self) -> None:
        tmp_root = Path("/tmp") if Path("/tmp").is_dir() else None
        self.temp = tempfile.TemporaryDirectory(prefix="tspin.", dir=tmp_root)
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.socket = root / "s"
        self.home = root / "home"
        (self.home / ".local/bin").mkdir(parents=True)
        (self.home / ".config/terminal").mkdir(parents=True)
        source_helper = SOURCE / ".local/bin/term-tab-spinner"
        self.assertTrue(source_helper.is_file(), "term-tab-spinner helper is missing")
        shutil.copy2(source_helper, self.home / ".local/bin/term-tab-spinner")
        continuum = self.home / ".local/bin/tmux-continuum-default-server"
        continuum.write_text("#!/bin/sh\nexit 0\n")
        continuum.chmod(0o755)
        collector = self.home / ".local/bin/term-pane-state"
        collector.write_text('#!/bin/sh\nprintf x >>"$HOME/collector"\n')
        collector.chmod(0o755)
        shutil.copy2(
            SOURCE / ".config/terminal/working-spinner.frames",
            self.home / ".config/terminal/working-spinner.frames",
        )
        self.env = os.environ.copy()
        self.env.update(
            HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.home / ".config"),
            PATH=str(self.home / ".local/bin") + os.pathsep + self.env["PATH"],
            TERM="xterm-256color",
            LANG="C.UTF-8",
            LC_ALL="C.UTF-8",
        )
        self.tmux("-f", "/dev/null", "new-session", "-d", "-s", "spinner", "exec sleep 30")
        self.addCleanup(lambda: self.tmux("kill-server", check=False))
        self.tmux("source-file", str(SOURCE / ".config/tmux/conf.d/10-base.conf"))
        self.pane = self.tmux("display-message", "-p", "#{pane_id}").stdout.strip()
        self.wait_for(
            "sleep test pane",
            lambda: (
                self.tmux("display-message", "-p", "#{pane_current_command}").stdout.strip()
                == "sleep"
            ),
        )

    def tmux(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        """Run one command against the invocation-owned server."""
        result = subprocess.run(
            ["tmux", "-S", str(self.socket), *args],
            env=self.env if hasattr(self, "env") else None,
            text=True,
            capture_output=True,
        )
        if check and result.returncode != 0:
            self.fail(
                f"tmux {' '.join(args)} failed ({result.returncode}): "
                f"{result.stdout} {result.stderr}"
            )
        return result

    def value(self, option: str) -> str:
        """Read one server option from the private server."""
        return self.tmux("show-option", "-sv", option, check=False).stdout.strip()

    def marker(self, pane: str | None = None) -> str:
        """Render the actual window marker for one test pane."""
        return self.tmux(
            "display-message", "-p", "-t", pane or self.pane, "#{E:@window_marker}"
        ).stdout.strip()

    def wait_for(self, description: str, condition, seconds: float = 2) -> None:
        """Poll an observable condition until a bounded deadline."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if condition():
                return
            time.sleep(0.03)
        command = self.tmux(
            "display-message", "-p", "#{pane_current_command}", check=False
        ).stdout.strip()
        self.fail(
            f"timed out waiting for {description}; frame={self.value('@term_tab_spinner_frame')}; "
            f"pane_command={command}"
        )

    @staticmethod
    def alive(pid: int) -> bool:
        """Treat an unreaped zombie as exited, including on macOS without /proc."""
        result = subprocess.run(
            ["ps", "-o", "stat=", "-p", str(pid)], text=True, capture_output=True
        )
        return result.returncode == 0 and not result.stdout.lstrip().startswith("Z")

    def test_busy_tab_advances_frames(self) -> None:
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        seen: set[str] = set()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and len(seen) < 3:
            seen.update(frame for frame in FRAMES if frame in self.marker())
            time.sleep(0.05)
        self.assertGreaterEqual(len(seen), 3, f"spinner frames seen: {seen}")

    def test_idle_tab_stays_static(self) -> None:
        self.assertNotIn("⠋", self.marker())
        self.assertEqual("⋯", self.value("@term_tab_spinner_frame"))

    def test_background_work_keeps_attention_visible(self) -> None:
        other = self.tmux(
            "new-window", "-d", "-P", "-F", "#{pane_id}", "exec sleep 30"
        ).stdout.strip()
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        self.tmux("set-option", "-p", "-t", self.pane, "@term_notify_pending", "1")
        self.wait_for("busy frame", lambda: self.value("@term_tab_spinner_frame") in FRAMES)
        marker = self.marker(self.pane)
        self.assertTrue(any(frame in marker for frame in FRAMES), marker)
        self.assertIn("●", marker)
        self.assertNotIn("●", self.marker(other))

    def test_stale_busy_mark_on_shell_does_not_spin(self) -> None:
        shell = self.tmux(
            "new-window",
            "-d",
            "-P",
            "-F",
            "#{pane_id}",
            'bash -c "sleep 30; :"',
        ).stdout.strip()
        self.wait_for(
            "shell command",
            lambda: (
                self.tmux(
                    "display-message", "-p", "-t", shell, "#{pane_current_command}"
                ).stdout.strip()
                == "bash"
            ),
        )
        self.tmux("set-option", "-p", "-t", shell, "@term_busy", "1")
        self.assertEqual("", self.marker(shell))
        self.assertEqual("⋯", self.value("@term_tab_spinner_frame"))

    def test_clear_hides_spinner_and_stops_updates(self) -> None:
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        self.wait_for("first busy frame", lambda: self.value("@term_tab_spinner_frame") in FRAMES)
        self.tmux("set-option", "-pu", "-t", self.pane, "@term_busy")
        self.assertNotIn("⠋", self.marker())
        self.wait_for("idle fallback", lambda: self.value("@term_tab_spinner_frame") == "⋯")

    def test_reload_replaces_old_helper(self) -> None:
        self.wait_for("initial owner", lambda: bool(self.value("@term_tab_spinner_owner")))
        old = self.value("@term_tab_spinner_owner")
        old_pid = int(old.split(":", 1)[0])
        self.tmux("source-file", str(SOURCE / ".config/tmux/conf.d/10-base.conf"))
        self.wait_for("new owner", lambda: self.value("@term_tab_spinner_owner") != old)
        self.wait_for("old helper exit", lambda: not self.alive(old_pid))

    def test_missing_frames_falls_back_to_static_mark(self) -> None:
        self.wait_for("initial owner", lambda: bool(self.value("@term_tab_spinner_owner")))
        owner_pid = int(self.value("@term_tab_spinner_owner").split(":", 1)[0])
        (self.home / ".config/terminal/working-spinner.frames").unlink()
        self.tmux("source-file", str(SOURCE / ".config/tmux/conf.d/10-base.conf"))
        self.wait_for("old helper exit", lambda: not self.alive(owner_pid))
        self.wait_for("fallback owner cleanup", lambda: not self.value("@term_tab_spinner_owner"))
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        self.assertIn("⋯", self.marker())

    def test_missing_helper_retires_previous_owner(self) -> None:
        self.wait_for("initial owner", lambda: bool(self.value("@term_tab_spinner_owner")))
        owner_pid = int(self.value("@term_tab_spinner_owner").split(":", 1)[0])
        (self.home / ".local/bin/term-tab-spinner").unlink()
        self.tmux("source-file", str(SOURCE / ".config/tmux/conf.d/10-base.conf"))
        self.wait_for("old helper exit", lambda: not self.alive(owner_pid))
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        self.assertIn("⋯", self.marker())

    def test_frame_file_cannot_inject_tmux_commands(self) -> None:
        self.wait_for("initial owner", lambda: bool(self.value("@term_tab_spinner_owner")))
        owner_pid = int(self.value("@term_tab_spinner_owner").split(":", 1)[0])
        (self.home / ".config/terminal/working-spinner.frames").write_text("⠋ ; kill-server\n⠙\n")
        self.tmux("source-file", str(SOURCE / ".config/tmux/conf.d/10-base.conf"))
        self.wait_for("old helper exit", lambda: not self.alive(owner_pid))
        self.wait_for("fallback owner cleanup", lambda: not self.value("@term_tab_spinner_owner"))
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            self.assertEqual(0, self.tmux("has-session", check=False).returncode)
            time.sleep(0.03)

    def test_server_shutdown_reaps_helper(self) -> None:
        self.wait_for("initial owner", lambda: bool(self.value("@term_tab_spinner_owner")))
        owner_pid = int(self.value("@term_tab_spinner_owner").split(":", 1)[0])
        self.tmux("kill-server")
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline and self.alive(owner_pid):
            time.sleep(0.03)
        self.assertFalse(self.alive(owner_pid), f"helper {owner_pid} survived tmux server shutdown")

    def test_busy_spinner_preserves_collector_heartbeat(self) -> None:
        self.tmux("set-option", "-g", "status-right", "")
        master, slave = pty.openpty()

        def controlling_tty() -> None:
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

        client = subprocess.Popen(
            ["tmux", "-S", str(self.socket), "attach-session", "-t", "spinner"],
            env=self.env,
            stdin=slave,
            stdout=slave,
            stderr=slave,
            preexec_fn=controlling_tty,
        )
        os.close(slave)

        def close_client() -> None:
            if client.poll() is None:
                client.kill()
            client.wait(timeout=2)
            os.close(master)

        self.addCleanup(close_client)
        self.wait_for(
            "attached client", lambda: bool(self.tmux("list-clients", check=False).stdout)
        )
        self.tmux("set-option", "-p", "-t", self.pane, "@term_busy", "1")
        self.wait_for(
            "collector publication during a short busy turn",
            lambda: (self.home / "collector").exists(),
            seconds=2,
        )
        self.tmux("set-option", "-pu", "-t", self.pane, "@term_busy")


if __name__ == "__main__":
    unittest.main()
