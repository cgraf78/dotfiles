# shellcheck shell=bash
# Load Termnav's WezTerm/tmux shell integration from the shdeps API.

# shellcheck source=../../.local/lib/dot/core/shdeps-assets.sh
. "$HOME/.local/lib/dot/core/shdeps-assets.sh"

dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh 2>/dev/null || true

_dot_wezterm_publish_tmux_context() {
  declare -F _termnav_wezterm_set_user_var >/dev/null 2>&1 || return 0
  if [[ -n "${TMUX:-}" ]]; then
    _termnav_wezterm_set_user_var DOT_TMUX true
  else
    _termnav_wezterm_set_user_var DOT_TMUX ""
  fi
}

_dot_wezterm_register_tmux_context() {
  declare -F _termnav_wezterm_set_user_var >/dev/null 2>&1 || return 0
  _dot_wezterm_publish_tmux_context

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    autoload -Uz add-zsh-hook
    add-zsh-hook -d precmd _dot_wezterm_publish_tmux_context 2>/dev/null || true
    add-zsh-hook precmd _dot_wezterm_publish_tmux_context
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    [[ " ${precmd_functions[*]} " != *" _dot_wezterm_publish_tmux_context "* ]] &&
      precmd_functions+=(_dot_wezterm_publish_tmux_context)
  fi
}

_dot_wezterm_register_tmux_context
