"""The tmux version rule the tmux PTY drivers share.

master and OpenBSD's base tmux (openbsd-*) are newer than any release;
otherwise one leading next- is ignored and the leading MAJOR.MINOR
compares, so 3.3a, 3.3-rc and next-3.3 all read as 3.3. A version this
cannot read counts as newest, as tmux.conf's guard and tests/helpers.sh do.
The floor is tmux.conf's "# tmux minimum:" marker.
"""

from __future__ import annotations

import os
import pathlib
import re

_RELEASE = re.compile(r"(\d+)\.(\d+)")
_MARKER = re.compile(r"^# tmux minimum: (\d+)\.(\d+)$", re.MULTILINE)


def parse(version: str) -> tuple[int, int] | None:
    """Return (major, minor), or None for a build newer than any release."""
    version = version.strip().removeprefix("tmux ")
    if version == "master" or version.startswith("openbsd-"):
        return None
    match = _RELEASE.match(version.removeprefix("next-"))
    return None if match is None else (int(match[1]), int(match[2]))


def at_least(version: str, minimum: tuple[int, int]) -> bool:
    """Whether VERSION is MINIMUM or newer; unreleased and unknown builds are."""
    release = parse(version)
    return release is None or release >= minimum


def minimum(config: pathlib.Path | None = None) -> tuple[int, int]:
    """The floor stated in tmux.conf, by default the source home's."""
    if config is None:
        home = os.environ.get("DOT_TEST_SOURCE_HOME") or str(pathlib.Path.home())
        config = pathlib.Path(home) / ".config/tmux/tmux.conf"
    match = _MARKER.search(config.read_text())
    if match is None:
        raise RuntimeError(f"{config} states no '# tmux minimum:' floor")
    return int(match[1]), int(match[2])


def supported(version: str, config: pathlib.Path | None = None) -> bool:
    """Whether VERSION meets the floor."""
    return at_least(version, minimum(config))
