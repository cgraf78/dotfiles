# shellcheck shell=bash
# Status and post-install hooks for xclip.

_xclip_applicable() {
  [[ "$(uname -s)" == "Linux" ]] || return 1
  [[ -n "${DISPLAY:-}" ]]
}

status() {
  if ! _xclip_applicable; then return 0; fi
  # In force mode, post() will run and report the result — stay silent here.
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && return 0

  if command -v xclip &>/dev/null; then
    _log_dim "  xclip up to date"
    return 0
  fi

  return 1
}

post() {
  # Only install on Linux desktops with X11 clipboard access.
  # Headless servers and non-Linux systems should not pull X11 packages.
  if ! _xclip_applicable; then
    return 1
  fi
  if command -v xclip &>/dev/null && [[ "${DOT_FORCE:-0}" -ne 1 ]]; then
    return 0
  fi

  case "${_PKG_MGR:-}" in
  apt | dnf | pacman) ;;
  *)
    _warn "  warning: no install method for xclip on ${_PKG_MGR:-unknown}"
    return 1
    ;;
  esac

  if ! _require_sudo; then
    _warn "  warning: sudo not available — cannot install xclip"
    return 1
  fi

  local rc=0
  case "${_PKG_MGR:-}" in
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

  if [[ $rc -ne 0 ]]; then
    _warn "  warning: failed to install xclip"
    return 1
  fi

  local action="installed"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && action="reinstalled"
  _log_ok "  xclip $action (${_PKG_MGR})"
}
