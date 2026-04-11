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

# Environment
_shell_source_dir ~/.config/shell/env.d zsh

# Non-interactive? Stop here.
[[ -o interactive ]] || return

# Interactive
_shell_source_dir ~/.config/shell/interactive.d zsh

# Machine-local overrides (not in repo) — after interactive.d so functions
# like set_hostname_alias are defined before local scripts call them.
if [ -f ~/.zshrc_local ]; then . ~/.zshrc_local; fi
if [ -f ~/.zshrc_local_work ]; then . ~/.zshrc_local_work; fi
