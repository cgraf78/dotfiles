# shellcheck shell=bash
# dot doctor: Integrations checks.

_dr_check_shell_integrations() {
  _dr_section "Shell integrations"

  local cache output
  cache=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-shell) || {
    _dr_warn "sley shell integration unchecked" "could not create temp cache"
    return 0
  }

  output=$(
    XDG_CACHE_HOME="$cache" bash --noprofile -ic '
      printf "loaded=%s\n" "${SLEY_SHELL_LOADED:-0}"
      printf "termnav=%s\n" "${TERMNAV_SHELL_LOADED:-0}"
      declare -F _sley_shell_complete >/dev/null && printf "%s\n" "bash_complete=yes"
    ' 2>/dev/null || true
  )
  if [[ "$output" == *"loaded=1"* &&
    "$output" == *"bash_complete=yes"* &&
    -f "$cache/shell/sley.bash" ]]; then
    _dr_ok "sley bash integration"
  else
    _dr_warn "sley bash integration unavailable" \
      "interactive bash did not load sley shell completions"
  fi
  if [[ "$output" == *"termnav=1"* ]]; then
    _dr_ok "termnav bash integration"
  else
    _dr_warn "termnav bash integration unavailable" \
      "interactive bash did not load termnav shell integration"
  fi

  rm -rf "$cache"

  if ! command -v zsh >/dev/null 2>&1; then
    _dr_skip "sley zsh integration" "zsh not installed"
    return 0
  fi

  cache=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-shell) || {
    _dr_warn "sley zsh integration unchecked" "could not create temp cache"
    return 0
  }

  output=$(
    XDG_CACHE_HOME="$cache" zsh -ic '
      (( ${+functions[_sley_zsh_register]} )) && _sley_zsh_register
      print -r -- "loaded=${SLEY_SHELL_LOADED:-0}"
      print -r -- "termnav=${TERMNAV_SHELL_LOADED:-0}"
      (( ${+functions[_sley_zsh_complete]} )) && print -r -- "zsh_complete=yes"
      (( ${+_comps[sley]} )) && print -r -- "zsh_compdef=${_comps[sley]}"
    ' 2>/dev/null || true
  )
  if [[ "$output" == *"loaded=1"* &&
    "$output" == *"zsh_complete=yes"* &&
    "$output" == *"zsh_compdef=_sley_zsh_complete"* &&
    -f "$cache/shell/sley.zsh" ]]; then
    _dr_ok "sley zsh integration"
  else
    _dr_warn "sley zsh integration unavailable" \
      "interactive zsh did not load sley shell completions"
  fi
  if [[ "$output" == *"termnav=1"* ]]; then
    _dr_ok "termnav zsh integration"
  else
    _dr_warn "termnav zsh integration unavailable" \
      "interactive zsh did not load termnav shell integration"
  fi

  rm -rf "$cache"
}

# ---------------------------------------------------------------------------
# Git hooks
# ---------------------------------------------------------------------------
_dr_check_git_hooks() {
  _dr_section "Git hooks"

  local want_hooks="$HOME/.local/share/git-hooks"
  # Check global first, then fall back to the dotfiles repo-local config.
  local actual_hooks scope=""
  actual_hooks=$(git config --get --global core.hooksPath 2>/dev/null || echo "")
  if [[ -n "$actual_hooks" ]]; then
    scope="global"
  elif [[ -d "$DOTFILES" ]]; then
    actual_hooks=$($GIT config --get core.hooksPath 2>/dev/null || echo "")
    [[ -n "$actual_hooks" ]] && scope="repo-local"
  fi
  # Normalize ~
  actual_hooks="${actual_hooks/#\~/$HOME}"

  if [[ "$actual_hooks" == "$want_hooks" ]]; then
    _dr_ok "core.hooksPath" "$(_dr_tilde "$actual_hooks") ($scope)"
  elif [[ -z "$actual_hooks" ]]; then
    _dr_warn "core.hooksPath not set" \
      "dotfiles ship a pre-commit hook — see $(_dr_tilde "$want_hooks")"
  else
    _dr_warn "core.hooksPath points elsewhere" "got $actual_hooks, expected $(_dr_tilde "$want_hooks")"
  fi

  if [[ -x "$want_hooks/pre-commit" ]]; then
    _dr_ok "pre-commit hook present and executable"
  elif [[ -f "$want_hooks/pre-commit" ]]; then
    _dr_fail "pre-commit hook not executable" "chmod +x $want_hooks/pre-commit"
  else
    _dr_warn "pre-commit hook missing" "$want_hooks/pre-commit"
  fi
}

# Hive Memory binary/config skew.
#
# The hm config is dotfiles-managed and syncs to machines independently of
# hive-memory releases, so a machine can carry a config key its installed hm
# does not understand yet (or no longer understands). hm deliberately
# downgrades unknown keys to a stderr warning so the hook path never fails —
# which means the configured memory policy silently stays on defaults unless
# something surfaces the skew. This check is that something.
_dr_check_hive_memory() {
  _dr_section "Hive Memory"

  if ! command -v hm >/dev/null 2>&1; then
    _dr_skip "hive-memory config" "hm not installed"
    return 0
  fi

  # `stores list` is the cheapest read-only command that still loads (and
  # therefore validates) the full config. Capture stderr only.
  local stderr unknown
  if ! stderr=$(hm stores list --json 2>&1 >/dev/null); then
    _dr_warn "hm config unchecked" "${stderr%%$'\n'*}"
    return 0
  fi

  unknown=$(printf '%s\n' "$stderr" | grep -F 'unknown config key' || true)
  if [[ -n "$unknown" ]]; then
    _dr_warn "hm binary behind configured keys" \
      "${unknown%%$'\n'*} — update hive-memory (shdeps) or drop the key"
    return 0
  fi
  _dr_ok "hm understands configured keys"
}
