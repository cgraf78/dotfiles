"""Run independent PTY test groups with bounded process ownership."""

from __future__ import annotations

import contextlib
import errno
import os
import pathlib
import signal
import subprocess
import sys
import tempfile
import time

from tmux_paths import short_temporary_parent

_darwin_waitid = None


def worker_exited(pid: int) -> bool:
    """Observe worker completion without freeing the PID that reserves its group."""
    required = ("waitid", "P_PID", "WEXITED", "WNOHANG", "WNOWAIT")
    if all(hasattr(os, name) for name in required):
        try:
            info = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        except InterruptedError:
            return False
        observed = info.si_pid if info is not None else 0
    elif sys.platform == "darwin":
        # CPython can omit waitid on macOS even though libc exposes it.
        # Reserve 128 aligned bytes for siginfo_t, whose si_pid is at byte 12.
        # Darwin wait.h defines P_PID=1, WEXITED=4, WNOHANG=1, WNOWAIT=32.
        import ctypes

        global _darwin_waitid
        if _darwin_waitid is None:
            try:
                _darwin_waitid = ctypes.CDLL(None, use_errno=True).waitid
            except AttributeError as error:
                raise RuntimeError("Darwin libc waitid is unavailable") from error
            _darwin_waitid.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
            _darwin_waitid.restype = ctypes.c_int
        info = (ctypes.c_uint64 * 16)()
        if _darwin_waitid(1, pid, info, 4 | 1 | 32) != 0:
            error = ctypes.get_errno()
            if error == errno.EINTR:
                return False
            raise OSError(error, os.strerror(error))
        observed = ctypes.c_int32.from_buffer(info, 12).value
    else:
        raise RuntimeError("non-reaping waitid is required for PTY workers")
    if observed not in (0, pid):
        raise RuntimeError(f"waitid returned PID {observed} for worker {pid}")
    return observed == pid


def wait_for_worker(pid: int, timeout: float | None = None) -> None:
    """Wait for completion or the grace deadline while leaving the group owned."""
    deadline = None if timeout is None else time.monotonic() + timeout
    while not worker_exited(pid):
        if deadline is not None and time.monotonic() >= deadline:
            break
        time.sleep(0.01)


def signal_worker(pid: int, signum: int) -> None:
    """Signal the exact unreaped worker's group, including surviving children."""
    worker_exited(pid)
    try:
        os.killpg(pid, signum)
    except ProcessLookupError:
        return
    except PermissionError:
        if sys.platform != "darwin":
            raise
        # A Darwin group can refuse a signal as its last live process exits.
        # Defer judgment until the final signal, then require a group snapshot.
        if signum == signal.SIGKILL:
            snapshot = subprocess.run(
                ["/bin/ps", "-axo", "pgid=,stat="],
                capture_output=True,
                text=True,
                check=True,
                timeout=2,
            )
            if any(
                int(group) == pid and not status.startswith("Z")
                for group, status in (line.split() for line in snapshot.stdout.splitlines())
            ):
                raise


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
                    wait_for_worker(worker.pid)
            finally:
                primary_error = sys.exc_info()[0]
                errors = []
                # A second Ctrl-C must not interrupt ownership cleanup.
                for stop in previous:
                    signal.signal(stop, signal.SIG_IGN)
                # Signal every live group before waiting on any of them. The
                # driver unwinds unittest cleanups, including daemonized tmux
                # servers that no longer belong to the worker's process group.
                if primary_error is not None:
                    for worker, _, _ in workers:
                        try:
                            signal_worker(worker.pid, signal.SIGINT)
                        except (OSError, RuntimeError) as error:
                            errors.append(f"worker {worker.pid} interrupt: {error}")
                for worker, output, root in workers:
                    try:
                        if primary_error is not None:
                            wait_for_worker(worker.pid, timeout=15)
                        signal_worker(worker.pid, signal.SIGKILL)
                    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
                        errors.append(f"worker {worker.pid} group cleanup: {error}")
                    try:
                        worker.wait(timeout=2)
                    except subprocess.TimeoutExpired as error:
                        errors.append(str(error))
                        # No group operations follow this direct-child fallback.
                        try:
                            worker.kill()
                            worker.wait(timeout=1)
                        except (OSError, subprocess.TimeoutExpired) as kill_error:
                            errors.append(str(kill_error))
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
            return int(any(worker.returncode for worker, _, _ in workers))
    finally:
        for stop, handler in previous.items():
            signal.signal(stop, handler)
