# shellcheck shell=bash
# ~/.zprofile: zsh login shell config.
# Load the shared environment layer for login shells, including `zsh -lc`.
# Non-login non-interactive zsh is covered by ~/.zshenv; interactive setup
# stays in ~/.zshrc. _shell_load_env is guarded so login+interactive zsh does
# not double-prepend PATH.

. "$HOME/.local/lib/dotfiles/shell-loader.sh"
_shell_load_env zsh
