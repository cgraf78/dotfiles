# ~/.bashrc: entry point for bash configuration.
# Sourced from ~/.bash_profile for login shells too.

# Work config (first — may include system config that must precede user config)
if [ -f ~/.bashrc_work ]; then
    . ~/.bashrc_work
fi

# Environment
export EDITOR=vim

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

# Shell behavior
HISTSIZE=130000
HISTFILESIZE=-1
HISTTIMEFORMAT="%d/%m/%y %T "
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# Prompt
PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
    ;;
esac

# Platform-specific config
case "$(uname -s)" in
    Darwin)
        [ -f ~/.bashrc_mac ] && . ~/.bashrc_mac ;;
    Linux|MINGW*|MSYS*)
        [ -f ~/.bashrc_linux ] && . ~/.bashrc_linux ;;
esac

# Machine-local extensions (not in repo)
if [ -f ~/.bashrc_extra ]; then
    . ~/.bashrc_extra
fi

# Stop here for non-interactive shells
case $- in
    *i*) ;;
      *) return;;
esac

# Aliases (after non-interactive guard — aliases aren't expanded in non-interactive shells)
if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Completions
command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)" || true

# SSH bypassing tmux
sshn() { ssh -t "$1" "NO_TMUX=1 bash"; }

# Directory bookmarks
mkdir -p ~/.marks
mark() { ln -sfn "$(pwd)" ~/.marks/"$1"; }
jump() { cd -P ~/.marks/"$1" 2>/dev/null || echo "No such mark"; }

# Vim
# Vim runtime is installed by dot-bootstrap (no auto-network calls on shell startup).

# Plain tmux session (delegates to ds with bare profile)
def() { ds -p bare ${1:+--name "$1"}; }

# Auto-attach to tmux on SSH (sshn() bypasses this via NO_TMUX)
# exec so the SSH session ends when tmux detaches.
if [[ -z "$TMUX" && $- == *i* && -n "$SSH_CONNECTION" && -z "$NO_TMUX" ]] && command -v tmux &>/dev/null; then
    exec ds -p bare
fi
