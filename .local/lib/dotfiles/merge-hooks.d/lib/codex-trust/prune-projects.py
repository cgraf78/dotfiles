#!/usr/bin/env python3
"""Prune stale Codex project-trust stanzas from a Codex config file.

Codex records ``[projects."<path>"]`` trust entries as it runs, including
throwaway locations (``/tmp`` scratch dirs, deleted checkouts) and absolute
paths from other machines. This helper removes entries that can never be
legitimate local trust on this machine and rewrites the file atomically.

An entry is removed only when all of these hold:

* the key is an absolute path and the stanza sets
  ``trust_level = "trusted"`` (explicit non-trusted stanzas are user intent
  and are always preserved);
* the path is neither ``$HOME`` nor below it;
* the path is not rooted at one of the current user's home directories
  (``/Users/$USER``, ``/home/$USER``, ``/data/users/$USER``), so managed
  layers that declare same-user trust on every platform are never fought;
* the path is the system temp dir (or below it), another user's home
  directory (or below it), an over-broad multi-user root (``/Users``,
  ``/home``, ``/data/users``), or simply does not exist.

Usage: prune-projects.py CONFIG

Exit 0 rewrites CONFIG in place (or leaves it untouched when nothing is
stale) and prints each pruned path on stdout. Any failure leaves CONFIG
untouched and exits 1 with a diagnostic on stderr.
"""

from __future__ import annotations

import getpass
import json
import os
import pathlib
import re
import sys
from collections.abc import Mapping
from typing import Any

import tomllib

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")

# Home-directory roots shared by every platform this client runs on. Entries
# below the *current user's* directory on any of these layouts are managed
# policy (declared by the Codex config layers), never cruft.
HOME_ROOTS = ("/Users", "/home", "/data/users")

# Trusting a whole multi-user root is never legitimate local policy.
OVERBROAD_ROOTS = frozenset(HOME_ROOTS)


def toml_key(name: str) -> str:
    """Return ``name`` as a TOML bare key or quoted key."""
    if BARE_KEY.match(name):
        return name
    return json.dumps(name)


def scalar(value: Any) -> str:
    """Serialize scalar TOML values used by Codex config."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list) and not any(isinstance(v, dict) for v in value):
        return "[" + ", ".join(scalar(v) for v in value) + "]"
    raise TypeError(f"unsupported TOML value: {value!r}")


def section(prefix: tuple[str, ...]) -> str:
    """Serialize a TOML section path."""
    return ".".join(toml_key(part) for part in prefix)


def emit_body(table: Mapping[str, Any], prefix: tuple[str, ...], lines: list[str]) -> None:
    """Emit TOML with scalars before child tables so root keys stay at root."""
    scalars = []
    children = []
    arrays = []

    for name, value in table.items():
        if isinstance(value, dict):
            children.append((name, value))
        elif isinstance(value, list) and any(isinstance(v, dict) for v in value):
            arrays.append((name, value))
        else:
            scalars.append((name, value))

    for name, value in scalars:
        lines.append(f"{toml_key(name)} = {scalar(value)}")

    for name, value in children:
        if lines and lines[-1] != "":
            lines.append("")
        lines.append(f"[{section((*prefix, name))}]")
        emit_body(value, (*prefix, name), lines)

    for name, items in arrays:
        for item in items:
            if not isinstance(item, dict):
                raise TypeError(f"mixed scalar/table array at {section((*prefix, name))}")
            if lines and lines[-1] != "":
                lines.append("")
            lines.append(f"[[{section((*prefix, name))}]]")
            emit_body(item, (*prefix, name), lines)


def normalize(path: str) -> str:
    """Lexically normalize a trusted path for prefix comparison.

    Purely lexical: nothing is resolved, so missing paths and symlinks
    compare by the literal spelling Codex recorded.
    """
    if path != "/" and path.endswith("/"):
        path = path.rstrip("/") or "/"
    return path


def under(path: str, root: str) -> bool:
    """Return True when ``path`` is ``root`` or a directory below it."""
    if root == "/":
        return path.startswith("/")
    return path == root or path.startswith(root + "/")


def account_user() -> str:
    """Return the current account name, or "" when it cannot be determined."""
    user = os.environ.get("USER") or os.environ.get("LOGNAME") or ""
    if user:
        return "" if "/" in user else user
    try:
        user = getpass.getuser()
    except Exception:
        return ""
    return "" if "/" in user else user


def account_home() -> str:
    """Return the current home directory for trust comparison."""
    home = os.environ.get("HOME") or ""
    if home:
        return normalize(home)
    return normalize(os.path.expanduser("~"))


def temp_roots() -> set[str]:
    """Return temp-dir spellings that count as ephemeral trust.

    ``/tmp`` is a symlink to ``/private/tmp`` on macOS, so both spellings
    are stale by construction. ``realpath`` is a no-op on Linux.
    """
    roots = {"/tmp"}
    try:
        resolved = normalize(os.path.realpath("/tmp"))
    except OSError:
        resolved = ""
    if resolved.startswith("/"):
        roots.add(resolved)
    return roots


def is_other_user_home(path: str, user: str) -> bool:
    """Return True when ``path`` is another user's home (or below one)."""
    if not user:
        # Without an account name there is no safe way to tell another
        # user's home from the caller's own: keep the entry.
        return False
    for root in HOME_ROOTS:
        if path == root or not path.startswith(root + "/"):
            continue
        first = path[len(root) + 1 :].split("/", 1)[0]
        if first and first != user:
            return True
    return False


