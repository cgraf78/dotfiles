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
export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-argus}"
export DS_UPTERM_PRIVATE_KEY="$HOME/.ssh/argus_github_ed25519"

# Vim runtime — clone on first use if missing
if [ ! -d "$HOME/.vim_runtime" ] && command -v git &>/dev/null; then
    git clone --depth 1 https://github.com/cgraf78/vimrc.git "$HOME/.vim_runtime" &>/dev/null \
        && sh "$HOME/.vim_runtime/install_awesome_vimrc.sh" &>/dev/null || true
fi

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
# Set PS1 with colored user@host:path format.
# Args: $1 - hostname to display (default: \h, the system hostname).
set_prompt() {
    local host="${1:-\\h}"
    PS1='\[\033[01;32m\]\u@'"$host"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
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
    :
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

# Completions
command -v fzf &>/dev/null && eval "$(fzf --bash 2>/dev/null)" || true

# Directory bookmarks
mkdir -p ~/.marks
mark() { ln -sfn "$(pwd)" ~/.marks/"$1"; }
jump() { cd -P ~/.marks/"$1" 2>/dev/null || echo "No such mark"; }

# SSH bypassing tmux
sshn() { ssh -t "$1" "NO_TMUX=1 bash"; }

# ds shell integration (profile shortcuts + auto-attach on SSH)
command -v ds &>/dev/null && eval "$(ds init bash)"
