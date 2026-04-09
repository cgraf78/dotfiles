# Zsh prompt: git branch/status indicators, PROMPT with exit code.

# Print git branch and dirty/staged indicators for the current directory.
# Falls back to the bare dotfiles repo (~/.dotfiles) when not in a regular repo.
__git_prompt() {
    local -a g=(git)
    if ! git rev-parse --git-dir &>/dev/null; then
        [[ "$PWD" == "$HOME" && -d "$HOME/.dotfiles" ]] || return
        g=(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
    fi

    local branch
    branch="$("${g[@]}" symbolic-ref --short HEAD 2>/dev/null || "${g[@]}" rev-parse --short HEAD 2>/dev/null)" || return

    local git_status flags=""
    git_status="$("${g[@]}" --no-optional-locks status --porcelain 2>/dev/null)"
    # Staged changes
    [[ "$git_status" == *$'\n'[MADRC]* || "$git_status" == [MADRC]* ]] && flags+="+"
    # Unstaged changes
    [[ "$git_status" == *$'\n'?[MDRC]* || "$git_status" == ?[MDRC]* ]] && flags+="*"
    # Untracked files
    [[ "$git_status" == *"??"* ]] && flags+="%"
    [ -n "$flags" ] && flags=" $flags"
    printf ' (%s%s)' "$branch" "$flags"
}

# Set PROMPT with exit status, user@host:path (branch) format.
# Shows red x on non-zero exit code, green o on success.
# Args: $1 - hostname to display (default: %m, the system hostname).
set_prompt() {
    local host="${1:-%m}"
    setopt PROMPT_SUBST
    # %(?.green o.red x) — zsh ternary on last exit status
    PROMPT='%(?.%B%F{green}o%f%b.%B%F{red}x%f%b) %B%F{green}%n@'"$host"'%f%b:%B%F{blue}%~%f%b%F{yellow}$(__git_prompt)%f%# '
    # Set terminal title for xterm/rxvt
    case "$TERM" in
    xterm*|rxvt*)
        PROMPT=$'%{\e]0;%n@'"$host"$': %~\a%}'"$PROMPT"
        ;;
    esac
}

# Set a hostname alias for the prompt and tmux pane borders.
# Args: $1 - alias to display (e.g., "dev1").
#        Call from ~/.zshrc_local to override the default hostname.
set_hostname_alias() {
    HOSTNAME_ALIAS="$1"
    set_prompt "$1"
    [ -n "$TMUX" ] && tmux set -g @hostname_alias "$1" 2>/dev/null
}

set_prompt
