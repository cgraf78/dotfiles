# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Sync global mise-managed tools on every `dot update`.
#
# This runs as a merge hook rather than a shdeps post-install hook because the
# tracked toolset (`~/.config/mise/config.toml` and `mise.lock`) can change even
# when the `mise` package itself does not. `mise install --locked` is idempotent,
# so the correct boundary is the regular dot update path. The committed lockfile
# is authoritative, so installs fail closed instead of resolving new assets.

if ! declare -F dot_sibling_tmp_for >/dev/null 2>&1; then
  _dot_mise_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../temp.sh disable=SC1091
  . "$_dot_mise_hook_dir/../temp.sh"
fi

_mise_replace_link() {
  local target="$1" link="$2" tmp

  dot_sibling_tmp_for "$link" || return 1
  tmp="$REPLY"
  ln -sfn "$target" "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$link" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }
}

_mise_retire_tmux() {
  local link="$HOME/.local/bin/tmux"
  local managed_link="$HOME/.local/bin/.dot-mise/tmux"

  if [[ -L "$link" ]] && [[ "$(readlink "$link" 2>/dev/null)" == "$managed_link" ]]; then
    rm -f "$link"
  fi
  [[ -L "$managed_link" ]] && rm -f "$managed_link"
  return 0
}

_mise_publish_tmux() {
  local tmux_bin bin_dir link managed_link existing_target=""

  bin_dir="$HOME/.local/bin"
  link="$bin_dir/tmux"
  managed_link="$bin_dir/.dot-mise/tmux"

  # The stable intermediate target identifies links owned by this hook across
  # Mise data-root and version changes. Preserve every other executable/link.
  if [[ -L "$link" ]]; then
    existing_target=$(readlink "$link" 2>/dev/null) || return 0
    [[ "$existing_target" == "$managed_link" ]] || return 0
  elif [[ -e "$link" ]]; then
    return 0
  fi

  tmux_bin=$(mise which tmux 2>/dev/null) || tmux_bin=""
  if [[ -z "$tmux_bin" || ! -x "$tmux_bin" ]]; then
    # Do not leave a high-priority broken link masking Mise's ordinary shim
    # when tmux is removed or resolution stops succeeding.
    _mise_retire_tmux
    return 0
  fi

  # Tmux is called repeatedly by DS and prompt/editor integrations. Bypass
  # Mise's generic per-invocation shim while retaining Mise as version owner.
  # The stable public link never changes; the inner link is atomically replaced.
  mkdir -p "${managed_link%/*}" || return 0
  _mise_replace_link "$tmux_bin" "$managed_link" || return 0
  if [[ -z "$existing_target" ]]; then
    _mise_replace_link "$managed_link" "$link" || return 0
  fi
}

_mise_interactive() {
  [[ -t 0 && -t 1 ]]
}

merge() {
  _dot_tool_present mise || return 0
  # Mise's tracked global toolset targets Linux and macOS release assets.
  # Termux dependencies come from its native packages instead; asking Mise to
  # resolve them as Android assets produces deterministic unsupported-platform
  # failures and cannot install a useful generation.
  dot_hook_platform_match android && return 0

  local config="$HOME/.config/mise/config.toml"
  if [[ ! -f "$config" ]]; then
    _mise_retire_tmux
    return 0
  fi

  dot_hook_log "  mise"

  mise trust "$config" &>/dev/null || true

  local github_token install_ok=0
  github_token="${MISE_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}"

  # Headless cron runs on Linux can leak a session bus/keyring pair when
  # `gh auth token` wakes up the credential stack, so only fall back to
  # `gh` when the merge is running interactively and owns the account HOME.
  if [[ -z "$github_token" ]] && _mise_interactive; then
    local gh_command
    if _dot_account_scoped_command \
      "Mise GitHub token lookup" gh "${DOT_TEST_GH:-}"; then
      gh_command="$REPLY"
      github_token="$("$gh_command" auth token 2>/dev/null || true)"
    fi
  fi

  if [[ -n "$github_token" ]]; then
    if (cd "$HOME" && MISE_GITHUB_TOKEN="$github_token" mise install --locked); then
      install_ok=1
    fi
  else
    if (cd "$HOME" && mise install --locked); then
      install_ok=1
    fi
  fi

  if ((install_ok)); then
    # SuperHTML moved from the deprecated UBI backend to the GitHub backend.
    # Prune only that retired payload, and let mise preserve it if another
    # tracked config still references the old provider.
    (cd "$HOME" && mise prune --tools --yes ubi:kristoff-it/superhtml) \
      &>/dev/null || true
  fi

  _mise_publish_tmux
}
