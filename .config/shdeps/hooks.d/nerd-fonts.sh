# shellcheck shell=bash
# Hook for nerd-fonts — patched fonts for terminal/editor icons.

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
      # Check caskroom directory directly — avoids ~1.4s Ruby overhead per
      # brew list call. Fonts are casks so they live in Caskroom, not Cellar.
      if [[ -z "${_NERD_CASKROOM:-}" ]]; then
        _NERD_CASKROOM="$(brew --caskroom 2>/dev/null)"
      fi
      if [[ "$brew_pkg" != "-" && -n "$_NERD_CASKROOM" && -d "$_NERD_CASKROOM/$brew_pkg" ]]; then
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

_nerd_font_version() {
  local brew_pkg="$1" pacman_pkg="$2"
  if [[ "$brew_pkg" != "-" ]] && command -v brew &>/dev/null; then
    if [[ -z "${_NERD_CASKROOM:-}" ]]; then
      _NERD_CASKROOM="$(brew --caskroom 2>/dev/null)"
    fi
    if [[ -n "$_NERD_CASKROOM" && -d "$_NERD_CASKROOM/$brew_pkg" ]]; then
      basename -a "$_NERD_CASKROOM/$brew_pkg"/* 2>/dev/null | sort -V | tail -n 1
      return
    fi
  fi
  if [[ "$pacman_pkg" != "-" ]] && command -v pacman &>/dev/null; then
    pacman -Q "$pacman_pkg" 2>/dev/null | awk '{print $2}'
  fi
}

exists() {
  local entry name brew_pkg pacman_pkg _nerd_zip font_dir
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg _nerd_zip font_dir <<<"$entry"
    if ! _nerd_font_installed "$brew_pkg" "$pacman_pkg" "$font_dir"; then
      return 1
    fi
  done < <(_nerd_fonts_entries)
  return 0
}

version() {
  local installed=0 total=0 entry name brew_pkg pacman_pkg _nerd_zip font_dir version versions=()
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg _nerd_zip font_dir <<<"$entry"
    total=$((total + 1))
    if _nerd_font_installed "$brew_pkg" "$pacman_pkg" "$font_dir"; then
      installed=$((installed + 1))
      version="$(_nerd_font_version "$brew_pkg" "$pacman_pkg")"
      [[ -n "$version" ]] && versions+=("$version")
    fi
  done < <(_nerd_fonts_entries)
  if [[ "${#versions[@]}" -gt 0 ]]; then
    printf '%s\n' "${versions[@]}" | sort -Vu | paste -sd ',' - | awk -v installed="$installed" -v total="$total" '
      {
        if (index($0, ",") == 0 && installed == total) {
          print $0
        } else {
          printf "%s/%s font families installed -- %s\n", installed, total, $0
        }
      }'
  else
    printf '%s/%s font families installed\n' "$installed" "$total"
  fi
}

install() {
  # Fetch latest nerd-fonts version once for the GitHub fallback path
  local nf_version=""
  if command -v curl &>/dev/null; then
    nf_version=$(shdeps_curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest" 2>/dev/null |
      grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4) || true
  fi

  local entry name brew_pkg pacman_pkg nerd_zip font_dir
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg nerd_zip font_dir <<<"$entry"

    # Skip already-installed fonts unless reinstalling
    if ! shdeps_reinstall && _nerd_font_installed "$brew_pkg" "$pacman_pkg" "$font_dir"; then continue; fi

    # Install via native package manager where available
    case "$(shdeps_pkg_mgr)" in
      brew)
        if [[ "$brew_pkg" != "-" ]]; then
          if shdeps_reinstall && brew list "$brew_pkg" &>/dev/null; then
            brew upgrade "$brew_pkg" &>/dev/null && continue
          else
            brew install "$brew_pkg" &>/dev/null && continue
          fi
        fi
        ;;
      pacman)
        if [[ "$pacman_pkg" != "-" ]]; then
          local pacman_flags=(--noconfirm)
          shdeps_reinstall || pacman_flags+=(--needed)
          sudo pacman -S "${pacman_flags[@]}" "$pacman_pkg" &>/dev/null && continue
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
    if shdeps_curl -fsSL "$url" -o "$tmp/font.zip" 2>/dev/null; then
      mkdir -p "$dest"
      unzip -qo "$tmp/font.zip" '*.ttf' -d "$dest" 2>/dev/null || true
      if command -v fc-cache &>/dev/null; then fc-cache -f "$dest" 2>/dev/null || true; fi
    else
      shdeps_warn "  warning: failed to download $name"
    fi
    rm -rf "$tmp"
  done < <(_nerd_fonts_entries)
}

uninstall() {
  local entry name brew_pkg pacman_pkg _nerd_zip font_dir
  while IFS= read -r entry; do
    IFS='|' read -r name brew_pkg pacman_pkg _nerd_zip font_dir <<<"$entry"
    case "$(shdeps_pkg_mgr)" in
      brew)
        if [[ "$brew_pkg" != "-" ]] && brew list "$brew_pkg" &>/dev/null; then
          shdeps_warn "  $name: remove manually via: brew uninstall $brew_pkg"
          continue
        fi
        ;;
      pacman)
        if [[ "$pacman_pkg" != "-" ]] && pacman -Q "$pacman_pkg" &>/dev/null; then
          shdeps_warn "  $name: remove manually via: sudo pacman -R $pacman_pkg"
          continue
        fi
        ;;
    esac
    # GitHub-installed fonts: remove font directory
    if [[ -n "$font_dir" && -d "$HOME/.local/share/fonts/$font_dir" ]]; then
      rm -rf "$HOME/.local/share/fonts/$font_dir"
    fi
  done < <(_nerd_fonts_entries)
  if command -v fc-cache &>/dev/null; then fc-cache -f 2>/dev/null || true; fi
}
