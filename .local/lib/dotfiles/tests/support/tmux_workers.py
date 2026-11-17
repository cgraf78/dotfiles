"""Run independent PTY test groups with bounded process ownership."""

from __future__ import annotations

import contextlib
import os
import pathlib
import signal
import subprocess
import sys
import tempfile

from tmux_paths import short_temporary_parent


def interrupt(_signal: int, _frame: object) -> None:
    """Turn termination into an exception so unittest runs fixture cleanups."""
    raise KeyboardInterrupt


def record_server(socket: pathlib.Path, pid: int) -> None:
    """Keep daemon ownership available to the supervisor after a worker dies."""
    socket.with_suffix(socket.suffix + ".pid").write_text(str(pid))


def clean_servers(root: pathlib.Path) -> None:
    """Kill only recorded daemons whose command still names their private socket."""
    errors = []
    for record in root.rglob("*.sock.pid"):
        try:
            socket = str(record)[:-4]
            pid = int(record.read_text())
            # A daemon's PID may have been reused since it exited. The unique
            # socket path must still be in its command before we can signal it.
            process = subprocess.run(
                ["ps", "-o", "args=", "-p", str(pid)],
                text=True,
                capture_output=True,
                check=False,
                timeout=2,
            )
            if socket in process.stdout:
                with contextlib.suppress(ProcessLookupError):
                    os.kill(pid, signal.SIGKILL)
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            errors.append(f"{record}: {error}")
    if errors:
        raise RuntimeError(f"tmux daemon cleanup failed: {errors}")


def run_workers(commands: list[list[str]]) -> int:
    """Run at most two groups, preserving all output and any group's failure.

    Separate processes keep PTY forks and unittest's process-wide mocks from
    interfering. Files avoid pipe backpressure and keep each unittest result
    contiguous for tmux-test's per-case coverage checks.
    """
    if not 1 <= len(commands) <= 2:
        raise ValueError("expected one or two PTY test groups")
    workers = []
    launching = False
    cancelled = False

    def cancel(_signal: int, _frame: object) -> None:
        nonlocal cancelled
        if launching:
            # Returning lets Popen finish and lets us register the child.
            # Raising in this window could lose a successfully forked worker.
            cancelled = True
        else:
            raise KeyboardInterrupt

    previous = {stop: signal.signal(stop, cancel) for stop in (signal.SIGINT, signal.SIGTERM)}
    try:
        with contextlib.ExitStack() as stack:
            try:
                for command in commands:
                    output = stack.enter_context(tempfile.TemporaryFile(mode="w+"))
                    root = pathlib.Path(
                        stack.enter_context(
                            tempfile.TemporaryDirectory(prefix="dtw-", dir=short_temporary_parent())
                        )
                    )
                    launching = True
                    try:
                        worker = subprocess.Popen(
                            command,
                            stdout=output,
                            stderr=subprocess.STDOUT,
                            start_new_session=True,
                            env={**os.environ, "DOT_TEST_TMUX_WORKER_ROOT": str(root)},
                        )
                        workers.append((worker, output, root))
                    finally:
                        launching = False
                    if cancelled:
                        raise KeyboardInterrupt
                for worker, _, _ in workers:
                    worker.wait()
                return int(any(worker.returncode for worker, _, _ in workers))
            finally:
                primary_error = sys.exc_info()[0]
                errors = []
                # A second Ctrl-C must not interrupt ownership cleanup.
                for stop in previous:
                    signal.signal(stop, signal.SIG_IGN)
                # Signal every live group before waiting on any of them. The
                # driver unwinds unittest cleanups, including daemonized tmux
                # servers that no longer belong to the worker's process group.
                for worker, _, _ in workers:
                    if worker.poll() is None:
                        with contextlib.suppress(ProcessLookupError):
                            os.killpg(worker.pid, signal.SIGINT)
                for worker, output, root in workers:
                    try:
                        worker.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        with contextlib.suppress(ProcessLookupError):
                            os.killpg(worker.pid, signal.SIGKILL)
                        worker.wait()
                    try:
                        clean_servers(root)
                    except Exception as error:
                        # A damaged record must not abandon the next worker,
                        # especially one still awaiting forced termination.
                        errors.append(str(error))
                    output.seek(0)
                    print(output.read(), end="", flush=True)
                if errors:
                    message = f"PTY worker cleanup failed: {errors}"
                    if primary_error is None:
                        raise RuntimeError(message)
                    print(message, file=sys.stderr)
    finally:
        for stop, handler in previous.items():
            signal.signal(stop, handler)
