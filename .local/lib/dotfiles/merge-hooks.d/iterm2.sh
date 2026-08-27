# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge iTerm2 settings from dotfiles into the local iTerm2 config.
# Runs during standalone Dot client convergence.
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
    if ! dot_config_files_equal "$src" "$dst"; then
      cp "$src" "$dst"
    fi
  done < <(dot_hook_family_files_matching iterm2/profiles.d '*.json' '*.replace/*.json')
}

_iterm2_has_profiles() {
  local src dst_dir
  dst_dir="$HOME/Library/Application Support/iTerm2/DynamicProfiles"
  [[ -d "$dst_dir" ]] || return 1

  while IFS= read -r src; do
    return 0
  done < <(dot_hook_family_files_matching iterm2/profiles.d '*.json' '*.replace/*.json')
  return 1
}

_iterm2_has_defaults() {
  local source
  while IFS= read -r source; do
    return 0
  done < <(dot_hook_family_files_matching iterm2/defaults.d '*.tsv' '*.replace/*.tsv')
  return 1
}

# Write one iTerm2 global preference row via defaults.
_iterm2_write_default() {
  local defaults_command="$1" domain="$2" key="$3" type="$4" value="$5"

  case "$type" in
    bool) "$defaults_command" write "$domain" "$key" -bool "$value" ;;
    int) "$defaults_command" write "$domain" "$key" -int "$value" ;;
    string) "$defaults_command" write "$domain" "$key" -string "$value" ;;
    plist) "$defaults_command" write "$domain" "$key" "$value" ;;
    *)
      dot_hook_warn "    warning: unsupported iTerm2 defaults type: $type"
      return 0
      ;;
  esac
}

# Write iTerm2 global preferences via declarative TSV fragments.
_iterm2_defaults() {
  local source line domain key type value extra defaults_command

  _dot_account_scoped_command \
    "iTerm2 defaults" defaults "${DOT_TEST_DEFAULTS:-}" || return 0
  defaults_command="$REPLY"

  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      IFS=$'\t' read -r domain key type value extra <<<"$line"
      if [[ -z "$domain" || -z "$key" || -z "$type" || -z "$value" || -n "$extra" ]]; then
        dot_hook_warn "    warning: malformed iTerm2 defaults row in $source"
        continue
      fi

      value="${value//\\n/$'\n'}"
      _iterm2_write_default "$defaults_command" "$domain" "$key" "$type" "$value"
    done <"$source"
  done < <(dot_hook_family_files_matching iterm2/defaults.d '*.tsv' '*.replace/*.tsv')
}

# Main: copy dynamic profile and apply global preferences.
merge() {
  _dot_tool_present iterm2 || return 0
  [[ "$(uname)" == "Darwin" ]] || return 0

  _iterm2_has_profiles || _iterm2_has_defaults || return 0

  dot_hook_log "  iTerm2"
  _iterm2_profiles || true
  _iterm2_defaults
}
