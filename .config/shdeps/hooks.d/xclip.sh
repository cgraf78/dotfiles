# shellcheck shell=bash
# Hook for xclip — X11 clipboard tool for Linux desktops.

_xclip_applicable() {
  [[ "$(uname -s)" == "Linux" ]] || return 1
  [[ -n "${DISPLAY:-}" ]]
}

exists() {
  # Not applicable on non-Linux or headless systems
  _xclip_applicable || return 0
  command -v xclip &>/dev/null
}

version() {
  xclip -version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1
}

install() {
  if ! _xclip_applicable; then return 0; fi

  local mgr
  mgr=$(shdeps_pkg_mgr)

  case "$mgr" in
    apt | dnf | pacman) ;;
    *)
      shdeps_warn "  warning: no install method for xclip on ${mgr:-unknown}"
      return 1
      ;;
  esac

  if ! shdeps_require_sudo; then
    shdeps_warn "  warning: sudo not available — cannot install xclip"
    return 1
  fi

  local rc=0
  case "$mgr" in
    apt)
      sudo apt-get update -qq >/dev/null 2>&1 || true
      sudo apt-get install -y xclip >/dev/null 2>&1 || rc=$?
      ;;
    dnf)
      sudo dnf install -y xclip >/dev/null 2>&1 || rc=$?
      ;;
    pacman)
      sudo pacman -S --needed --noconfirm xclip >/dev/null 2>&1 || rc=$?
      ;;
  esac

  [[ $rc -eq 0 ]]
}
