#!/bin/bash
# Post-install hooks for dependencies.
# Convention: _post_<name> (dashes in dep name → underscores).
# Called by _run_post_hooks in helpers.sh after all deps are installed.
# Add new hooks here — no changes to helpers.sh needed.

_post_vimrc() {
  local vimrc_dir="$HOME/.local/share/vimrc"
  [[ -f "$vimrc_dir/install_awesome_parameterized.sh" ]] || return 0
  bash "$vimrc_dir/install_awesome_parameterized.sh" "$vimrc_dir" "$(whoami)" >/dev/null || \
    _warn "  warning: vimrc install script failed"
}

_post_gstack() {
  [[ -d "$HOME/.local/share/gstack" ]] || return 0
  mkdir -p "$HOME/.claude/skills"
  ln -sfn "$HOME/.local/share/gstack" "$HOME/.claude/skills/gstack"
  local _d
  for _d in "$HOME/.local/share/gstack"/*/; do
    if [[ -f "$_d/SKILL.md" && "$(basename "$_d")" != "node_modules" ]]; then
      ln -sfn "gstack/$(basename "$_d")" "$HOME/.claude/skills/$(basename "$_d")"
    fi
  done
}

_post_bash_preexec() {
  [[ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]] || return 0
  ln -sfn "$HOME/.local/share/bash-preexec/bash-preexec.sh" "$HOME/.bash-preexec.sh"
}

_post_nerd_fonts() {
  # Install fonts from the _FONTS registry below.
  # Each entry: "DisplayName|brew_pkg|pacman_pkg|nerd_fonts_zip|local_dir"
  #   brew_pkg:       homebrew cask name (or - to skip)
  #   pacman_pkg:     pacman package name (or - to skip)
  #   nerd_fonts_zip: zip asset name on ryanoasis/nerd-fonts releases (or - to skip)
  #   local_dir:      subdirectory under ~/.local/share/fonts/ for manual installs
  local _FONTS=(
    "JetBrains Mono Nerd Font|font-jetbrains-mono-nerd-font|ttf-jetbrains-mono-nerd|JetBrainsMono|JetBrainsMonoNerdFont"
    "FiraCode Nerd Font|font-fira-code-nerd-font|ttf-firacode-nerd|FiraCode|FiraCodeNerdFont"
    "MesloLG Nerd Font|font-meslo-lg-nerd-font|ttf-meslo-nerd|Meslo|MesloLGNerdFont"
  )

  # Fetch latest nerd-fonts version once for the GitHub fallback path
  local nf_version=""
  if command -v curl &>/dev/null; then
    nf_version=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" 2>/dev/null \
      | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4) || true
  fi

  local _any_installed=0
  local entry name brew_pkg pacman_pkg nerd_zip font_dir
  for entry in "${_FONTS[@]}"; do
    IFS='|' read -r name brew_pkg pacman_pkg nerd_zip font_dir <<< "$entry"

    # Check if already installed
    local installed=0
    case "${_PKG_MGR:-}" in
      brew)   [[ "$brew_pkg" != "-" ]] && brew list "$brew_pkg" &>/dev/null && installed=1 ;;
      pacman) [[ "$pacman_pkg" != "-" ]] && pacman -Q "$pacman_pkg" &>/dev/null && installed=1 ;;
    esac
    if [[ $installed -eq 0 && -n "$font_dir" ]]; then
      ls "$HOME/.local/share/fonts/$font_dir"/*.ttf &>/dev/null 2>&1 && installed=1
    fi
    if [[ $installed -eq 1 ]]; then continue; fi

    # Install via native package manager where available
    case "${_PKG_MGR:-}" in
      brew)
        if [[ "$brew_pkg" != "-" ]]; then
          brew install "$brew_pkg" &>/dev/null && \
            _log "  $name installed (brew)" && _any_installed=1 && continue
        fi
        ;;
      pacman)
        if [[ "$pacman_pkg" != "-" ]]; then
          sudo pacman -S --needed --noconfirm "$pacman_pkg" &>/dev/null && \
            _log "  $name installed (pacman)" && _any_installed=1 && continue
        fi
        ;;
    esac

    # Fallback: download from nerd-fonts GitHub releases
    if [[ "$nerd_zip" == "-" ]]; then
      _warn "  warning: no install method for $name on $_PKG_MGR"
      continue
    fi
    if [[ -z "$nf_version" ]]; then
      _warn "  warning: couldn't determine nerd-fonts version — skipping $name"
      continue
    fi

    local url tmp
    url="https://github.com/ryanoasis/nerd-fonts/releases/download/$nf_version/$nerd_zip.zip"
    tmp=$(mktemp -d) || continue
    local dest="$HOME/.local/share/fonts/$font_dir"
    if curl -fsSL "$url" -o "$tmp/font.zip" 2>/dev/null; then
      mkdir -p "$dest"
      unzip -qo "$tmp/font.zip" '*.ttf' -d "$dest" 2>/dev/null || true
      if command -v fc-cache &>/dev/null; then fc-cache -f "$dest" 2>/dev/null || true; fi
      _log "  $name installed from GitHub ($nf_version)"
      _any_installed=1
    else
      _warn "  warning: failed to download $name"
    fi
    rm -rf "$tmp"
  done

  if [[ $_any_installed -eq 0 ]]; then
    _log "  nerd-fonts up to date"
  fi
}

_post_wezterm() {
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
    local ver
    ver=$(wezterm --version 2>/dev/null | awk '{print $2}')
    _log "  wezterm up to date${ver:+ -- $ver}"
    return 0
  fi

  case "${_PKG_MGR:-}" in
    brew)
      if brew list --cask wezterm &>/dev/null; then
        if [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
          brew upgrade --cask wezterm &>/dev/null || true
          _log "  wezterm refreshed (brew)"
        fi
        return 0
      fi
      if brew install --cask wezterm &>/dev/null; then
        _log "  wezterm installed (brew)"
      else
        _warn "  warning: failed to install wezterm (brew)"
      fi
      return 0
      ;;
    pacman)
      if sudo pacman -S --needed --noconfirm wezterm &>/dev/null; then
        _log "  wezterm installed (pacman)"
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
  if [[ "$(id -u)" -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    if [[ "$DOT_QUIET" -eq 1 ]]; then return 0; fi
    if ! sudo true 2>/dev/null; then
      _warn "  warning: sudo not available — cannot install wezterm"
      return 0
    fi
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
  all_urls=$(echo "$release_json" \
    | grep -o '"browser_download_url":[[:space:]]*"[^"]*\.'"$ext"'"' \
    | cut -d'"' -f4)

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
    deb) sudo dpkg -i "$tmp" &>/dev/null || true
         sudo apt-get install -f -y &>/dev/null || rc=$? ;;
    rpm) sudo dnf install -y "$tmp" &>/dev/null || rc=$? ;;
  esac
  rm -f "$tmp"

  if [[ $rc -ne 0 ]]; then
    _warn "  warning: wezterm package install failed"
    return 0
  fi

  _log "  wezterm installed ($ext) -- $latest_tag"
}
