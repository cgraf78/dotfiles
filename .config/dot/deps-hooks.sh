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
            _log "  $name installed (brew)" && continue
        fi
        ;;
      pacman)
        if [[ "$pacman_pkg" != "-" ]]; then
          sudo pacman -S --needed --noconfirm "$pacman_pkg" &>/dev/null && \
            _log "  $name installed (pacman)" && continue
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
    else
      _warn "  warning: failed to download $name"
    fi
    rm -rf "$tmp"
  done
}
