# ~/.bashrc: entry point for bash configuration.
# Sourced from ~/.bash_profile for login shells too.

# =============================================================================
# Work (must be first per requirements inside the file)
# =============================================================================
if [ -f ~/.bashrc_work ]; then
    . ~/.bashrc_work
fi

# =============================================================================
# Environment
# =============================================================================
export EDITOR=vim
export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-claude}"
export DS_CHAT_CHATBOT="${DS_CHAT_CHATBOT:-argus}"
export DS_UPTERM_PRIVATE_KEY="$HOME/.ssh/argus_github_ed25519"
export DS_SSH_AUTO_ATTACH=ds
export PHOTOCAD_ENV_FILE=/var/lib/photocad/.env
export PHOTOCAD_LIVE_TEST_ENV_FILE=~/.config/photocad/live-test-env
# GitHub PAT for Claude Code's GitHub MCP server. Avoids calling `gh auth token`
# at shell startup (which triggers D-Bus/keyring on headless hosts).
# To create: gh auth token > ~/.config/gh/github-pat && chmod 600 ~/.config/gh/github-pat
[ -f "$HOME/.config/gh/github-pat" ] && export GITHUB_PERSONAL_ACCESS_TOKEN="$(cat "$HOME/.config/gh/github-pat")"

# PATH
if [ -d "/usr/local/bin" ]; then
    PATH="/usr/local/bin:$PATH"
fi
if [ -d "$HOME/.local/bin" ]; then
    PATH="$HOME/.local/bin:$PATH"
fi
if [ -d "$HOME/bin" ]; then
    PATH="$HOME/bin:$PATH"
fi
if [ -d "$HOME/.bun/bin" ]; then
    export BUN_INSTALL="$HOME/.bun"
    PATH="$BUN_INSTALL/bin:$PATH"
fi
if [ -f "$HOME/.atuin/bin/env" ]; then
    . "$HOME/.atuin/bin/env"
fi

# =============================================================================
# Shell behavior
# =============================================================================
HISTSIZE=130000
HISTFILESIZE=-1
HISTTIMEFORMAT="%d/%m/%y %T "
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# =============================================================================
# Prompt
# =============================================================================
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

# =============================================================================
# macOS
# =============================================================================
if [[ "$(uname -s)" == "Darwin" ]]; then
    # Homebrew
    test -x /opt/homebrew/bin/brew && eval "$(/opt/homebrew/bin/brew shellenv)"

    # iTerm2
    test -e "${HOME}/.iterm2_shell_integration.bash" && . "${HOME}/.iterm2_shell_integration.bash"
fi

# =============================================================================
# Linux / WSL / MINGW
# =============================================================================
if [[ "$(uname -s)" == "Linux" || "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    # Disable XON/XOFF flow control so ctrl+s doesn't freeze the terminal
    stty -ixon 2>/dev/null
fi

# =============================================================================
# Extensions
# =============================================================================
# Machine-local (not in repo)
if [ -f ~/.bashrc_local ]; then
    . ~/.bashrc_local
fi
if [ -f ~/.bashrc_local_work ]; then
    . ~/.bashrc_local_work
fi

# Stop here for non-interactive shells
case $- in
    *i*) ;;
      *) return;;
esac

# =============================================================================
# Interactive
# =============================================================================
# Aliases
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Directory bookmarks
mkdir -p ~/.marks
mark() { ln -sfn "$(pwd)" ~/.marks/"$1"; }
jump() { cd -P ~/.marks/"$1" 2>/dev/null || echo "No such mark"; }

# SSH bypassing tmux
sshn() { ssh -t "$1" "NO_TMUX=1 bash"; }

# OpenClaw TUI — launch a conversation with the main agent.
# Usage: argus [session-name]   (default: tui)
# Enforces agent:main:<session-name> session key structure.
# unalias first: bash expands aliases before parsing function definitions,
# so if argus was previously an alias, "argus() {" becomes a syntax error.
unalias argus 2>/dev/null || true
argus() {
    local sess="${1:-tui}"
    openclaw tui --session "agent:main:${sess}"
}

# Tool shell integrations (completions, key bindings, auto-attach)
command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)" || true
command -v ds &>/dev/null && eval "$(ds init bash)"
command -v zoxide &>/dev/null && eval "$(zoxide init bash)"
[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
command -v atuin &>/dev/null && eval "$(atuin init bash --disable-up-arrow)"
