# shellcheck shell=bash
# Hook for wezterm — GPU-accelerated terminal emulator.

_wezterm_ver() {
  wezterm --version 2>/dev/null | awk '{v=$2; if (v ~ /^[0-9a-f]{40}$/) print "commit " substr(v,1,7); else print v}'
}

_wezterm_os_release() {
  local distro_id="" distro_ver=""
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_id="${ID:-}"
    distro_ver="${VERSION_ID:-}"
  fi
  printf '%s|%s\n' "$distro_id" "$distro_ver"
}

_wezterm_asset_pattern() {
  local distro_id="$1" distro_ver="$2"
  case "$distro_id" in
    ubuntu) printf 'Ubuntu%s\n' "$distro_ver" ;;
    debian) printf 'Debian%s\n' "$distro_ver" ;;
    fedora) printf 'Fedora%s\n' "$distro_ver" ;;
    centos | rhel | rocky | almalinux)
      printf 'centos%s\n' "${distro_ver%%.*}"
      ;;
  esac
}

_wezterm_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf 'x86_64\n' ;;
    aarch64 | arm64) printf 'arm64\n' ;;
  esac
}

_wezterm_select_asset() {
  local all_urls="$1" pattern="$2" ext="$3" arch="$4"
  local asset lower_pattern lower_asset suffix

  lower_pattern=$(printf '%s' "$pattern" | tr '[:upper:]' '[:lower:]')
  case "$ext:$arch" in
    deb:x86_64) suffix="${lower_pattern}.deb" ;;
    deb:arm64) suffix="${lower_pattern}.arm64.deb" ;;
    rpm:x86_64) suffix="${lower_pattern}.x86_64.rpm" ;;
    *) return 1 ;;
  esac

  while IFS= read -r asset; do
    lower_asset=$(printf '%s' "$asset" | tr '[:upper:]' '[:lower:]')
    if [[ "$lower_asset" == *"$suffix" ]]; then
      printf '%s\n' "$asset"
      return 0
    fi
  done <<<"$all_urls"

  return 1
}

exists() {
  # WSL: WezTerm runs as a Windows-native app; not managed here.
  local platform
  platform=$(shdeps_platform)
  [[ "$platform" == "wsl" ]] && return 0

  # CI should verify dotfiles' WezTerm configuration and wrappers, not install a
  # GUI terminal into an ephemeral runner. Treating CI as satisfied keeps normal
  # desktop installs unchanged while avoiding cask/package flakiness in tests.
  [[ -n "${CI:-}" ]] && return 0

  # Headless Linux: skip to avoid pulling in GUI dependencies.
  [[ "$platform" == "linux" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]] && return 0

  command -v wezterm &>/dev/null
}

version() {
  _wezterm_ver
}

install() {
  local platform
  platform=$(shdeps_platform)

  # Safety net: skip on WSL/headless (exists() should have caught this)
  if [[ "$platform" == "wsl" ]]; then return 0; fi
  if [[ -n "${CI:-}" ]]; then return 0; fi
  if [[ "$platform" == "linux" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then return 0; fi

  local mgr
  mgr=$(shdeps_pkg_mgr)

  case "$mgr" in
    brew)
      if shdeps_reinstall && brew list --cask wezterm &>/dev/null; then
        brew upgrade --cask wezterm &>/dev/null || return 1
      else
        brew install --cask wezterm &>/dev/null || return 1
      fi
      return 0
      ;;
    pacman)
      local pacman_flags=(--noconfirm)
      shdeps_reinstall || pacman_flags+=(--needed)
      sudo pacman -S "${pacman_flags[@]}" wezterm &>/dev/null || return 1
      return 0
      ;;
  esac

  # apt/dnf: download .deb/.rpm from GitHub releases.
  local ext
  case "$mgr" in
    apt) ext="deb" ;;
    dnf) ext="rpm" ;;
    *)
      shdeps_warn "  warning: no install method for wezterm on ${mgr:-unknown}"
      return 1
      ;;
  esac

  if ! shdeps_require_sudo; then
    shdeps_warn "  warning: sudo not available — cannot install wezterm"
    return 1
  fi

  local release_json latest_tag
  release_json=$(shdeps_curl -fsSL --no-netrc -H "Authorization:" \
    "https://api.github.com/repos/wez/wezterm/releases/latest" 2>/dev/null) || {
    shdeps_warn "  warning: couldn't fetch wezterm release info"
    return 1
  }
  latest_tag=$(echo "$release_json" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  if [[ -z "$latest_tag" ]]; then
    shdeps_warn "  warning: couldn't determine latest wezterm version"
    return 1
  fi

  local distro_id="" distro_ver="" distro_release arch
  distro_release=$(_wezterm_os_release)
  distro_id=${distro_release%%|*}
  distro_ver=${distro_release#*|}
  arch=$(_wezterm_arch)

  local all_urls asset_url=""
  all_urls=$(echo "$release_json" |
    grep -o '"browser_download_url":[[:space:]]*"[^"]*\.'"$ext"'"' |
    cut -d'"' -f4)

  if [[ -n "$distro_id" && -n "$distro_ver" && -n "$arch" ]]; then
    local pattern=""
    pattern=$(_wezterm_asset_pattern "$distro_id" "$distro_ver")
    if [[ -n "$pattern" ]]; then
      asset_url=$(_wezterm_select_asset "$all_urls" "$pattern" "$ext" "$arch")
    fi
  fi

  if [[ -z "$asset_url" ]]; then
    shdeps_warn "  warning: no .$ext asset matched ${distro_id:-unknown} ${distro_ver:-} ${arch:-unknown} for wezterm $latest_tag"
    return 1
  fi

  local tmp
  tmp=$(mktemp) || return 1
  if ! shdeps_curl -fsSL "$asset_url" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    shdeps_warn "  warning: failed to download wezterm"
    return 1
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

  [[ $rc -eq 0 ]]
}
