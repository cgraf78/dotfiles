# shellcheck shell=bash
# ~/.bashrc: thin loader — config lives in ~/.config/shell/

# shellcheck disable=SC1091  # stable path under $HOME, deployed by dotfiles
. "$HOME/.local/lib/dotfiles/shell-loader.sh"

# Environment. Interactive and login shells are authoritative. Bash also reads
# this file for a non-interactive `bash -c` whose stdin is a socket or that
# sshd started (its rshd heuristic, in place of BASH_ENV): agent tool shells
# and `ssh host cmd`. Those children keep caller values like any BASH_ENV
# load, so they get the fill-only mode. See ~/.config/shell/README.md.
_shell_env_mode=authoritative
case $- in
  *i*) ;;
  *) shopt -q login_shell || _shell_env_mode=fill ;;
esac
_shell_load_env bash "$_shell_env_mode"
unset _shell_env_mode

# Non-interactive? Stop here.
case $- in *i*) ;; *) return ;; esac

# Interactive
_shell_source_dir ~/.config/shell/interactive.d bash
