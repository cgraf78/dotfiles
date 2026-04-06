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

_post_jetbrains_mono_nerd_font() {
  # Install JetBrainsMono Nerd Font using the best method per platform:
  #   macOS: brew install (cask)
  #   Arch:  pacman -S ttf-jetbrains-mono-nerd
  #   Other: download from GitHub releases
  # Idempotent — skips if the font is already installed.

  # Check if already installed
  case "${_PKG_MGR:-}" in
    brew)   brew list font-jetbrains-mono-nerd-font &>/dev/null && return 0 ;;
    pacman) pacman -Q ttf-jetbrains-mono-nerd &>/dev/null && return 0 ;;
  esac
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont"
  if ls "$font_dir"/*.ttf &>/dev/null 2>&1; then return 0; fi

  # Install via native package manager where available
  case "${_PKG_MGR:-}" in
    brew)
      brew install font-jetbrains-mono-nerd-font &>/dev/null && \
        _log "  font-jetbrains-mono-nerd-font installed (brew)" && return 0
      ;;
    pacman)
      sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd &>/dev/null && \
        _log "  font-jetbrains-mono-nerd-font installed (pacman)" && return 0
      ;;
  esac

  # Fallback: download from GitHub releases
  command -v curl &>/dev/null || return 0
  local version url tmp
  version=$(curl -fsSL --no-netrc -H "Authorization:" \
    "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" 2>/dev/null \
    | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4) || return 0
  [[ -n "$version" ]] || return 0

  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$version/JetBrainsMono.zip"
  tmp=$(mktemp -d) || return 0
  if curl -fsSL "$url" -o "$tmp/font.zip" 2>/dev/null; then
    mkdir -p "$font_dir"
    unzip -qo "$tmp/font.zip" '*.ttf' -d "$font_dir" 2>/dev/null || true
    if command -v fc-cache &>/dev/null; then fc-cache -f "$font_dir" 2>/dev/null || true; fi
    _log "  font-jetbrains-mono-nerd-font installed from GitHub ($version)"
  else
    _warn "  warning: failed to download JetBrainsMono Nerd Font"
  fi
  rm -rf "$tmp"
}
