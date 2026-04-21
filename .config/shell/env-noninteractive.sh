# shellcheck shell=bash
# Sourced by non-interactive bash via BASH_ENV.
# Guard prevents PATH duplication in nested subshells.
[ -n "$_SHELL_ENV_LOADED" ] && return 0
export _SHELL_ENV_LOADED=1

for _f in "$HOME/.config/shell/env.d/"*.sh; do
  # shellcheck disable=SC1090
  [ -f "$_f" ] && . "$_f"
done
unset _f
