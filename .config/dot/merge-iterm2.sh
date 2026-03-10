#!/bin/bash
# Merge iTerm2 settings from dotfiles into the local iTerm2 config.
# Shared by dot-bootstrap and dot (on pull).
# macOS only — no-ops silently on other platforms.
#
# Two layers:
#   1. Dynamic Profile — ~/.config/dot/iterm2/dynamic-profile.json is symlinked
#      into ~/Library/Application Support/iTerm2/DynamicProfiles/. This creates
#      a "Dotfiles" profile with key mappings, font, colors, and terminal
#      settings. Set it as default in Preferences → Profiles → Other Actions.
#   2. Global preferences — `defaults write` applies settings that live outside
#      profiles: tab style, key repeat, quit behavior, pointer actions, etc.

# Write iTerm2 global preferences via defaults.
_iterm2_defaults() {
  local domain="com.googlecode.iterm2"

  # Key repeat instead of accent popup
  defaults write "$domain" ApplePressAndHoldEnabled -bool false
  # Compact tab bar
  defaults write "$domain" TabStyleWithAutomaticOption -int 5
  # Don't merge windows into tabs automatically
  defaults write "$domain" AppleWindowTabbingMode -string manual
  # No quit confirmation
  defaults write "$domain" PromptOnQuit -bool false
  defaults write "$domain" OnlyWhenMoreTabs -bool false
  # Let apps access clipboard via escape sequences
  defaults write "$domain" AllowClipboardAccess -bool true
  # Allow escape sequences to clear scrollback
  defaults write "$domain" PreventEscapeSequenceFromClearingHistory -bool false

  # Pointer actions: right-click context menu, middle-click paste,
  # three-finger swipe navigation
  defaults write "$domain" PointerActions '{
    "Button,1,1,," = { Action = kContextMenuPointerAction; };
    "Button,2,1,," = { Action = kPasteFromClipboardPointerAction; };
    "Gesture,ThreeFingerSwipeDown,," = { Action = kPrevWindowPointerAction; };
    "Gesture,ThreeFingerSwipeLeft,," = { Action = kPrevTabPointerAction; };
    "Gesture,ThreeFingerSwipeRight,," = { Action = kNextTabPointerAction; };
    "Gesture,ThreeFingerSwipeUp,," = { Action = kNextWindowPointerAction; };
  }'
}

# Main: symlink dynamic profile and apply global preferences.
merge_iterm2() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  local src="$HOME/.config/dot/iterm2/dynamic-profile.json"
  local dst_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  local dst="$dst_dir/dotfiles.json"

  [[ -f "$src" ]] || return 0

  echo "Merging iTerm2 config..."

  if [[ ! -d "$dst_dir" ]]; then
    echo "==> Skipping iTerm2 (launch iTerm2 once, then re-run to link profile)"
    return 0
  fi

  # Dynamic profile symlink
  if [[ ! -L "$dst" || "$(readlink "$dst")" != "$src" ]]; then
    ln -sf "$src" "$dst"
    echo "==> Linked iTerm2 dynamic profile"
  fi

  # Global preferences
  _iterm2_defaults
}
