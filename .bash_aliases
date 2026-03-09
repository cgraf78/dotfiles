# Tools
alias vs='code'
alias ca='cal -3'
alias vi='vim'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='grep -F --color=auto'
alias egrep='grep -E --color=auto'
alias gl='git log --oneline --all --graph --decorate'
alias dl='dot log --oneline --all --graph --decorate'

# SSH/tunnels
alias rdptun.bevo2='autossh -M0 -N -L 9000:bevo2.lan:3389 nas'
alias vnctun.metro='autossh -M0 -N -L 9001:metro.web:5901 nas'

# Platform-specific aliases
case "$(uname -s)" in
    Darwin)
        [ -f ~/.bash_aliases_mac ] && . ~/.bash_aliases_mac ;;
    Linux|MINGW*|MSYS*)
        [ -f ~/.bash_aliases_linux ] && . ~/.bash_aliases_linux ;;
esac

# Work aliases
if [ -f ~/.bash_aliases_work ]; then
    . ~/.bash_aliases_work
fi
