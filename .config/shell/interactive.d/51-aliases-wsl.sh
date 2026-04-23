# shellcheck shell=bash
# WSL / MINGW / MSYS aliases and helpers.  Shared Windows interop sits in the
# top block; WSL-only ergonomics (WINHOME, wcode, explorer) live below.
# Depends on _UNAME and _bat_cmd from earlier files.

case "$_UNAME" in
  Linux) [[ -n "${WSL_DISTRO_NAME:-}" ]] || return 0 ;;
  MINGW* | MSYS*) ;;
  *) return 0 ;;
esac

# Native ls coloring (eza takes precedence in 50-aliases.sh if installed).
# Handles WSL and MINGW/MSYS; 51-aliases-linux.sh covers pure Linux.
command -v eza >/dev/null 2>&1 || alias ls='ls --color=auto'

# Debian/Ubuntu under WSL may still ship `bat` as `batcat`.
[[ "${_bat_cmd:-}" == "batcat" ]] && alias bat='batcat'

# ── Windows interop (shared between WSL and MINGW/MSYS) ──────────────────

alias np='"c:/program files/notepad++/notepad++.exe"'
alias rufus='rufus-4.6p.exe -g'
alias cpuz='cpuz_x64.exe'
alias wireshark='"c:/Program Files/Wireshark/Wireshark.exe"'
alias wireshark.rdma='ssh cgraf@ubuntu tcpdump -ni mlx5_0 --immediate-mode -Uw - | "c:/Program Files/Wireshark/Wireshark.exe" -k -i -'
alias rebootusb='python "$CMDER_ROOT/bin/usbtools/rebootusb.py"'
alias setusbhost='python "$CMDER_ROOT/bin/usbtools/setusbhost.py"'
alias pbcopy='clip.exe'
alias pbpaste='powershell.exe -NoProfile -Command Get-Clipboard'

# ── WSL-only ergonomics ──────────────────────────────────────────────────

[[ -n "${WSL_DISTRO_NAME:-}" ]] || return 0

# Cache Windows home path
if [[ -z "${WINHOME:-}" ]]; then
  if [[ -d "/mnt/c/Users/$USER" ]]; then
    export WINHOME="/mnt/c/Users/$USER"
  else
    # Fallback to powershell (only if not already cached)
    WINHOME=$(wslpath "$(powershell.exe -c "Write-Host -NoNewline \$env:USERPROFILE" 2>/dev/null)" 2>/dev/null)
    export WINHOME
  fi
fi

# Open in Windows/local VS Code instead of Remote WSL.
wcode() {
  local target code_exe code_exe_win
  target="$(wslpath -w "${1:-.}")"
  code_exe="/mnt/c/Users/$USER/AppData/Local/Programs/Microsoft VS Code/Code.exe"

  if [[ -x "$code_exe" ]]; then
    code_exe_win="$(wslpath -w "$code_exe")"
    powershell.exe -NoProfile -Command "Start-Process -FilePath '$code_exe_win' -ArgumentList '$target'" >/dev/null 2>&1
  else
    powershell.exe -NoProfile -Command "Start-Process -FilePath 'code' -ArgumentList '$target'" >/dev/null 2>&1
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
alias cppath='wslpath -w "$(pwd)" | clip.exe' # Copy current WSL path as Windows path
alias wpath='wslpath -w'                      # Convert to Windows path
alias lpath='wslpath -u'                      # Convert to Linux path

# Open Windows Explorer
e() {
  if [[ $# -eq 0 ]]; then
    explorer.exe .
  else
    explorer.exe "$(wslpath -w "$1")"
  fi
}
