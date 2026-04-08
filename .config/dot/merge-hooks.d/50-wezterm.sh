#!/bin/bash
# Copy WezTerm config into the Windows home when running under WSL.
# Keeps ~/.wezterm.lua in dotfiles as the source of truth.

merge() {
  local src="$HOME/.config/wezterm/wezterm.lua"
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

  echo "  WezTerm"

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
    rm -f "$dest"
  elif [[ -e "$dest" ]] && ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
  fi

  if [[ ! -e "$dest" ]] || ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    cp "$src" "$dest"
  fi
}
