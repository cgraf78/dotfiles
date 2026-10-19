"""Filesystem roots shared by the tmux PTY drivers."""

from __future__ import annotations

import os
import pathlib


def short_temporary_parent() -> str | None:
    """A writable short root for Unix sockets: /tmp, or Termux's $PREFIX/tmp.

    `dot test` points TMPDIR at a deep per-suite directory, so a socket below
    it can exceed the ~108-byte Unix socket path limit. Termux has no /tmp,
    which is why its prefix root is the fallback. None defers to TMPDIR.
    """
    roots = [pathlib.Path("/tmp")]
    if prefix := os.environ.get("PREFIX"):
        roots.append(pathlib.Path(prefix) / "tmp")
    return next(
        (str(root) for root in roots if root.is_dir() and os.access(root, os.W_OK | os.X_OK)),
        None,
    )