def should_prune(path: str, home: str, user: str, tmp_dirs: set[str]) -> bool:
    """Return True when a trusted project path is stale cruft."""
    if under(path, home):
        return False
    if user and any(under(path, f"{root}/{user}") for root in HOME_ROOTS):
        # Same-user homes on foreign layouts are managed-layer policy (the
        # Codex config layers declare them on every platform), not cruft.
        # Pruning them would churn against the merge on every update.
        return False
    if path in OVERBROAD_ROOTS or any(under(path, tmp) for tmp in tmp_dirs):
        return True
    if is_other_user_home(path, user):
        return True
    return not os.path.exists(path)


def prune_projects(config: dict[str, Any], home: str, user: str, tmp_dirs: set[str]) -> list[str]:
    """Remove stale entries from ``config["projects"]`` in place."""
    projects = config.get("projects")
    if not isinstance(projects, dict):
        return []
    pruned = []
    for path, entry in list(projects.items()):
        if (
            not isinstance(path, str)
            or not path.startswith("/")
            or not isinstance(entry, dict)
            or entry.get("trust_level") != "trusted"
        ):
            continue
        if should_prune(normalize(path), home, user, tmp_dirs):
            del projects[path]
            pruned.append(path)
    return pruned


def render(config: Mapping[str, Any]) -> str:
    """Serialize the config in the stable scalars-first TOML shape."""
    lines: list[str] = []
    emit_body(config, (), lines)
    return "\n".join(lines).rstrip() + "\n"


def replace_file(path: pathlib.Path, content: str) -> None:
    """Atomically replace ``path`` while preserving its permission bits."""
    mode = path.stat().st_mode & 0o7777
    tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}")
    try:
        tmp.write_text(content, encoding="utf-8")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: prune-projects.py CONFIG", file=sys.stderr)
        return 2

    config_path = pathlib.Path(argv[1])
    try:
        raw = config_path.read_bytes()
    except OSError as exc:
        print(f"prune-projects.py: cannot read {config_path}: {exc}", file=sys.stderr)
        return 1

    try:
        config = tomllib.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, tomllib.TOMLDecodeError) as exc:
        print(f"prune-projects.py: invalid TOML in {config_path}: {exc}", file=sys.stderr)
        return 1

    pruned = prune_projects(config, account_home(), account_user(), temp_roots())
    if not pruned:
        return 0

    try:
        rendered = render(config)
    except (TypeError, ValueError) as exc:
        print(f"prune-projects.py: cannot render {config_path}: {exc}", file=sys.stderr)
        return 1

    try:
        replace_file(config_path, rendered)
    except OSError as exc:
        print(f"prune-projects.py: cannot write {config_path}: {exc}", file=sys.stderr)
        return 1

    for path in pruned:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
