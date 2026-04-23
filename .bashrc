# shellcheck shell=bash
# ~/.bashrc: thin loader — config lives in ~/.config/shell/

# shellcheck disable=SC1091  # stable path under $HOME, deployed by dotfiles
. "$HOME/.local/lib/dot/shell-loader.sh"

# Environment
_shell_source_dir ~/.config/shell/env.d bash

# Non-interactive? Stop here.
case $- in *i*) ;; *) return ;; esac

# Interactive
_shell_source_dir ~/.config/shell/interactive.d bash
