# shellcheck shell=bash
# Load Termnav's WezTerm/tmux shell integration from the shdeps API.

# shellcheck source=../../../.local/lib/dotfiles/shdeps-assets.sh
. "$HOME/.local/lib/dotfiles/shdeps-assets.sh"

dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh 2>/dev/null || true

# A shell that sourced the pre-extraction integration may still carry its old
# dotfiles-owned per-prompt callback. Termnav must not know that private name,
# so retire it once at this consumer boundary when an existing shell reloads.
_dot_wezterm_retire_legacy_tmux_context() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook -d precmd _dot_wezterm_publish_tmux_context 2>/dev/null || true
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    local callback
    local -a remaining=()
    for callback in ${precmd_functions[@]+"${precmd_functions[@]}"}; do
      [[ "$callback" == _dot_wezterm_publish_tmux_context ]] ||
        remaining+=("$callback")
    done
    precmd_functions=("${remaining[@]}")
  fi

  unset -f _dot_wezterm_publish_tmux_context 2>/dev/null || true
}

_dot_wezterm_retire_legacy_tmux_context
unset -f _dot_wezterm_retire_legacy_tmux_context
