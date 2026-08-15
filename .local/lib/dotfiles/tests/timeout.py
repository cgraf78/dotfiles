#!/usr/bin/env python3
"""Run one command under a portable process-group timeout."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from collections.abc import Sequence
from pathlib import Path
from types import FrameType

process: subprocess.Popen | None = None
interrupted_signal: int | None = None
handled_signals = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


class ForwardedSignal(Exception):
    """Indicate that the supervisor received a cancellation signal."""


def parse_timeout(value: str) -> float:
    """Convert a timeout value with an optional s, m, h, or d suffix."""
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    multiplier = units.get(value[-1:], 1)
    if value[-1:] in units:
        value = value[:-1]
    return float(value) * multiplier


def capture_signal(signum: int, _frame: FrameType | None) -> None:
    """Record cancellation and interrupt a blocking wait once a child exists."""
    global interrupted_signal
    interrupted_signal = signum
    if process is not None:
        raise ForwardedSignal


def mark_timeout_expired() -> None:
    """Record that the supervisor, rather than the child, produced status 124."""
    marker = os.environ.get("DOT_TEST_TIMEOUT_EXPIRED_FILE")
    if not marker:
        return
    try:
        Path(marker).write_text("", encoding="utf-8")
    except OSError:
        # Failure to publish optional retry metadata must not replace the
        # command's authoritative timeout status.
        pass


def list_session_pids(session_id: int) -> list[int] | None:
    """Return a portable PID snapshot for one session, or None when unavailable."""
    try:
        result = subprocess.run(
            ["ps", "-A", "-o", "pid="],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None

    pids: list[int] = []
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) != 1:
            return None
        try:
            pid = int(fields[0])
        except ValueError:
            return None
        try:
            if os.getsid(pid) == session_id:
                pids.append(pid)
        except (PermissionError, ProcessLookupError):
            pass
    return pids


def stop_process_group(first_signal: int) -> None:
    """Stop the entire child session, then reap its leader."""
    assert process is not None
    for handled_signal in handled_signals:
        signal.signal(handled_signal, signal.SIG_IGN)

    def send_process_group_signal(signum: int) -> bool:
        """Signal the original process group when session enumeration is unavailable."""
        try:
            os.killpg(process.pid, signum)
        except AttributeError:
            try:
                process.send_signal(signum)
            except (PermissionError, ProcessLookupError):
                return False
        except (PermissionError, ProcessLookupError):
            return False
        return True

    def send_signal(signum: int) -> bool:
        """Signal revalidated members of the child session."""
        pids = list_session_pids(process.pid)
        if pids is None:
            return send_process_group_signal(signum)

        found_member = False
        for pid in pids:
            try:
                # The ps output is only a candidate snapshot. Re-check the SID
                # immediately before signaling so PID reuse cannot widen scope.
                if os.getsid(pid) != process.pid:
                    continue
                found_member = True
                os.kill(pid, signum)
            except (PermissionError, ProcessLookupError):
                pass
        if found_member:
            return True

        # A portable PID snapshot can race with a still-running leader. The
        # original process group remains a safe fallback because this wrapper
        # created that leader and session itself.
        if process.poll() is None:
            return send_process_group_signal(signum)
        return False

    if not send_signal(first_signal):
        process.wait()
        return
    time.sleep(1)
    send_signal(signal.SIGKILL)
    process.wait()


def main(argv: Sequence[str]) -> int:
    """Run the requested command and return a shell-compatible status."""
    global process

    timeout = parse_timeout(argv[1])
    for handled_signal in handled_signals:
        signal.signal(handled_signal, capture_signal)

    child_env = os.environ.copy()
    child_env.pop("DOT_TEST_TIMEOUT_EXPIRED_FILE", None)
    try:
        process = subprocess.Popen(argv[2:], start_new_session=True, env=child_env)
    except FileNotFoundError:
        return 127
    except OSError:
        return 126

    try:
        if interrupted_signal is not None:
            raise ForwardedSignal
        wrapper_pid_file = os.environ.get("DOT_TEST_TIMEOUT_WRAPPER_PID_FILE")
        if wrapper_pid_file:
            Path(wrapper_pid_file).write_text(str(os.getpid()), encoding="utf-8")
        status = process.wait(timeout=timeout)
    except ForwardedSignal:
        assert interrupted_signal is not None
        stop_process_group(interrupted_signal)
        return 128 + interrupted_signal
    except subprocess.TimeoutExpired:
        mark_timeout_expired()
        stop_process_group(signal.SIGTERM)
        return 124

    stop_process_group(signal.SIGTERM)
    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
