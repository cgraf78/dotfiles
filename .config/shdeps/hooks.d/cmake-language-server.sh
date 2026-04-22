# shellcheck shell=bash
# Hook for cmake-language-server — CMake LSP for nvim.
#
# Installed via uv tool install with pygls<2 pinned (pygls 2.x
# removed the LanguageServer import that cmake-language-server uses).

exists() {
  command -v cmake-language-server &>/dev/null
}

version() {
  cmake-language-server --version 2>/dev/null | head -1
}

install() {
  if ! command -v uv &>/dev/null; then
    shdeps_warn "  warning: uv not available — cannot install cmake-language-server"
    return 1
  fi
  uv tool install --force cmake-language-server --with 'pygls<2' &>/dev/null || return 1
}

uninstall() {
  if command -v uv &>/dev/null; then
    uv tool uninstall cmake-language-server &>/dev/null
  fi
}
