"""Exercise managed Terminal profiles without accessing the user's preferences."""

import copy
import importlib.util
import json
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
HELPER = ROOT / ".local/lib/dotfiles/merge-hooks.d/lib/terminal-font.py"
sys.path.insert(0, str(HELPER.parent))
APPEARANCE = ROOT / ".config/terminal/settings.json"
POLICY = ROOT / ".config/dot/merge-hooks.d/terminal/profile.json"


class TerminalProfileTest(unittest.TestCase):
    """Check selection, preservation, validation, and preference publication boundaries."""

    def setUp(self):
        spec = importlib.util.spec_from_file_location("terminal_font", HELPER)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.appearance = json.loads(APPEARANCE.read_text())
        self.policy = json.loads(POLICY.read_text())
        self.original = {
            "Default Window Settings": "Clear Dark",
            "Startup Window Settings": "Pro",
            "Window Settings": {
                "Clear Dark": {"name": "Clear Dark", "Font": b"keep"},
                "Pro": {"name": "Pro"},
            },
            "Unrelated": True,
        }

    def merge(self, preferences=None):
        return self.module.merge(
            self.original if preferences is None else preferences, self.appearance, self.policy
        )

    def test_selects_managed_profile_as_default_and_startup(self):
        merged = self.merge()
        self.assertEqual(merged["Default Window Settings"], "Dotfiles")
        self.assertEqual(merged["Startup Window Settings"], "Dotfiles")
        font = plistlib.loads(merged["Window Settings"]["Dotfiles"]["Font"])
        self.assertIn(self.appearance["font"]["postscript_name"], font["$objects"])
        self.assertEqual(font["$objects"][1]["NSSize"], self.appearance["macos_font_size"])
        self.assertIsInstance(font["$objects"][1]["NSSize"], float)

    def test_preserves_existing_profiles_and_unrelated_preferences(self):
        original = copy.deepcopy(self.original)
        merged = self.merge()
        for name, profile in original["Window Settings"].items():
            self.assertEqual(merged["Window Settings"][name], profile)
        self.assertEqual(merged["Unrelated"], True)
        self.assertEqual(self.original, original)

    def test_fresh_install_has_explicit_valid_selections(self):
        merged = self.merge({})
        for key in ("Default Window Settings", "Startup Window Settings"):
            self.assertIn(merged[key], merged["Window Settings"])
        self.assertEqual(merged["Default Window Settings"], "Dotfiles")

    def test_bundled_profiles_are_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            resources = Path(directory)
            (resources / "Clear Dark.terminal").write_bytes(
                plistlib.dumps({"name": "Clear Dark", "BackgroundColor": b"keep"})
            )
            profiles = self.module.initial_profiles(resources)
            merged = self.merge({"Window Settings": profiles})
            self.assertEqual(merged["Window Settings"]["Clear Dark"], profiles["Clear Dark"])

    def test_palette_matches_shared_appearance(self):
        profile = self.merge()["Window Settings"]["Dotfiles"]
        expected = self.module.color_archive(self.appearance["colors"]["background"])
        self.assertEqual(profile["BackgroundColor"], expected)
        self.assertEqual(sum(key.startswith("ANSI") for key in profile), 16)
        self.assertTrue(profile["FontAntialias"])

    def test_repeated_merge_is_stable(self):
        first = self.merge()
        self.assertEqual(self.merge(first), first)

    def test_invalid_profiles_are_rejected(self):
        with self.assertRaises(ValueError):
            self.merge({"Window Settings": []})

    def test_invalid_font_is_rejected(self):
        self.appearance["font"]["postscript_name"] = ""
        with self.assertRaises(ValueError):
            self.merge()

    def test_invalid_palette_is_rejected(self):
        self.appearance["colors"]["ansi"] = []
        with self.assertRaises(ValueError):
            self.merge()

    def test_invalid_color_is_rejected(self):
        with self.assertRaises(ValueError):
            self.module.color_archive("red")

    def backend(self, fail_key=None):
        """Emulate only macOS's preference storage boundary, preserving actual plist encoding."""
        self.stored = copy.deepcopy(self.original)
        self.writes = []

        def run(args, **kwargs):
            if args[1] == "export":
                return subprocess.CompletedProcess(args, 0, plistlib.dumps(self.stored), b"")
            key = args[3]
            self.writes.append(key)
            if key == fail_key:
                raise subprocess.CalledProcessError(1, args)
            self.stored[key] = (
                args[-1] if args[-2] == "-string" else plistlib.loads(args[-1].encode())
            )
            return subprocess.CompletedProcess(args, 0)

        return run

    def test_applies_profile_before_selecting_it(self):
        with patch.object(self.module.subprocess, "run", side_effect=self.backend()):
            self.module.apply("defaults", APPEARANCE, POLICY)
            self.assertEqual(
                self.writes,
                ["Window Settings", "Default Window Settings", "Startup Window Settings"],
            )
            self.assertEqual(self.stored, self.merge())
            self.module.apply("defaults", APPEARANCE, POLICY)
            self.assertEqual(len(self.writes), 3)

    def test_failed_profile_write_preserves_old_selections(self):
        with patch.object(
            self.module.subprocess, "run", side_effect=self.backend("Window Settings")
        ):
            with self.assertRaises(subprocess.CalledProcessError):
                self.module.apply("defaults", APPEARANCE, POLICY)
            self.assertEqual(self.stored, self.original)

    def test_concurrent_edit_is_not_overwritten(self):
        before = copy.deepcopy(self.original)
        changed = copy.deepcopy(before)
        changed["ConcurrentEdit"] = True
        with patch.object(self.module, "read_preferences", side_effect=[before, changed]):
            with patch.object(self.module.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "changed during merge"):
                    self.module.apply("defaults", APPEARANCE, POLICY)
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
