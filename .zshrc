# ~/.zshrc: thin loader — config lives in ~/.config/shell/

_shell_source_dir() {
    local f
    local -a files=()
    for f in "$1"/*.sh; do [ -f "$f" ] && files+=("$f"); done
    if [ -n "${2:-}" ]; then
        for f in "$1"/*."$2"; do [ -f "$f" ] && files+=("$f"); done
    fi
    files=(${(o)files})
    for f in "${files[@]}"; do . "$f"; done
}

# Environment (all shells)
_shell_source_dir ~/.config/shell/env.d

# Machine-local overrides (not in repo)
[ -f ~/.zshrc_local ] && . ~/.zshrc_local
[ -f ~/.zshrc_local_work ] && . ~/.zshrc_local_work

# Non-interactive? Stop here.
[[ -o interactive ]] || return

# Interactive
_shell_source_dir ~/.config/shell/interactive.d zsh
