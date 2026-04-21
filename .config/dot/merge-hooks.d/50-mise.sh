# shellcheck shell=bash
# Sync global mise-managed tools on every `dot update`.
#
# This runs as a merge hook rather than a shdeps post-install hook because
# the tracked toolset (`~/.config/mise/config.toml` and `mise.lock`) can
# change even when the `mise` package itself does not. `mise install` is
# idempotent, so the correct boundary is the regular dot update path.

merge() {
  command -v mise &>/dev/null || return 0

  local config="$HOME/.config/mise/config.toml"
  [[ -f "$config" ]] || return 0

  _log "  mise"

  mise trust "$config" &>/dev/null || true

  local github_token
  github_token="${MISE_GITHUB_TOKEN:-}"

  # Headless cron runs on Linux can leak a session bus/keyring pair when
  # `gh auth token` wakes up the credential stack, so only fall back to
  # `gh` when the merge is running interactively.
  if [[ -z "$github_token" ]] && [[ -t 0 && -t 1 ]] && command -v gh &>/dev/null; then
    github_token="$(gh auth token 2>/dev/null || true)"
  fi

  if [[ -n "$github_token" ]]; then
    (cd "$HOME" && MISE_GITHUB_TOKEN="$github_token" mise install) || true
  else
    (cd "$HOME" && mise install) || true
  fi
}
