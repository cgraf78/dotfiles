# shellcheck shell=bash
# Status and post-install hooks for nerd-fonts.

_nerd_fonts_entries() {
  printf '%s\n' \
    "JetBrains Mono Nerd Font|font-jetbrains-mono-nerd-font|ttf-jetbrains-mono-nerd|JetBrainsMono|JetBrainsMono" \
    "FiraCode Nerd Font|font-fira-code-nerd-font|ttf-firacode-nerd|FiraCode|FiraCode" \
    "MesloLG Nerd Font|font-meslo-lg-nerd-font|ttf-meslo-nerd|Meslo|Meslo"
}

_nerd_font_installed() {
  local brew_pkg="$1" pacman_pkg="$2" font_dir="$3"
  case "$(shdeps_pkg_mgr)" in
  brew)
    if [[ "$brew_pkg" != "-" ]] && brew list "$brew_pkg" &>/dev/null; then
      return 0
    fi
    ;;
  pacman)
    if [[ "$pacman_pkg" != "-" ]] && pacman -Q "$pacman_pkg" &>/dev/null; then
      return 0
    fi
    ;;
  esac
  [[ -n "$font_dir" ]] && ls "$HOME/.local/share/fonts/$font_dir"/*.ttf &>/dev/null 2>&1
}

status() {
  # In force mode, post() will run and report the result — stay silent here.
  shdeps_reinstall && return 0

  if ! _shdeps_hook_due "nerd-fonts"; then
    shdeps_log_dim "  nerd-fonts up to date"
    return 0
  fi

  local entry name brew_pkg pacman_pkg _nerd_zip font_dir
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg _nerd_zip font_dir <<<"$entry"
    if ! _nerd_font_installed "$brew_pkg" "$pacman_pkg" "$font_dir"; then
      return 1
    fi
  done < <(_nerd_fonts_entries)

  shdeps_log_dim "  nerd-fonts up to date"
  return 0
}

install() {
  # Install fonts from the _FONTS registry below.
  # Each entry: "DisplayName|brew_pkg|pacman_pkg|nerd_fonts_zip|local_dir"
  #   brew_pkg:       homebrew cask name (or - to skip)
  #   pacman_pkg:     pacman package name (or - to skip)
  #   nerd_fonts_zip: zip asset name on ryanoasis/nerd-fonts releases (or - to skip)
  #   local_dir:      subdirectory under ~/.local/share/fonts/ for manual installs

  # Fetch latest nerd-fonts version once for the GitHub fallback path
  local nf_version=""
  if command -v curl &>/dev/null; then
    nf_version=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" 2>/dev/null |
      grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4) || true
  fi

  local entry name brew_pkg pacman_pkg nerd_zip font_dir
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg nerd_zip font_dir <<<"$entry"

    # Check if already installed (skip check when forced to reinstall).
    if ! shdeps_reinstall && _nerd_font_installed "$brew_pkg" "$pacman_pkg" "$font_dir"; then continue; fi

    # Install (or reinstall/upgrade when forced) via native package manager where available.
    case "$(shdeps_pkg_mgr)" in
    brew)
      if [[ "$brew_pkg" != "-" ]]; then
        if shdeps_reinstall && brew list "$brew_pkg" &>/dev/null; then
          brew upgrade "$brew_pkg" &>/dev/null &&
            shdeps_log_ok "  $name reinstalled (brew)" && continue
        else
          brew install "$brew_pkg" &>/dev/null &&
            shdeps_log_ok "  $name installed (brew)" && continue
        fi
      fi
      ;;
    pacman)
      if [[ "$pacman_pkg" != "-" ]]; then
        local pacman_flags=(--noconfirm)
        shdeps_reinstall || pacman_flags+=(--needed)
        local pacman_action="installed"
        shdeps_reinstall && pacman_action="reinstalled"
        sudo pacman -S "${pacman_flags[@]}" "$pacman_pkg" &>/dev/null &&
          shdeps_log_ok "  $name $pacman_action (pacman)" && continue
      fi
      ;;
    esac

    # Fallback: download from nerd-fonts GitHub releases
    if [[ "$nerd_zip" == "-" ]]; then
      shdeps_warn "  warning: no install method for $name on $(shdeps_pkg_mgr)"
      continue
    fi
    if [[ -z "$nf_version" ]]; then
      shdeps_warn "  warning: couldn't determine nerd-fonts version — skipping $name"
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
      local action="installed"
      shdeps_reinstall && action="reinstalled"
      shdeps_log_ok "  $name $action from GitHub ($nf_version)"
    else
      shdeps_warn "  warning: failed to download $name"
    fi
    rm -rf "$tmp"
  done < <(_nerd_fonts_entries)
}
