"""Render opt-in iTerm2 Dynamic Profiles from the shared terminal settings."""

from __future__ import annotations

import argparse
import copy
import json
import sys
from pathlib import Path

from terminal_settings import cursor_type, rgb

APPEARANCE = "Dotfiles Appearance"
DEFAULT = "Dotfiles Default"
PROFILE_REFERENCE = "Dotfiles Profile"
HEX_ACTION = 11
MODIFIERS = {"SHIFT": 0x20000, "CTRL": 0x40000, "ALT": 0x80000, "OPT": 0x80000, "SUPER": 0x100000}
FUNCTION_KEYS = {
    "UpArrow": 0xF700,
    "DownArrow": 0xF701,
    "LeftArrow": 0xF702,
    "RightArrow": 0xF703,
    "PageUp": 0xF72C,
    "PageDown": 0xF72D,
}


def color(value: str) -> dict:
    """Encode iTerm2's native sRGB component dictionary."""
    red, green, blue = rgb(value)
    return {
        "Color Space": "sRGB",
        "Alpha Component": 1.0,
        "Red Component": red,
        "Green Component": green,
        "Blue Component": blue,
    }


def key_sequence(binding: dict) -> tuple[str, dict]:
    """Translate portable key modifiers and literal bytes into iTerm2's key map."""
    key = binding["key"]
    modifiers = binding["mods"].split("|")
    mask = sum(MODIFIERS[modifier] for modifier in modifiers)
    if key in FUNCTION_KEYS:
        code = FUNCTION_KEYS[key]
        # iTerm2 normalizes the numeric-pad bit only for the four arrows,
        # not PageUp/PageDown. Its lookup otherwise uses the exact mask.
        if key.endswith("Arrow"):
            mask |= 0x200000
    elif key == "Enter":
        code = 13
    elif len(key) == 1:
        code = ord(key.upper() if "SHIFT" in modifiers else key)
    else:
        raise ValueError(f"unsupported shared key {key!r}")
    text = " ".join(f"0x{byte:x}" for byte in binding["text"].encode("utf-8"))
    return f"0x{code:x}-0x{mask:x}", {"Action": HEX_ACTION, "Text": text}


def apply_appearance(profile: dict, settings: dict) -> None:
    """Apply shared appearance and supported portable behavior to one managed profile."""
    font = f"{settings['font']['postscript_name']} {settings['macos_font_size']:g}"
    profile.update(
        {
            "Normal Font": font,
            "Non Ascii Font": font,
            "Columns": settings["initial_cols"],
            "Rows": settings["initial_rows"],
            "Horizontal Spacing": settings["spacing"]["horizontal"],
            "Vertical Spacing": settings["spacing"]["vertical"],
            "Cursor Type": cursor_type("iterm2", settings["cursor"]["shape"]),
            "Blinking Cursor": settings["cursor"]["blink"],
            "Scrollback Lines": settings["scrollback_lines"],
            "Terminal Type": settings["terminal_type"],
            "ASCII Ligatures": settings["ligatures"],
            "Non-ASCII Ligatures": settings["ligatures"],
        }
    )
    colors = settings["colors"]
    for key in list(profile):
        if key.endswith((" (Light)", " (Dark)")):
            del profile[key]
    for native, shared in {
        "Background Color": "background",
        "Foreground Color": "foreground",
        "Bold Color": "foreground",
        "Cursor Color": "cursor_bg",
        "Cursor Text Color": "cursor_fg",
    }.items():
        profile[native] = color(colors[shared])
    palette = colors["ansi"] + colors["brights"]
    if len(colors["ansi"]) != 8 or len(colors["brights"]) != 8:
        raise ValueError("ANSI and bright palettes must each contain eight colors")
    for index, value in enumerate(palette):
        profile[f"Ansi {index} Color"] = color(value)
    keys = profile.setdefault("Keyboard Map", {})
    for binding in settings["send_keys"]:
        if binding["platform"] in ("all", "macos"):
            key, action = key_sequence(binding)
            keys[key] = action


def render(source: dict, settings: dict) -> tuple[dict, str]:
    """Render managed entries, preserving custom entries and returning the default GUID."""
    if not isinstance(source, dict):
        raise ValueError("iTerm2 source must be an object")
    result = copy.deepcopy(source)
    profiles = result.get("Profiles")
    if not isinstance(profiles, list):
        raise ValueError("iTerm2 source must contain a Profiles array")
    default_guid = ""
    seen = set()
    for profile in profiles:
        if not isinstance(profile, dict) or not all(
            isinstance(profile.get(key), str) and profile[key] for key in ("Name", "Guid")
        ):
            raise ValueError("every iTerm2 profile requires a nonempty Name and Guid")
        if profile["Guid"] in seen:
            raise ValueError("duplicate iTerm2 profile GUID in source")
        seen.add(profile["Guid"])
        key_map = profile.get("Keyboard Map", {})
        if not isinstance(key_map, dict) or any(
            not isinstance(action, dict) for action in key_map.values()
        ):
            raise ValueError("Keyboard Map and its actions must be objects")
        for action in key_map.values():
            if action.pop(PROFILE_REFERENCE, False):
                action["Text"] = profile["Guid"]
        if profile.pop(APPEARANCE, False):
            apply_appearance(profile, settings)
        if profile.pop(DEFAULT, False):
            if default_guid:
                raise ValueError("only one default profile may be selected per source")
            default_guid = profile["Guid"]
    return result, default_guid


def main() -> int:
    """Validate and render into caller-owned staging storage before publication."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--settings", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        raw = args.source.read_text()
        source = json.loads(raw)
        if not isinstance(source, dict):
            raise ValueError("iTerm2 source must be an object")
        needs_settings = any(
            p.get(APPEARANCE) for p in source.get("Profiles", []) if isinstance(p, dict)
        )
        settings = json.loads(args.settings.read_text()) if needs_settings else {}
        result, guid = render(source, settings)
        # Raw custom fragments retain their exact formatting; managed metadata
        # is removed so only native iTerm2 attributes reach the application.
        args.output.write_text(raw if result == source else json.dumps(result, indent=2) + "\n")
        if guid:
            print(guid)
    except (OSError, KeyError, ValueError, TypeError) as error:
        print(f"iTerm2 profile: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
