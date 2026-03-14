#!/bin/bash
# Link WezTerm config into the Windows home when running under WSL.
# Keeps ~/.wezterm.lua in dotfiles as the source of truth.

merge_wezterm() {
  local src="$HOME/.wezterm.lua"
  [[ -f "$src" ]] || return 0

  case "$(uname -s)" in
    Linux)
      [[ -n "${WSL_DISTRO_NAME:-}" ]] || return 0
      ;;
    MINGW*|MSYS*)
      # On Windows-native shells, HOME is already the Windows home.
      return 0
      ;;
    *)
      return 0
      ;;
  esac

  echo "==> Merging WezTerm config..."

  local winhome dest
  if [[ -n "${DOT_TEST_WINDOWS_HOME:-}" ]]; then
    winhome="$DOT_TEST_WINDOWS_HOME"
  elif [[ -d "/mnt/c/Users/$USER" ]]; then
    winhome="/mnt/c/Users/$USER"
  else
    winhome=$(wslpath "$(powershell.exe -NoProfile -Command "Write-Host -NoNewline \$env:USERPROFILE" 2>/dev/null)" 2>/dev/null || true)
  fi
  [[ -n "$winhome" ]] || return 0

  dest="$winhome/.wezterm.lua"
  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    local cur
    cur=$(readlink "$dest" 2>/dev/null || true)
    [[ "$cur" == "$src" ]] && return 0
    rm -f "$dest"
  elif [[ -e "$dest" ]]; then
    mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
  fi

  ln -s "$src" "$dest"
  echo "==> Linked WezTerm config to Windows home: $dest"
}
