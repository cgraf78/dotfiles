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


def stop_process_group(first_signal: int) -> None:
    """Stop the entire child session, then reap its leader."""
    assert process is not None
    for handled_signal in handled_signals:
        signal.signal(handled_signal, signal.SIG_IGN)
    try:
        os.killpg(process.pid, first_signal)
    except ProcessLookupError:
        process.wait()
        return
    time.sleep(1)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (PermissionError, ProcessLookupError):
        pass
    process.wait()


def main(argv: Sequence[str]) -> int:
    """Run the requested command and return a shell-compatible status."""
    global process

    timeout = parse_timeout(argv[1])
    for handled_signal in handled_signals:
        signal.signal(handled_signal, capture_signal)

    try:
        process = subprocess.Popen(argv[2:], start_new_session=True)
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
        stop_process_group(signal.SIGTERM)
        return 124

    return status if status >= 0 else 128 - status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
