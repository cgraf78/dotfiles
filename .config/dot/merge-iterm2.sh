#!/bin/bash
# Merge iTerm2 settings from dotfiles into the local iTerm2 config.
# Shared by dot-bootstrap and dot (on pull).
# macOS only — no-ops silently on other platforms.
#
# Two layers:
#   1. Dynamic Profile — ~/.config/dot/iterm2/dotfiles-dyn-profile.json is copied
#      into ~/Library/Application Support/iTerm2/DynamicProfiles/. This creates
#      a "Windows (Dotfiles)" profile with key mappings, font, colors, and terminal
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

# Main: copy dynamic profile and apply global preferences.
merge_iterm2() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  local src="$HOME/.config/dot/iterm2/dotfiles-dyn-profile.json"
  local dst_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  local dst="$dst_dir/dotfiles-dyn-profile.json"

  [[ -f "$src" ]] || return 0
  if [[ ! -d "$dst_dir" ]]; then
    echo "Skipping iTerm2 (DynamicProfiles dir not found)"
    return 0
  fi

  echo "==> Merging iTerm2 config..."

  # Dynamic profile copy (iTerm2 doesn't follow symlinks)
  if ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst"
  fi

  # Global preferences
  _iterm2_defaults
}
