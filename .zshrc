# ~/.zshrc: thin loader — config lives in ~/.config/shell/

. "$HOME/.local/lib/dot/shell-loader.sh"

# Environment
_shell_source_dir ~/.config/shell/env.d zsh

# Non-interactive? Stop here.
[[ -o interactive ]] || return

# Interactive
_shell_source_dir ~/.config/shell/interactive.d zsh
