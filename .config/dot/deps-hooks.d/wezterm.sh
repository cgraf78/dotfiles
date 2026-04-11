# shellcheck shell=bash
# Status and post-install hooks for wezterm.

_wezterm_ver() {
  wezterm --version 2>/dev/null | awk '{v=$2; if (v ~ /^[0-9a-f]{40}$/) print "commit " substr(v,1,7); else print v}'
}

status() {
  # In force mode, post() will run and report the result — stay silent here.
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && return 0
  if command -v wezterm &>/dev/null; then
    local ver
    ver=$(_wezterm_ver)
    _log_dim "  wezterm up to date${ver:+ -- $ver}"
    return 0
  fi
  return 1
}

post() {
  # WSL: WezTerm runs as a Windows-native app; merge-wezterm.sh handles config.
  if _is_wsl; then return 0; fi

  # Headless Linux: skip to avoid pulling in GUI dependencies.
  # Note: DISPLAY/WAYLAND_DISPLAY are unset in cron too, so cron can't do the
  # initial install on desktops — that requires one interactive `dot update`.
  # After that, the `command -v` fast path keeps cron from re-running this.
  if [[ "$(uname -s)" == "Linux" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    return 0
  fi

  # Fast path: already installed and not forcing reinstall.
  if command -v wezterm &>/dev/null && [[ "${DOT_FORCE:-0}" -ne 1 ]]; then
    return 0
  fi

  case "${_PKG_MGR:-}" in
  brew)
    if brew list --cask wezterm &>/dev/null; then
      if [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
        if brew upgrade --cask wezterm &>/dev/null; then
          local ver; ver=$(_wezterm_ver)
          _log_ok "  wezterm reinstalled (brew)${ver:+ -- $ver}"
        else
          _warn "  warning: failed to upgrade wezterm (brew)"
        fi
      fi
      return 0
    fi
    if brew install --cask wezterm &>/dev/null; then
      local ver; ver=$(_wezterm_ver)
      _log_ok "  wezterm installed (brew)${ver:+ -- $ver}"
    else
      _warn "  warning: failed to install wezterm (brew)"
    fi
    return 0
    ;;
  pacman)
    local pacman_flags=(--noconfirm)
    [[ "${DOT_FORCE:-0}" -ne 1 ]] && pacman_flags+=(--needed)
    local pacman_action="installed"
    [[ "${DOT_FORCE:-0}" -eq 1 ]] && pacman_action="reinstalled"
    if sudo pacman -S "${pacman_flags[@]}" wezterm &>/dev/null; then
      local ver; ver=$(_wezterm_ver)
      _log_ok "  wezterm $pacman_action (pacman)${ver:+ -- $ver}"
    else
      _warn "  warning: failed to install wezterm (pacman)"
    fi
    return 0
    ;;
  esac

  # apt/dnf: download .deb/.rpm from GitHub releases.
  local ext
  case "${_PKG_MGR:-}" in
  apt) ext="deb" ;;
  dnf) ext="rpm" ;;
  *)
    _warn "  warning: no install method for wezterm on ${_PKG_MGR:-unknown}"
    return 0
    ;;
  esac

  # Need sudo for package install.
  if ! _require_sudo; then
    _warn "  warning: sudo not available — cannot install wezterm"
    return 0
  fi

  # Query GitHub releases API.
  local release_json latest_tag
  release_json=$(curl -fsSL --no-netrc -H "Authorization:" \
    "https://api.github.com/repos/wez/wezterm/releases/latest" 2>/dev/null) || {
    _warn "  warning: couldn't fetch wezterm release info"
    return 0
  }
  latest_tag=$(echo "$release_json" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  if [[ -z "$latest_tag" ]]; then
    _warn "  warning: couldn't determine latest wezterm version"
    return 0
  fi

  # Find matching asset URL for this distro.
  local distro_id="" distro_ver=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_id="${ID:-}"
    distro_ver="${VERSION_ID:-}"
  fi

  local all_urls asset_url=""
  all_urls=$(echo "$release_json" |
    grep -o '"browser_download_url":[[:space:]]*"[^"]*\.'"$ext"'"' |
    cut -d'"' -f4)

  # Try exact distro+version match (e.g., Ubuntu22.04, Fedora39).
  if [[ -n "$distro_id" && -n "$distro_ver" ]]; then
    local pattern=""
    case "$distro_id" in
    ubuntu) pattern="Ubuntu${distro_ver}" ;;
    debian) pattern="Debian${distro_ver}" ;;
    fedora) pattern="Fedora${distro_ver}" ;;
    esac
    if [[ -n "$pattern" ]]; then
      asset_url=$(echo "$all_urls" | grep -i "$pattern" | head -1)
    fi
  fi

  if [[ -z "$asset_url" ]]; then
    _warn "  warning: no .$ext asset matched ${distro_id:-unknown} ${distro_ver:-} for wezterm $latest_tag"
    return 0
  fi

  # Download and install.
  local tmp
  tmp=$(mktemp) || return 0
  if ! curl -fsSL "$asset_url" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    _warn "  warning: failed to download wezterm"
    return 0
  fi

  local rc=0
  case "$ext" in
  deb)
    sudo dpkg -i "$tmp" &>/dev/null || true
    sudo apt-get install -f -y &>/dev/null || rc=$?
    ;;
  rpm) sudo dnf install -y "$tmp" &>/dev/null || rc=$? ;;
  esac
  rm -f "$tmp"

  if [[ $rc -ne 0 ]]; then
    _warn "  warning: wezterm package install failed"
    return 0
  fi

  _log_ok "  wezterm installed ($ext) -- $latest_tag"
}
