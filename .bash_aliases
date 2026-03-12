# =============================================================================
# Tools
# =============================================================================
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

# =============================================================================
# SSH / tunnels
# =============================================================================
alias rdptun.bevo2='autossh -M0 -N -L 9000:bevo2.lan:3389 nas'
alias vnctun.metro='autossh -M0 -N -L 9001:metro.web:5901 nas'

# =============================================================================
# macOS
# =============================================================================
if [[ "$(uname -s)" == "Darwin" ]]; then
    alias ls='ls -G'
fi

# =============================================================================
# Linux / WSL / MINGW
# =============================================================================
if [[ "$(uname -s)" == "Linux" || "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* ]]; then
    # GNU coreutils
    alias ls='ls --color=auto'
    alias cp='cp --backup=numbered'
    alias ln='ln --backup=numbered'
    alias mv='mv -f --backup=numbered'

    # Windows interop (WSL and MINGW/MSYS — uname already matched above)
    if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" != "Linux" ]]; then
        alias e.='explorer.exe .'
        alias np='"c:/program files/notepad++/notepad++.exe"'
        alias rufus='rufus-4.6p.exe -g'
        alias cpuz='cpuz_x64.exe'
        alias wireshark='"c:/Program Files/Wireshark/Wireshark.exe"'
        alias wireshark.rdma='ssh cgraf@ubuntu tcpdump -ni mlx5_0 --immediate-mode -Uw - | "c:/Program Files/Wireshark/Wireshark.exe" -k -i -'
        alias rebootusb='python "$CMDER_ROOT/bin/usbtools/rebootusb.py"'
        alias setusbhost='python "$CMDER_ROOT/bin/usbtools/setusbhost.py"'
        alias pbcopy='clip.exe'
        alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard'
    fi
fi

# =============================================================================
# Work
# =============================================================================
if [ -f ~/.bash_aliases_work ]; then
    . ~/.bash_aliases_work
fi
