#!/usr/bin/env python3
"""Render Codex config TOML in the exact shape the shell merge expects."""

from __future__ import annotations

import json
import re
import sys
from typing import Any

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")
USAGE = "usage: toml-render.py render-json JSON"


def toml_key(name: str) -> str:
    if BARE_KEY.match(name):
        return name
    return json.dumps(name)


def scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if value is None:
        raise TypeError("null is not supported in TOML")
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list) and not any(isinstance(v, dict) for v in value):
        return "[" + ", ".join(scalar(v) for v in value) + "]"
    raise TypeError(f"unsupported TOML value: {value!r}")


def section(prefix: tuple[str, ...]) -> str:
    return ".".join(toml_key(part) for part in prefix)


def emit_body(table: dict[str, Any], prefix: tuple[str, ...], lines: list[str]) -> None:
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

    # TOML parsers attach following scalar assignments to the current table.
    # Emit root/table scalars before child tables so yq-merged root values stay
    # at the semantic level Codex expects.
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


def render_table(table: dict[str, Any], prefix: tuple[str, ...] = ()) -> str:
    lines: list[str] = []
    emit_body(table, prefix, lines)
    return "\n".join(lines).rstrip() + "\n"


def render_json(path: str) -> None:
    with open(path, encoding="utf-8") as handle:
        merged = json.load(handle)
    print(render_table(merged), end="")


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(USAGE, file=sys.stderr)
        return 2

    command = argv[1]
    if command == "render-json" and len(argv) == 3:
        render_json(argv[2])
        return 0

    print(USAGE, file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
