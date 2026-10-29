"""Install a managed macOS Terminal profile matching the shared WezTerm appearance."""

from __future__ import annotations

import argparse
import copy
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

DOMAIN = "com.apple.Terminal"
SETTINGS = "Window Settings"
DEFAULT = "Default Window Settings"
STARTUP = "Startup Window Settings"
ANSI_NAMES = ("Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White")


def archive(objects: list) -> bytes:
    """Encode the AppKit keyed-archive envelope used in Terminal preferences."""
    return plistlib.dumps(
        {
            "$version": 100000,
            "$archiver": "NSKeyedArchiver",
            "$top": {"root": plistlib.UID(1)},
            "$objects": ["$null", *objects],
        },
        fmt=plistlib.FMT_BINARY,
    )


def font_archive(name: str, size: float) -> bytes:
    """Encode a specific NSFont face and point size."""
    if not isinstance(name, str) or not name.strip():
        raise ValueError("shared appearance requires a nonempty font postscript_name")
    if not isinstance(size, (int, float)) or not 0 < size < 1000:
        raise ValueError("shared appearance requires a positive macOS font size")
    return archive(
        [
            {
                "NSSize": float(size),
                "NSfFlags": 16,
                "NSName": plistlib.UID(2),
                "$class": plistlib.UID(3),
            },
            name,
            {"$classname": "NSFont", "$classes": ["NSFont", "NSObject"]},
        ]
    )


def color_archive(color: str) -> bytes:
    """Encode an opaque sRGB NSColor; use the calibrated RGB archive convention."""
    if not isinstance(color, str) or not re.fullmatch(r"#[0-9a-fA-F]{6}", color):
        raise ValueError(f"expected a six-digit RGB color, got {color!r}")
    components = " ".join(f"{int(color[i : i + 2], 16) / 255:.10f}" for i in (1, 3, 5))
    return archive(
        [
            {"NSRGB": (components + "\0").encode(), "NSColorSpace": 1, "$class": plistlib.UID(2)},
            {"$classname": "NSColor", "$classes": ["NSColor", "NSObject"]},
        ]
    )


def initial_profiles(resources: Path) -> dict:
    """Retain Apple's built-in profiles on a never-launched Terminal installation."""
    profiles = {}
    for source in sorted(resources.glob("*.terminal")):
        profile = plistlib.loads(source.read_bytes())
        profiles[profile["name"]] = profile
    if not profiles:
        raise ValueError(f"no bundled Terminal profiles found in {resources}")
    return profiles


def merge(preferences: dict, appearance: dict, policy: dict) -> dict:
    """Preserve user profiles and select the fully managed profile for new sessions."""
    result = copy.deepcopy(preferences)
    profiles = result.setdefault(SETTINGS, {})
    if not isinstance(profiles, dict):
        raise ValueError("Terminal Window Settings must be a dictionary")
    profile = copy.deepcopy(policy)
    name = profile.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("Terminal profile requires a nonempty name")
    profile.update(
        {
            "type": SETTINGS,
            "ProfileCurrentVersion": 2.09,
            "Font": font_archive(
                appearance["font"]["postscript_name"], appearance["macos_font_size"]
            ),
            "columnCount": appearance["initial_cols"],
            "rowCount": appearance["initial_rows"],
        }
    )
    colors = appearance["colors"]
    for key, color in {
        "BackgroundColor": colors["background"],
        "TextColor": colors["foreground"],
        "TextBoldColor": colors["foreground"],
        "CursorColor": colors["cursor_bg"],
        "SelectionColor": colors.get("selection_bg", "#1d3b53"),
    }.items():
        profile[key] = color_archive(color)
    for group, prefix in (("ansi", "ANSI"), ("brights", "ANSIBright")):
        palette = colors[group]
        if len(palette) != len(ANSI_NAMES):
            raise ValueError(f"{group} must contain eight colors")
        for index, color_name in enumerate(ANSI_NAMES):
            profile[f"{prefix}{color_name}Color"] = color_archive(palette[index])
    profiles[name] = profile
    result[DEFAULT] = name
    result[STARTUP] = name
    return result


def read_preferences(defaults: str) -> dict:
    """Read the account's preference domain through cfprefsd, allowing a fresh account."""
    result = subprocess.run([defaults, "export", DOMAIN, "-"], capture_output=True, check=False)
    if result.returncode:
        if (Path.home() / "Library/Preferences" / f"{DOMAIN}.plist").exists():
            raise ValueError("could not read existing Terminal preferences")
        return {}
    preferences = plistlib.loads(result.stdout)
    if not isinstance(preferences, dict):
        raise ValueError("Terminal preference domain must be a dictionary")
    return preferences


def apply(defaults: str, appearance_path: Path, policy_path: Path) -> None:
    """Publish the profile before selecting it, preserving unrelated preference keys."""
    appearance = json.loads(appearance_path.read_text())
    policy = json.loads(policy_path.read_text())
    original = read_preferences(defaults)
    preferences = copy.deepcopy(original)
    if SETTINGS not in preferences:
        for app in (
            Path("/System/Applications/Utilities/Terminal.app"),
            Path("/Applications/Utilities/Terminal.app"),
        ):
            resources = app / "Contents/Resources/Initial Settings"
            if resources.is_dir():
                preferences[SETTINGS] = initial_profiles(resources)
                break
    candidate = merge(preferences, appearance, policy)
    if read_preferences(defaults) != original:
        raise ValueError("Terminal preferences changed during merge; retry dot update")
    # Never replace the plist behind cfprefsd or import an entire stale domain.
    # The profile must exist before either selection can point at it.
    for key in (SETTINGS, DEFAULT, STARTUP):
        if candidate[key] == original.get(key):
            continue
        value = candidate[key]
        payload = plistlib.dumps(value).decode() if isinstance(value, dict) else value
        args = [defaults, "write", DOMAIN, key]
        if isinstance(value, str):
            args.append("-string")
        subprocess.run([*args, payload], check=True)
    actual = read_preferences(defaults)
    if any(actual.get(key) != candidate[key] for key in (SETTINGS, DEFAULT, STARTUP)):
        raise ValueError(
            "Terminal preferences did not retain the managed profile; retry dot update"
        )


def main() -> int:
    """Apply the managed profile with actionable errors for ordinary preference failures."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--defaults", required=True)
    parser.add_argument("--appearance", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    args = parser.parse_args()
    try:
        apply(args.defaults, args.appearance, args.profile)
    except (
        OSError,
        KeyError,
        ValueError,
        TypeError,
        plistlib.InvalidFileException,
        subprocess.CalledProcessError,
    ) as error:
        print(f"Terminal profile: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
