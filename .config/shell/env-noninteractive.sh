# shellcheck shell=bash
# Sourced by non-interactive bash via BASH_ENV and by non-login,
# non-interactive zsh via ~/.zshenv. Login zsh loads env.d from ~/.zprofile;
# keep this shell-aware so scripts, hooks, editor tasks, and automation get the
# same env.d layer regardless of whether they choose bash or zsh.
_shell_ext=bash
[ -n "${ZSH_VERSION:-}" ] && _shell_ext=zsh

# Guard by shell flavor. Same-shell nested subprocesses should not keep
# prepending PATH, but a zsh-driven bash subprocess still needs bash-specific
# env.d branches and system rc hooks.
case ",${_SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS:-}," in
  *,"$_shell_ext",*) return 0 ;;
esac
if [ -n "${_SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS:-}" ]; then
  export _SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS="${_SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS},$_shell_ext"
else
  export _SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS="$_shell_ext"
fi

# shellcheck disable=SC1091  # stable path under $HOME, deployed by dotfiles
. "$HOME/.local/lib/dot/core/shell-loader.sh"
_shell_load_env "$_shell_ext"
