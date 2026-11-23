#!/usr/bin/env python3
"""Exercise PTY worker scheduling, reporting, and process cleanup."""

from __future__ import annotations

import contextlib
import io
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from tmux_workers import run_workers


class WorkerTest(unittest.TestCase):
    """Use real child processes so serial execution or lost failures are visible."""

    def test_groups_overlap_and_report_each_result(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            commands = []
            for own, peer in (("first", "second"), ("second", "first")):
                commands.append(
                    [
                        sys.executable,
                        "-c",
                        "import pathlib, sys, time; "
                        "root = pathlib.Path(sys.argv[1]); "
                        "(root / sys.argv[2]).touch(); "
                        "deadline = time.monotonic() + 2; "
                        "\nwhile not (root / sys.argv[3]).exists():\n"
                        " if time.monotonic() >= deadline: sys.exit(9)\n"
                        " time.sleep(0.01)\n"
                        "print(sys.argv[2])",
                        str(root),
                        own,
                        peer,
                    ]
                )
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = run_workers(commands)
            self.assertEqual(0, status, "both workers must start before either finishes")
            self.assertEqual(["first", "second"], output.getvalue().splitlines())

    def test_failure_keeps_the_other_groups_output(self) -> None:
        commands = [
            [sys.executable, "-c", "print('failed case'); raise SystemExit(7)"],
            [sys.executable, "-c", "print('passing case')"],
        ]
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = run_workers(commands)
        self.assertEqual(1, status)
        self.assertEqual(["failed case", "passing case"], output.getvalue().splitlines())

    def test_partial_startup_reaps_the_started_worker(self) -> None:
        popen = subprocess.Popen
        started = []

        def launch(*args, **kwargs):
            worker = popen(*args, **kwargs)
            started.append(worker)
            return worker

        with (
            contextlib.redirect_stdout(io.StringIO()),
            patch("tmux_workers.Popen", side_effect=launch),
            self.assertRaises(FileNotFoundError),
        ):
            run_workers(
                [
                    [sys.executable, "-c", "import time; time.sleep(60)"],
                    ["/no-such-tmux-test-worker/executable"],
                ]
            )
        self.assertEqual(1, len(started))
        self.assertIsNotNone(started[0].returncode, "the first worker must be reaped")

    def test_signal_between_launch_and_registration_reaps_the_worker(self) -> None:
        popen = subprocess.Popen
        started = []

        def launch(*args, **kwargs):
            worker = popen(*args, **kwargs)
            started.append(worker)
            os.kill(os.getpid(), signal.SIGTERM)
            return worker

        with (
            contextlib.redirect_stdout(io.StringIO()),
            patch("tmux_workers.Popen", side_effect=launch),
            self.assertRaises(KeyboardInterrupt),
        ):
            run_workers([[sys.executable, "-c", "import time; time.sleep(60)"]])
        self.assertIsNotNone(started[0].returncode, "cancellation must not lose the new child")

    def test_cleanup_error_does_not_abandon_another_worker(self) -> None:
        popen = subprocess.Popen
        started = []

        def launch(*args, **kwargs):
            worker = popen(*args, **kwargs)
            started.append(worker)
            if len(started) == 2:
                os.kill(os.getpid(), signal.SIGTERM)
            return worker

        try:
            with (
                contextlib.redirect_stdout(io.StringIO()),
                contextlib.redirect_stderr(io.StringIO()),
                patch("tmux_workers.Popen", side_effect=launch),
                patch("tmux_workers.clean_servers", side_effect=ValueError("partial record")),
                self.assertRaises(KeyboardInterrupt),
            ):
                command = [sys.executable, "-c", "import time; time.sleep(60)"]
                run_workers([command, command])
            self.assertTrue(all(worker.returncode is not None for worker in started))
        finally:
            for worker in started:
                if worker.poll() is None:
                    worker.kill()
                worker.wait()

    def test_exited_worker_cannot_leave_a_tmux_daemon(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            record = pathlib.Path(directory) / "server"
            command = [
                sys.executable,
                "-c",
                "import os, pathlib, subprocess, sys; "
                "sys.path.insert(0, sys.argv[2]); "
                "from tmux_workers import record_server; "
                "socket = pathlib.Path(os.environ['DOT_TEST_TMUX_WORKER_ROOT']) / 'orphan.sock'; "
                "os.environ.update(HOME=str(socket.parent), SHELL='/bin/sh'); "
                "os.environ.pop('ENV', None); os.environ.pop('BASH_ENV', None); "
                "subprocess.run(['tmux', '-S', str(socket), '-f', '/dev/null', "
                "'new-session', '-d', 'sleep 60'], check=True); "
                "pid = int(subprocess.check_output(['tmux', '-S', str(socket), "
                "'display-message', '-p', '#{pid}'])); "
                "record_server(socket, pid); "
                "pathlib.Path(sys.argv[1]).write_text(str(pid) + '\\n' + str(socket)); "
                "sys.exit(7)",
                str(record),
                str(pathlib.Path(__file__).parent),
            ]
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(1, run_workers([command]))
                pid, socket = record.read_text().splitlines()
                deadline = time.monotonic() + 2
                while True:
                    process = subprocess.run(
                        ["ps", "-o", "args=", "-p", pid],
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    if socket not in process.stdout:
                        break
                    if time.monotonic() >= deadline:
                        self.fail(f"worker left its tmux daemon alive: {pid} {socket}")
                    time.sleep(0.01)
            finally:
                if record.exists():
                    pid, socket = record.read_text().splitlines()
                    process = subprocess.run(
                        ["ps", "-o", "args=", "-p", pid],
                        capture_output=True,
                        text=True,
                        check=False,
                    )
                    if socket in process.stdout:
                        with contextlib.suppress(ProcessLookupError):
                            os.kill(int(pid), signal.SIGKILL)

    def test_exited_worker_cannot_leave_a_same_group_child(self) -> None:
        """The worker's status must remain available after its group is cleaned."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            record = root / "child.pid"
            child = root / "owned-child.py"
            child.write_text("import time\ntime.sleep(10)\n")
            command = [
                sys.executable,
                "-c",
                (
                    "import pathlib, subprocess, sys; "
                    "child = subprocess.Popen([sys.executable, sys.argv[1]]); "
                    "pathlib.Path(sys.argv[2]).write_text(str(child.pid)); "
                    "raise SystemExit(7)"
                ),
                str(child),
                str(record),
            ]

            def child_alive(pid: int) -> bool:
                process = subprocess.run(
                    ["ps", "-o", "args=", "-p", str(pid)],
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=2,
                )
                return str(child) in process.stdout

            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(1, run_workers([command]))
                pid = int(record.read_text())
                deadline = time.monotonic() + 2
                while child_alive(pid):
                    if time.monotonic() >= deadline:
                        self.fail(f"worker left its same-group child alive: {pid}")
                    time.sleep(0.01)
            finally:
                if record.is_file():
                    pid = int(record.read_text())
                    if child_alive(pid):
                        with contextlib.suppress(ProcessLookupError):
                            os.kill(pid, signal.SIGKILL)

    def test_termination_unwinds_and_reaps_every_worker(self) -> None:
        for stop in (signal.SIGINT, signal.SIGTERM):
            with self.subTest(signal=stop), tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                child = root / "child.py"
                child.write_text(
                    "import os, pathlib, sys, time\n"
                    "root = pathlib.Path(sys.argv[1])\n"
                    "try:\n"
                    " root.with_suffix('.pid').write_text(str(os.getpid()))\n"
                    " while True: time.sleep(60)\n"
                    "finally: root.with_suffix('.cleaned').touch()\n"
                )
                command = [
                    sys.executable,
                    "-c",
                    "import sys; from tmux_workers import run_workers; "
                    "run_workers([[sys.executable, sys.argv[1], root] for root in sys.argv[2:]])",
                    str(child),
                    str(root / "first"),
                    str(root / "second"),
                ]
                with tempfile.TemporaryFile() as output:
                    coordinator = subprocess.Popen(
                        command,
                        cwd=pathlib.Path(__file__).parent,
                        stdout=output,
                        stderr=subprocess.STDOUT,
                        start_new_session=True,
                    )
                    try:
                        deadline = time.monotonic() + 5
                        while len(list(root.glob("*.pid"))) != 2:
                            if time.monotonic() >= deadline or coordinator.poll() is not None:
                                output.seek(0)
                                self.fail(f"workers did not start: {output.read()!r}")
                            time.sleep(0.01)
                        coordinator.send_signal(stop)
                        self.assertNotEqual(0, coordinator.wait(timeout=10))
                        self.assertEqual(2, len(list(root.glob("*.cleaned"))))
                        for pidfile in root.glob("*.pid"):
                            with self.assertRaises(ProcessLookupError):
                                os.kill(int(pidfile.read_text()), 0)
                    finally:
                        # The regression must remain safe when the coordinator
                        # fails to clean up: each PID must still name our script.
                        for pidfile in root.glob("*.pid"):
                            pid = int(pidfile.read_text())
                            process = subprocess.run(
                                ["ps", "-o", "args=", "-p", str(pid)],
                                capture_output=True,
                                text=True,
                                check=False,
                            )
                            if str(child) in process.stdout:
                                with contextlib.suppress(ProcessLookupError):
                                    os.killpg(pid, signal.SIGKILL)
                        if coordinator.poll() is None:
                            coordinator.kill()
                        coordinator.wait()


if __name__ == "__main__":
    unittest.main(verbosity=2)
