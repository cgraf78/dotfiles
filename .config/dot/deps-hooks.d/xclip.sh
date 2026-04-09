#!/bin/bash
# Status and post-install hooks for xclip.

_xclip_applicable() {
  [[ "$(uname -s)" == "Linux" ]] || return 1
  [[ -n "${DISPLAY:-}" ]]
}

status() {
  if ! _xclip_applicable; then return 0; fi

  if command -v xclip &>/dev/null; then
    _log "  xclip up to date"
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
    apt|dnf|pacman) ;;
    *)
      _warn "  warning: no install method for xclip on ${_PKG_MGR:-unknown}"
      return 1
      ;;
  esac

  if [[ "$(id -u)" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      return 1
    fi
    if ! sudo true 2>/dev/null; then
      _warn "  warning: sudo not available — cannot install xclip"
      return 1
    fi
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

  _log "  xclip installed (${_PKG_MGR})"
}
