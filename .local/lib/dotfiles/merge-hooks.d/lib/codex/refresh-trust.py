#!/usr/bin/env python3
"""Refresh Codex hook trust hashes in a TOML config.

Codex stores trusted command hooks under ``hooks.state``. The state key uses the
resolved config path plus the event/group/handler indexes, and the hash is based
on Codex's canonical hook identity JSON. Keeping this logic in Python avoids
reimplementing TOML parsing and canonical JSON hashing in shell.
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import sys
from collections.abc import Iterable, Mapping, MutableMapping
from typing import Any

import tomllib

BARE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")

EVENT_LABELS = {
    "PreToolUse": "pre_tool_use",
    "PermissionRequest": "permission_request",
    "PostToolUse": "post_tool_use",
    "PreCompact": "pre_compact",
    "PostCompact": "post_compact",
    "SessionStart": "session_start",
    "SessionEnd": "session_end",
    "UserPromptSubmit": "user_prompt_submit",
    "Stop": "stop",
}

MATCHER_EVENTS = {
    "PreToolUse",
    "PermissionRequest",
    "PostToolUse",
    "PreCompact",
    "PostCompact",
    "SessionStart",
}


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


def section(prefix: Iterable[str]) -> str:
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


def command_hook_hash(event_name: str, matcher: str | None, hook: Mapping[str, Any]) -> str:
    """Return Codex's trusted hash for one command hook."""
    normalized_hook = {
        "type": "command",
        "command": hook["command"],
        "timeout": max(int(hook.get("timeout", 600)), 1),
        "async": bool(hook.get("async", False)),
    }
    if hook.get("statusMessage") is not None:
        normalized_hook["statusMessage"] = hook["statusMessage"]

    identity: dict[str, Any] = {
        "event_name": EVENT_LABELS[event_name],
        "hooks": [normalized_hook],
    }
    if matcher is not None:
        identity["matcher"] = matcher

    payload = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def matching_state_entry(
    state: Mapping[str, Any],
    config_path: pathlib.Path,
    suffix: str,
) -> Mapping[str, Any] | None:
    """Return existing state for the same hook through an equivalent path."""
    resolved_config = config_path.resolve()
    for old_key, old_entry in state.items():
        if (
            not old_key.endswith(suffix)
            or not isinstance(old_entry, dict)
            or "enabled" not in old_entry
        ):
            continue

        old_source = old_key[: -len(suffix)]
        if pathlib.Path(old_source).resolve() == resolved_config:
            return old_entry
    return None


def refresh_hook_state(config: MutableMapping[str, Any], config_path: pathlib.Path) -> None:
    """Update ``hooks.state`` trusted hashes in ``config`` in place."""
    hooks = config.get("hooks")
    if not isinstance(hooks, dict):
        return

    state = hooks.setdefault("state", {})
    if not isinstance(state, dict):
        state = {}
        hooks["state"] = state

    key_source = str(config_path.resolve())
    for event_name, groups in list(hooks.items()):
        if event_name == "state" or event_name not in EVENT_LABELS or not isinstance(groups, list):
            continue

        event_label = EVENT_LABELS[event_name]
        for group_index, group in enumerate(groups):
            if not isinstance(group, dict):
                continue

            matcher = group.get("matcher") if event_name in MATCHER_EVENTS else None
            group_hooks = group.get("hooks", [])
            if not isinstance(group_hooks, list):
                continue

            for handler_index, hook in enumerate(group_hooks):
                if not isinstance(hook, dict) or hook.get("type") != "command":
                    continue

                key = f"{key_source}:{event_label}:{group_index}:{handler_index}"
                entry = state.setdefault(key, {})
                if not isinstance(entry, dict):
                    entry = {}
                    state[key] = entry
                suffix = f":{event_label}:{group_index}:{handler_index}"
                if "enabled" not in entry:
                    old_entry = matching_state_entry(state, config_path, suffix)
                    if old_entry is not None:
                        entry["enabled"] = old_entry["enabled"]
                entry["trusted_hash"] = command_hook_hash(event_name, matcher, hook)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: refresh-trust.py CONFIG", file=sys.stderr)
        return 2

    config_path = pathlib.Path(sys.argv[1])
    config = tomllib.loads(config_path.read_text())
    refresh_hook_state(config, config_path)

    lines: list[str] = []
    emit_body(config, (), lines)
    print("\n".join(lines).rstrip() + "\n", end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
