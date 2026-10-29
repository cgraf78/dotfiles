"""Validate iTerm2 generation against shared terminal settings without live state."""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
LIB = ROOT / ".local/lib/dotfiles/merge-hooks.d/lib"
sys.path.insert(0, str(LIB))


class Iterm2ProfileTest(unittest.TestCase):
    """Exercise native profile output, stable identity, and supported shared behavior."""

    def setUp(self):
        helper = LIB / "iterm2-profile.py"
        self.assertTrue(helper.is_file(), "iTerm2 profile generator is missing")
        spec = importlib.util.spec_from_file_location("iterm2_profile", helper)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.settings = json.loads((ROOT / ".config/terminal/settings.json").read_text())
        self.source = json.loads(
            (
                ROOT / ".config/dot/merge-hooks.d/iterm2/profiles.d/10-dotfiles-dyn-profile.json"
            ).read_text()
        )

    def test_managed_profile_is_named_dotfiles_and_keeps_identity(self):
        result, guid = self.module.render(self.source, self.settings)
        profile = result["Profiles"][0]
        self.assertEqual(profile["Name"], "Dotfiles")
        self.assertEqual(guid, "windows-dotfiles-synced-profile-001")
        self.assertEqual(profile["Guid"], guid)
        self.assertNotIn("Dotfiles Appearance", profile)
        self.assertNotIn("Dotfiles Default", profile)

    def test_appearance_comes_from_shared_settings(self):
        result, _ = self.module.render(self.source, self.settings)
        profile = result["Profiles"][0]
        self.assertEqual(profile["Normal Font"], "JetBrainsMonoNF-Light 11")
        self.assertEqual(profile["Non Ascii Font"], profile["Normal Font"])
        self.assertEqual(profile["Columns"], self.settings["initial_cols"])
        self.assertEqual(profile["Rows"], self.settings["initial_rows"])
        self.assertEqual(profile["Scrollback Lines"], self.settings["scrollback_lines"])
        self.assertEqual(profile["Cursor Type"], 2)
        self.assertTrue(profile["Blinking Cursor"])
        self.assertFalse(profile["Use Separate Colors for Light and Dark Mode"])
        self.assertFalse(any(k.endswith((" (Light)", " (Dark)")) for k in profile))
        self.assertEqual(profile["Background Color"]["Red Component"], 1 / 255)
        self.assertEqual(sum(k.startswith("Ansi ") for k in profile), 16)

    def test_shared_key_sequences_match_wezterm(self):
        profile = self.module.render(self.source, self.settings)[0]["Profiles"][0]
        keys = profile["Keyboard Map"]
        self.assertEqual(keys["0xd-0x20000"]["Text"], "0x1b 0x5b 0x31 0x33 0x3b 0x32 0x75")
        self.assertEqual(keys["0xf702-0x240000"]["Text"], "0x1b 0x5b 0x31 0x3b 0x35 0x44")
        self.assertEqual(keys["0xf702-0x260000"]["Text"], "0x1b 0x5b 0x31 0x3b 0x36 0x44")
        self.assertNotIn("0x67-0x40000", keys)
        self.assertNotIn("0x66-0x40000", keys)

    def test_page_keys_do_not_use_the_arrow_numeric_pad_flag(self):
        profile = self.module.render(self.source, self.settings)[0]["Profiles"][0]
        keys = profile["Keyboard Map"]
        self.assertEqual(keys["0xf72c-0x20000"]["Text"], "0x1b 0x5b 0x35 0x3b 0x32 0x7e")
        self.assertEqual(keys["0xf72d-0x60000"]["Text"], "0x1b 0x5b 0x36 0x3b 0x36 0x7e")

    def test_native_close_alias_keeps_current_tab_scope(self):
        profile = self.module.render(self.source, self.settings)[0]["Profiles"][0]
        self.assertEqual(
            profile["Keyboard Map"]["0x57-0x120000"], {"Action": 25, "Text": "Close\nClose"}
        )
        self.assertEqual(
            profile["Keyboard Map"]["0x54-0x120000"], {"Action": 27, "Text": profile["Guid"]}
        )
        for action in profile["Keyboard Map"].values():
            if action["Action"] == 27:
                self.assertEqual(action["Text"], profile["Guid"])
                self.assertNotIn("Dotfiles Profile", action)

    def test_unmanaged_profile_is_unchanged(self):
        source = {"Profiles": [{"Guid": "custom", "Name": "Custom", "Normal Font": "Menlo 14"}]}
        self.assertEqual(self.module.render(source, self.settings), (source, ""))

    def test_invalid_profile_does_not_render(self):
        with self.assertRaises(ValueError):
            self.module.render({"Profiles": [{"Name": "missing-guid"}]}, self.settings)

    def test_duplicate_guids_are_rejected(self):
        source = {"Profiles": [{"Name": name, "Guid": "same"} for name in ("Other", "Dotfiles")]}
        with self.assertRaisesRegex(ValueError, "duplicate"):
            self.module.render(source, self.settings)

    def test_changed_shared_settings_reach_both_native_profiles(self):
        self.settings["spacing"] = {"horizontal": 1.25, "vertical": 1.1}
        self.settings["cursor"] = {"shape": "bar", "blink": False}
        self.settings["scrollback_lines"] = 4321
        self.settings["ligatures"] = True
        iterm = self.module.render(self.source, self.settings)[0]["Profiles"][0]
        spec = importlib.util.spec_from_file_location("terminal_profile", LIB / "terminal-font.py")
        terminal_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(terminal_module)
        policy = json.loads((ROOT / ".config/dot/merge-hooks.d/terminal/profile.json").read_text())
        terminal = terminal_module.merge({}, self.settings, policy)["Window Settings"]["Dotfiles"]
        self.assertEqual(iterm["Horizontal Spacing"], terminal["FontWidthSpacing"])
        self.assertEqual(iterm["Vertical Spacing"], terminal["FontHeightSpacing"])
        self.assertEqual(iterm["Scrollback Lines"], terminal["ScrollbackLines"])
        self.assertEqual(iterm["Cursor Type"], 1)
        self.assertEqual(terminal["CursorType"], 2)
        self.assertTrue(iterm["ASCII Ligatures"])
        self.assertTrue(iterm["Non-ASCII Ligatures"])
        self.assertFalse(iterm["Blinking Cursor"])
        self.assertFalse(terminal["CursorBlink"])

    def test_invalid_keyboard_map_is_rejected(self):
        source = {"Profiles": [{"Name": "Custom", "Guid": "custom", "Keyboard Map": []}]}
        with self.assertRaisesRegex(ValueError, "Keyboard Map"):
            self.module.render(source, self.settings)

    def test_invalid_keyboard_action_is_rejected(self):
        source = {"Profiles": [{"Name": "Custom", "Guid": "custom", "Keyboard Map": {"key": []}}]}
        with self.assertRaisesRegex(ValueError, "Keyboard Map"):
            self.module.render(source, self.settings)

    def test_multiple_defaults_are_rejected(self):
        source = {
            "Profiles": [
                {"Guid": str(i), "Name": str(i), "Dotfiles Default": True} for i in range(2)
            ]
        }
        with self.assertRaises(ValueError):
            self.module.render(source, self.settings)


