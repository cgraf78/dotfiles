# shellcheck shell=bash
# Merge iTerm2 settings from dotfiles into the local iTerm2 config.
# Shared by dotbootstrap and dot (on pull).
# macOS only — no-ops silently on other platforms.
#
# Declarative sources:
#   1. Dynamic Profiles — ordered JSON fragments under iterm2/profiles.d/ are
#      copied into ~/Library/Application Support/iTerm2/DynamicProfiles/.
#   2. Global preferences — ordered TSV fragments under iterm2/defaults.d/
#      become `defaults write` calls for settings that live outside profiles.

_iterm2_profile_output_name() {
  local src="$1" base
  base="$(basename "$src")"
  if [[ "$base" =~ ^[0-9]+-(.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "$base"
  fi
}

# Return success when dynamic profiles were copied or already installed.
_iterm2_profiles() {
  local src dst_dir dst
  dst_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"

  [[ -d "$dst_dir" ]] || return 1

  while IFS= read -r src; do
    dst="$dst_dir/$(_iterm2_profile_output_name "$src")"
    # iTerm2 does not follow symlinks for dynamic profiles.
    if ! cmp -s "$src" "$dst"; then
      cp "$src" "$dst"
    fi
  done < <(_merge_hook_family_files_matching iterm2/profiles.d '*.json' '*.replace/*.json')
}

_iterm2_has_profiles() {
  local src dst_dir
  dst_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  [[ -d "$dst_dir" ]] || return 1

  while IFS= read -r src; do
    return 0
  done < <(_merge_hook_family_files_matching iterm2/profiles.d '*.json' '*.replace/*.json')
  return 1
}

_iterm2_has_defaults() {
  local source
  while IFS= read -r source; do
    return 0
  done < <(_merge_hook_family_files_matching iterm2/defaults.d '*.tsv' '*.replace/*.tsv')
  return 1
}

# Write one iTerm2 global preference row via defaults.
_iterm2_write_default() {
  local domain="$1" key="$2" type="$3" value="$4"

  case "$type" in
    bool) defaults write "$domain" "$key" -bool "$value" ;;
    int) defaults write "$domain" "$key" -int "$value" ;;
    string) defaults write "$domain" "$key" -string "$value" ;;
    plist) defaults write "$domain" "$key" "$value" ;;
    *)
      _warn "    warning: unsupported iTerm2 defaults type: $type"
      return 0
      ;;
  esac
}

# Write iTerm2 global preferences via declarative TSV fragments.
_iterm2_defaults() {
  local source line domain key type value extra

  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      IFS=$'\t' read -r domain key type value extra <<<"$line"
      if [[ -z "$domain" || -z "$key" || -z "$type" || -z "$value" || -n "$extra" ]]; then
        _warn "    warning: malformed iTerm2 defaults row in $source"
        continue
      fi

      value="${value//\\n/$'\n'}"
      _iterm2_write_default "$domain" "$key" "$type" "$value"
    done <"$source"
  done < <(_merge_hook_family_files_matching iterm2/defaults.d '*.tsv' '*.replace/*.tsv')
}

# Main: copy dynamic profile and apply global preferences.
merge() {
  [[ "$(uname)" == "Darwin" ]] || return 0

  _iterm2_has_profiles || _iterm2_has_defaults || return 0

  _log "  iTerm2"
  _iterm2_profiles || true
  _iterm2_defaults
}
