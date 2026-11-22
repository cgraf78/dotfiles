# shellcheck shell=bash

_wezterm_remove_hooks() {
  local hook
  local -a precmd_hooks=() preexec_hooks=()

  # reloadsh re-sources the Bash startup files in place. Remove only stock
  # WezTerm hooks so an already active shell can switch prompt ownership.
  for hook in ${precmd_functions[@]+"${precmd_functions[@]}"}; do
    case "$hook" in
      __wezterm_semantic_precmd | __wezterm_user_vars_precmd | __wezterm_osc7) ;;
      *) precmd_hooks+=("$hook") ;;
    esac
  done
  for hook in ${preexec_functions[@]+"${preexec_functions[@]}"}; do
    case "$hook" in
      __wezterm_semantic_preexec | __wezterm_user_vars_preexec) ;;
      *) preexec_hooks+=("$hook") ;;
    esac
  done
  precmd_functions=(${precmd_hooks[@]+"${precmd_hooks[@]}"})
  preexec_functions=(${preexec_hooks[@]+"${preexec_hooks[@]}"})
}

_wezterm_source_integration() {
  # Dotfiles marks prompts for tmux copy mode. A shell that merely inherited
  # TMUX (for example via code .) still uses its own terminal's integration.
  if [ -n "${TMUX:-}" ] && [ "${TERM_PROGRAM:-}" = tmux ]; then
    # Bash and Zsh scope this variable for the sourced integration.
    # shellcheck disable=SC2034
    local WEZTERM_SHELL_SKIP_SEMANTIC_ZONES=1 2>/dev/null || true
  fi
  _wezterm_remove_hooks
  # shellcheck source=/dev/null
  . "$1"
}

# Stock WezTerm's integration appends duplicate hooks if sourced twice.
if [ -z "${__wezterm_sourced:-}" ]; then
  for _wezterm_bundle in "$HOME/Applications/WezTerm.app" /Applications/WezTerm.app; do
    _wezterm_integration=$_wezterm_bundle/Contents/Resources/wezterm.sh
    if [ -r "$_wezterm_integration" ]; then
      _wezterm_source_integration "$_wezterm_integration"
      __wezterm_sourced=1
      break
    fi
  done
  unset _wezterm_bundle _wezterm_integration
fi
unset -f _wezterm_remove_hooks _wezterm_source_integration