class Iterm2HookTest(unittest.TestCase):
    """Run the real hook with isolated files and an account-preference test double."""

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="iterm2-hook-")
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        config = self.home / ".config/dot/merge-hooks.d/iterm2"
        shutil.copytree(ROOT / ".config/dot/merge-hooks.d/iterm2", config)
        shutil.copytree(ROOT / ".config/terminal", self.home / ".config/terminal")
        self.preferences = self.home / "preferences.json"
        self.preferences.write_text(
            json.dumps({"Default Bookmark Guid": "previous", "Unrelated": True})
        )
        self.defaults = self.home / "defaults"
        self.defaults.write_text(
            "#!/usr/bin/env python3\n"
            + "\n".join(
                [
                    "import json, os, sys",
                    "from pathlib import Path",
                    "store = Path(os.environ['ITERM2_FAKE_PREFS'])",
                    "prefs = json.loads(store.read_text())",
                    "action, domain, key = sys.argv[1:4]",
                    "if action == 'read':",
                    "    if key not in prefs: sys.exit(1)",
                    "    print(prefs[key]); sys.exit(0)",
                    "if key == os.environ.get('ITERM2_FAIL_KEY'): sys.exit(1)",
                    "if key != os.environ.get('ITERM2_DROP_KEY'): prefs[key] = sys.argv[-1]",
                    "store.write_text(json.dumps(prefs))",
                ]
            )
            + "\n"
        )
        self.defaults.chmod(0o700)
        self.destination = (
            self.home
            / "Library/Application Support/iTerm2/DynamicProfiles/dotfiles-dyn-profile.json"
        )

    def run_hook(self, **extra):
        environment = os.environ.copy()
        environment.update(
            HOME=str(self.home),
            ITERM2_FAKE_PREFS=str(self.preferences),
            DOT_TEST_DEFAULTS=str(self.defaults),
            BASH_ENV="",
            ENV="",
            **extra,
        )
        script = r"""
dot_hook_source() { :; }
_dot_tool_present() { return 0; }
uname() { printf '%s\n' Darwin; }
dot_hook_log() { :; }
dot_hook_warn() { printf '%s\n' "$*" >&2; }
_dot_account_scoped_command() { REPLY=$DOT_TEST_DEFAULTS; }
dot_hook_family_files_matching() {
  local source
  for source in "$HOME/.config/dot/merge-hooks.d/$1"/*; do
    [[ -f $source && $source != */README.md ]] && printf '%s\n' "$source"
  done
}
dot_sibling_tmp_for() {
  REPLY=$(mktemp "$1.tmp.XXXXXXXX") || return
  [[ ${REPLY##*/} == .* ]] || { printf 'staging must be hidden\n' >&2; return 1; }
}
dot_config_files_equal() { cmp -s "$1" "$2"; }
dot_commit_tmp() {
  [[ ${ITERM2_FAIL_PUBLISH:-0} == 0 ]] || return 1
  mv "$1" "$2"
}
. "$1"
merge
"""
        return subprocess.run(
            ["bash", "-s", "--", str(ROOT / ".local/lib/dotfiles/merge-hooks.d/iterm2.sh")],
            input=script,
            text=True,
            capture_output=True,
            env=environment,
        )

    def test_first_install_publishes_and_selects_managed_profile(self):
        result = self.run_hook()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            json.loads(self.destination.read_text())["Profiles"][0]["Name"], "Dotfiles"
        )
        prefs = json.loads(self.preferences.read_text())
        self.assertEqual(prefs["Default Bookmark Guid"], "windows-dotfiles-synced-profile-001")
        self.assertTrue(prefs["Unrelated"])
        before = self.destination.stat().st_mtime_ns
        self.assertEqual(self.run_hook().returncode, 0)
        self.assertEqual(self.destination.stat().st_mtime_ns, before)

    def test_failed_publication_preserves_profile_and_default(self):
        self.destination.parent.mkdir(parents=True)
        self.destination.write_text('{"Profiles": []}')
        result = self.run_hook(ITERM2_FAIL_PUBLISH="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.destination.read_text(), '{"Profiles": []}')
        self.assertEqual(
            json.loads(self.preferences.read_text())["Default Bookmark Guid"], "previous"
        )
        self.assertEqual(list(self.destination.parent.glob(".*.tmp.*")), [])

    def test_invalid_source_preserves_profile_and_default(self):
        source = (
            self.home / ".config/dot/merge-hooks.d/iterm2/profiles.d/10-dotfiles-dyn-profile.json"
        )
        source.write_text('{"Profiles": [')
        result = self.run_hook()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.destination.exists())
        self.assertEqual(
            json.loads(self.preferences.read_text())["Default Bookmark Guid"], "previous"
        )

    def test_earlier_defaults_failure_is_not_hidden(self):
        result = self.run_hook(ITERM2_FAIL_KEY="ApplePressAndHoldEnabled")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HideScrollbar", json.loads(self.preferences.read_text()))

    def test_failed_default_readback_is_reported(self):
        result = self.run_hook(ITERM2_DROP_KEY="Default Bookmark Guid")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            json.loads(self.preferences.read_text())["Default Bookmark Guid"], "previous"
        )


if __name__ == "__main__":
    unittest.main()
