# shellcheck shell=bash
# Enforce a modern Python while keeping the interpreter system-owned whenever
# the active package manager can provide one.

_python_supported_path() {
  local interpreter="$1"
  [[ -x "$interpreter" ]] || return 1
  env "$interpreter" -I -S -c \
    'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' \
    &>/dev/null
}

_python_supported() {
  local interpreter
  interpreter=$(command -v python3 2>/dev/null) || return 1
  _python_supported_path "$interpreter"
}

_python_supported_alternate() {
  local name interpreter prefix
  if command -v brew &>/dev/null &&
    prefix=$(brew --prefix python@3.12 2>/dev/null); then
    interpreter="$prefix/bin/python3.12"
    if _python_supported_path "$interpreter"; then
      printf '%s\n' "$interpreter"
      return 0
    fi
  fi

  for name in python3.14 python3.13 python3.12 python3.11; do
    interpreter=$(command -v "$name" 2>/dev/null) || continue
    _python_supported_path "$interpreter" || continue
    printf '%s\n' "$interpreter"
    return 0
  done
  return 1
}

_python_expose() {
  local interpreter="$1" root wrapper bin_dir link temp
  root="$(shdeps_install_dir)/python-minimum"
  wrapper="$root/python3"
  bin_dir=$(shdeps_bin_dir)
  link="$bin_dir/python3"

  if [[ -e "$link" || -L "$link" ]]; then
    if [[ ! -L "$link" || $(readlink "$link" 2>/dev/null) != "$wrapper" ]]; then
      shdeps_warn "  warning: refusing to replace unowned Python command: $link"
      return 1
    fi
  fi

  mkdir -p "$root" "$bin_dir" || return 1
  temp="$root/.python3.$$"
  if ! (
    umask 077
    {
      printf '#!/usr/bin/env bash\n'
      printf 'exec %q "$@"\n' "$interpreter"
    } >"$temp" && chmod u+x "$temp"
  ); then
    rm -f "$temp"
    return 1
  fi
  mv -f "$temp" "$wrapper" || {
    rm -f "$temp"
    return 1
  }

  if [[ ! -L "$link" ]]; then
    ln -s "$wrapper" "$link" || return 1
  fi
  if ! _python_supported; then
    shdeps_warn \
      "  warning: $bin_dir must precede the older python3 on PATH"
    return 1
  fi
}

_python_install_system() {
  if shdeps_platform_match android; then
    shdeps_pkg_install_for_mgr apt:python
    return
  fi

  shdeps_pkg_install_for_mgr \
    brew:python@3.12 \
    apt:python3.11-venv \
    dnf:python3.11 \
    pacman:python \
    zypper:python311 \
    apk:python3
}

exists() {
  _python_supported
}

install() {
  local interpreter bin_dir
  _python_supported && return 0

  if interpreter=$(_python_supported_alternate); then
    _python_expose "$interpreter"
    return
  fi

  _python_install_system || true
  _python_supported && return 0
  if interpreter=$(_python_supported_alternate); then
    _python_expose "$interpreter"
    return
  fi

  if ! command -v uv &>/dev/null; then
    shdeps_warn \
      "  warning: no system Python 3.11+ is available and uv is unavailable"
    return 1
  fi

  uv python install --default --upgrade 3.12 || return 1
  if ! _python_supported; then
    bin_dir=$(uv python dir --bin 2>/dev/null || printf '%s/.local/bin' "$HOME")
    shdeps_warn \
      "  warning: uv installed Python, but $bin_dir does not precede the older python3 on PATH"
    return 1
  fi
}

version() {
  command -v python3 &>/dev/null || return 0
  env python3 --version 2>&1
}

uninstall() {
  local root wrapper link
  root="$(shdeps_install_dir)/python-minimum"
  wrapper="$root/python3"
  link="$(shdeps_bin_dir)/python3"

  if [[ -L "$link" && $(readlink "$link" 2>/dev/null) == "$wrapper" ]]; then
    rm -f "$link"
  fi
  rm -f "$wrapper"
  rmdir "$root" 2>/dev/null || true
}
