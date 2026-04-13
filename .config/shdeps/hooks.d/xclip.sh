# shellcheck shell=bash
# Status and post-install hooks for xclip.

_xclip_applicable() {
  [[ "$(uname -s)" == "Linux" ]] || return 1
  [[ -n "${DISPLAY:-}" ]]
}

status() {
  if ! _xclip_applicable; then return 0; fi
  # In force mode, post() will run and report the result — stay silent here.
  shdeps_reinstall && return 0

  if command -v xclip &>/dev/null; then
    shdeps_log_dim "  xclip up to date"
    return 0
  fi

  return 1
}

install() {
  # Only install on Linux desktops with X11 clipboard access.
  # Headless servers and non-Linux systems should not pull X11 packages.
  if ! _xclip_applicable; then
    return 1
  fi
  if command -v xclip &>/dev/null && ! shdeps_reinstall; then
    return 0
  fi

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

  if [[ $rc -ne 0 ]]; then
    shdeps_warn "  warning: failed to install xclip"
    return 1
  fi

  local action="installed"
  shdeps_reinstall && action="reinstalled"
  shdeps_log_ok "  xclip $action ($mgr)"
}
