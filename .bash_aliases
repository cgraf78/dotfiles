# ~/.bash_aliases: all aliases, including platform-specific.
# Sourced from ~/.bashrc (interactive shells only).

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

    # Windows interop (shared between WSL and MINGW/MSYS)
    if [[ -n "${WSL_DISTRO_NAME:-}" || "$(uname -s)" != "Linux" ]]; then
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

    # WSL-specific ergonomics
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        # Cache Windows home path
        if [[ -z "${WINHOME:-}" ]]; then
            if [[ -d "/mnt/c/Users/$USER" ]]; then
                export WINHOME="/mnt/c/Users/$USER"
            else
                # Fallback to powershell (only if not already cached)
                export WINHOME=$(wslpath "$(powershell.exe -c "Write-Host -NoNewline \$env:USERPROFILE" 2>/dev/null)" 2>/dev/null)
            fi
        fi

        # Open in Windows/local VS Code instead of Remote WSL.
        wcode() {
            local target code_exe code_exe_win
            target="$(wslpath -w "${1:-.}")"
            code_exe="/mnt/c/Users/$USER/AppData/Local/Programs/Microsoft VS Code/Code.exe"

            if [[ -x "$code_exe" ]]; then
                code_exe_win="$(wslpath -w "$code_exe")"
                cmd.exe /C start "" "$code_exe_win" "$target" >/dev/null 2>&1
            else
                cmd.exe /C start "" code "$target" >/dev/null 2>&1
            fi
        }
        alias wvs='wcode'

        if [[ -n "${WINHOME:-}" ]]; then
            alias wh='cd "$WINHOME"'
            alias winhome='cd "$WINHOME"'

            if [[ -d "$WINHOME/OneDrive/Desktop" ]]; then
                alias wdesktop='cd "$WINHOME/OneDrive/Desktop"'
            else
                alias wdesktop='cd "$WINHOME/Desktop"'
            fi

            alias wdownloads='cd "$WINHOME/Downloads"'

            if [[ -d "$WINHOME/OneDrive/Documents" ]]; then
                alias wdocuments='cd "$WINHOME/OneDrive/Documents"'
            else
                alias wdocuments='cd "$WINHOME/Documents"'
            fi
        fi

        # Path & Clipboard helpers
        alias cppath='wslpath -w "$(pwd)" | clip.exe'  # Copy current WSL path as Windows path
        alias wpath='wslpath -w'                       # Convert to Windows path
        alias lpath='wslpath -u'                       # Convert to Linux path

        # Open Windows Explorer
        e() {
            if [[ $# -eq 0 ]]; then
                explorer.exe .
            else
                explorer.exe "$(wslpath -w "$1")"
            fi
        }
    fi
fi

# =============================================================================
# Work
# =============================================================================
if [ -f ~/.bash_aliases_work ]; then
    . ~/.bash_aliases_work
fi
