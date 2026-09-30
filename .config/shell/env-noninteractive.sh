# shellcheck shell=bash
# Sourced by non-interactive bash via BASH_ENV and by non-login,
# non-interactive zsh via ~/.zshenv. Login zsh loads env.d from ~/.zprofile;
# keep this shell-aware so scripts, hooks, editor tasks, and automation get the
# same env.d layer regardless of whether they choose bash or zsh.
_shell_ext=bash
[ -n "${ZSH_VERSION:-}" ] && _shell_ext=zsh

# No guard here beyond _shell_load_env's own. That guard is keyed on the
# current shell PID, so it only suppresses re-sourcing inside one process
# (BASH_ENV plus an explicit `. ~/.bashrc`, repeated sourcing); a forked child
# never matches it. Every new bash/zsh process must load env.d itself: shopt
# state, functions, arrays, bash-/zsh-specific branches, and overlay system-rc
# bootstraps do not travel through the environment. A previous exported
# per-flavor guard leaked into tmux's global environment and made every later
# `bash -c`/`zsh -c` skip env.d entirely. Repeated loads stay safe because
# 90-path.sh rebuilds PATH de-duplicated.
#
# The load is fill-only: these shells inherit a caller-chosen environment
# (`EDITOR=vim bash -c ...`, a venv PATH, a test's SHDEPS_CONF_DIR), so env.d
# keeps inherited values and supplies only missing ones. See
# _shell_load_env in shell-loader.sh.

# BASH_ENV is an absolute path, so a child that swaps HOME for one without
# dotfiles (test fixtures, tools running as another home) still sources this
# file. Such a home has no env.d to load: skip quietly instead of printing
# "No such file or directory" for the loader.
if [ -r "$HOME/.local/lib/dotfiles/shell-loader.sh" ]; then
  # shellcheck disable=SC1091  # stable path under $HOME, deployed by dotfiles
  . "$HOME/.local/lib/dotfiles/shell-loader.sh"
  _shell_load_env "$_shell_ext" fill
fi
