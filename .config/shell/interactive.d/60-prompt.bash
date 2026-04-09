# Bash prompt: git branch/status indicators, PS1 with exit code.

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

    local status flags=""
    status="$("${g[@]}" --no-optional-locks status --porcelain 2>/dev/null)"
    # Staged changes
    [[ "$status" == *$'\n'[MADRC]* || "$status" == [MADRC]* ]] && flags+="+"
    # Unstaged changes
    [[ "$status" == *$'\n'?[MDRC]* || "$status" == ?[MDRC]* ]] && flags+="*"
    # Untracked files
    [[ "$status" == *"??"* ]] && flags+="%"
    [ -n "$flags" ] && flags=" $flags"
    printf ' (%s%s)' "$branch" "$flags"
}

# Set PS1 with exit status, user@host:path (branch) format.
# Shows red x on non-zero exit code, green o on success.
# Args: $1 - hostname to display (default: \h, the system hostname).
set_prompt() {
    local host="${1:-\\h}"
    PROMPT_COMMAND='__cmd_exit=$?'
    local exit_sym='\[\033[01;$(( __cmd_exit ? 31 : 32 ))m\]$( (( __cmd_exit )) && echo "x" || echo "o")\[\033[00m\]'
    PS1="${exit_sym} "'\[\033[01;32m\]\u@'"$host"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(__git_prompt)\[\033[00m\]\$ '
    case "$TERM" in
    xterm*|rxvt*)
        PS1="\[\e]0;\u@$host: \w\a\]$PS1"
        ;;
    esac
}

# Set a hostname alias for the prompt and tmux pane borders.
# Args: $1 - alias to display (e.g., "dev1").
#        Call from ~/.bashrc_local to override the default hostname.
set_hostname_alias() {
    HOSTNAME_ALIAS="$1"
    set_prompt "$1"
    [ -n "$TMUX" ] && tmux set -g @hostname_alias "$1" 2>/dev/null
}

set_prompt
