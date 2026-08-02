# shellcheck shell=bash
# Load Termnav's WezTerm/tmux shell integration from the shdeps API.

# shellcheck source=../../.local/lib/dot/core/shdeps-assets.sh
. "$HOME/.local/lib/dot/core/shdeps-assets.sh"

dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh 2>/dev/null || true

_dot_wezterm_publish_tmux_context() {
  typeset -f _termnav_wezterm_set_user_var >/dev/null 2>&1 || return 0
  # Neovim's embedded terminal cannot relay tmux DCS passthrough framing, so
  # leave WezTerm-only metadata to Termnav's context predicate. Keep older
  # Termnav installations working until the predicate is universally present.
  if typeset -f _termnav_wezterm_active >/dev/null 2>&1; then
    _termnav_wezterm_active || return 0
  fi
  if [[ -n "${TMUX:-}" ]]; then
    _termnav_wezterm_set_user_var DOT_TMUX true
  else
    _termnav_wezterm_set_user_var DOT_TMUX ""
  fi
}

_dot_wezterm_unregister_tmux_context() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook -d precmd _dot_wezterm_publish_tmux_context 2>/dev/null || true
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    local _callback
    local -a _remaining=()
    for _callback in ${precmd_functions[@]+"${precmd_functions[@]}"}; do
      [[ "$_callback" == _dot_wezterm_publish_tmux_context ]] ||
        _remaining+=("$_callback")
    done
    precmd_functions=("${_remaining[@]}")
  fi
}

# TMUX is fixed for a shell's lifetime, so publish this context when the
# integration loads instead of paying for it on every prompt cycle. Remove the
# legacy callback so reloading an existing shell also gets the faster path.
_dot_wezterm_unregister_tmux_context
_dot_wezterm_publish_tmux_context
