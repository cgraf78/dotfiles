"""Shared data conversions for native terminal profile adapters."""

import re

CURSORS = {
    "terminal": {"block": 0, "underline": 1, "bar": 2},
    "iterm2": {"underline": 0, "bar": 1, "block": 2},
}


def rgb(color: str) -> tuple[float, float, float]:
    """Convert the shared six-digit RGB syntax without changing its color space."""
    if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError(f"expected a six-digit RGB color, got {color!r}")
    return tuple(int(color[i : i + 2], 16) / 255 for i in (1, 3, 5))


def cursor_type(application: str, shape: str) -> int:
    """Translate a shared cursor shape into the application's native enum."""
    try:
        return CURSORS[application][shape]
    except KeyError as error:
        raise ValueError(f"unsupported cursor shape {shape!r} for {application}") from error
