#!/bin/bash
# Merge VS Code settings and keybindings from dotfiles into local config.
# Shared by dotbootstrap and dot (on pull).
# Requires jq.

# Strip // line comments from JSONC so jq can parse it.
# Uses [[:space:]] instead of \s for macOS BSD sed compatibility.
_strip_jsonc() {
  grep -v '^[[:space:]]*//' "$1" | jq --indent 4 '.'
}

# Merge VS Code keybindings from dotfiles into a local keybindings.json.
# Policy: dotfiles win on conflicts (same key+when, different command).
# Local-only keybindings (not in dotfiles) are preserved.
# Writes to a .tmp file first so the original is preserved on failure.
_merge_vscode_keybindings() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    _strip_jsonc "$src" > "$dst"
    return
  fi

  # Create clean JSON temp files (strip JSONC comments for jq)
  local src_clean dst_clean
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  _strip_jsonc "$src" > "$src_clean"
  _strip_jsonc "$dst" > "$dst_clean"

  # Warn about conflicts: keybindings with same key+when but different command or args.
  # Skip dual-entry patterns (remove + add) where source also has the local's command.
  local conflicts
  conflicts=$(jq -rn --slurpfile s "$src_clean" --slurpfile d "$dst_clean" '
    [$s[0][] as $sb | $d[0][] as $db |
     select($sb.key == $db.key and ($sb.when // "") == ($db.when // "") and ($sb.command != $db.command or $sb.args != $db.args)) |
     select([$s[0][] | select(.key == $db.key and (.when // "") == ($db.when // "") and .command == $db.command and .args == $db.args)] | length == 0) |
     "    \($sb.key)\(if $sb.when then " (when: \($sb.when))" else "" end): \($db.command) -> \($sb.command)"] |
    unique | .[]' 2>/dev/null) || true
  if [[ -n "$conflicts" ]]; then
    echo "  overwriting local keybindings in $(basename "$(dirname "$(dirname "$dst")")"):"
    echo "$conflicts"
  fi

  # Merge: all dotfiles entries first, then any local-only entries.
  # A keybinding's identity is its key+when pair.
  if ! jq -n --indent 4 --slurpfile s "$src_clean" --slurpfile d "$dst_clean" '
    ($s[0] | map({key: .key, when: (.when // "")})) as $skeys |
    $s[0] + [$d[0][] | select({key: .key, when: (.when // "")} as $k | $skeys | map(. == $k) | any | not)]
  ' > "$dst.tmp"; then
    echo "  warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$dst.tmp"
    rm -f "$src_clean" "$dst_clean"
    return
  fi
  mv "$dst.tmp" "$dst"
  rm -f "$src_clean" "$dst_clean"
}

# Merge VS Code settings from dotfiles into a local settings.json.
# Policy: dotfiles win on conflicts (same key, different value).
# Local-only settings are preserved. Writes to .tmp first for safety.
_merge_vscode_settings() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    _strip_jsonc "$src" > "$dst"
    return
  fi

  # Create clean JSON temp files (strip JSONC comments for jq)
  local src_clean dst_clean
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  _strip_jsonc "$src" > "$src_clean"
  _strip_jsonc "$dst" > "$dst_clean"

  # Warn about actual changes: compare local vs the merged result (not vs dotfiles
  # directly) since * does recursive merge and preserves local-only nested keys.
  local conflicts
  conflicts=$(jq -rn --slurpfile s "$src_clean" --slurpfile d "$dst_clean" '
    ($d[0] * $s[0]) as $merged |
    [$merged | to_entries[] |
     select($d[0][.key] != null and $d[0][.key] != .value) |
     "    \(.key): \($d[0][.key] | tostring) -> \(.value | tostring)"] |
    .[]' 2>/dev/null) || true
  if [[ -n "$conflicts" ]]; then
    echo "  overwriting local settings in $(basename "$(dirname "$(dirname "$dst")")"):"
    echo "$conflicts"
  fi

  # Merge: local settings * dotfiles settings (recursive merge, dotfiles win)
  # Using * instead of + so nested objects (like "[python]") are merged
  # recursively — local-only nested keys are preserved.
  if ! jq -n --indent 4 --slurpfile s "$src_clean" --slurpfile d "$dst_clean" \
    '$d[0] * $s[0]' > "$dst.tmp"; then
    echo "  warning: settings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$dst.tmp"
    rm -f "$src_clean" "$dst_clean"
    return
  fi
  mv "$dst.tmp" "$dst"
  rm -f "$src_clean" "$dst_clean"
}

# Merge both settings and keybindings into a VS Code config dir.
# $1 = target config dir (e.g., ~/Library/Application Support/Code/User)
_merge_vscode_config() {
  # Settings (cross-platform)
  local settings_src="$HOME/.config/dot/merge-hooks.d/vscode-settings.json"
  if [[ -f "$settings_src" ]]; then
    _merge_vscode_settings "$settings_src" "$1/settings.json"
  fi

  # Keybindings: merge common first, then platform-specific
  local kb_common="$HOME/.config/dot/merge-hooks.d/vscode-keybindings.json"
  if [[ -f "$kb_common" ]]; then
    _merge_vscode_keybindings "$kb_common" "$1/keybindings.json"
  fi

  local kb_platform=""
  case "$(uname -s)" in
    Darwin)       kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-mac.json" ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-windows.json"
      else
        kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-linux.json"
      fi
      ;;
    MINGW*|MSYS*) kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-windows.json" ;;
  esac
  if [[ -n "$kb_platform" && -f "$kb_platform" ]]; then
    _merge_vscode_keybindings "$kb_platform" "$1/keybindings.json"
  fi
}

# Main: determine VS Code config dirs and merge.
merge_vscode() {
  echo "  VS Code"
  if ! command -v jq &>/dev/null; then
    echo "    skipped (jq not installed)"
    return 0
  fi
  if ! command -v code &>/dev/null; then
    echo "    skipped (code not found)"
    return 0
  fi
  case "$(uname -s)" in
    Darwin)
      _merge_vscode_config "$HOME/Library/Application Support/Code/User"
      ;;
    Linux)
      if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        WIN_APPDATA="$(wslpath "$(cmd.exe /C 'echo %APPDATA%' 2>/dev/null | tr -d '\r')" 2>/dev/null)" || true
        if [[ -n "$WIN_APPDATA" ]]; then
          _merge_vscode_config "$WIN_APPDATA/Code/User"
        fi
      else
        _merge_vscode_config "$HOME/.config/Code/User"
      fi
      ;;
    MINGW*|MSYS*)
      _merge_vscode_config "$APPDATA/Code/User"
      ;;
  esac
}
