# shellcheck shell=bash
# Hook for cmake-language-server — CMake LSP for nvim.
#
# Installed via uv tool install with pygls<2 pinned (pygls 2.x
# removed the LanguageServer import that cmake-language-server uses).

exists() {
  command -v cmake-language-server &>/dev/null
}

version() {
  local active tool installed_version path_field candidate_version=""
  active=$(command -v cmake-language-server 2>/dev/null) || return 0

  while read -r tool installed_version path_field; do
    if [[ "$tool" == "cmake-language-server" && "$installed_version" == v[0-9]* ]]; then
      candidate_version=${installed_version#v}
      continue
    fi
    if [[ "$tool" == "-" && "$installed_version" == "cmake-language-server" ]]; then
      path_field=${path_field#\(}
      path_field=${path_field%\)}
      if [[ -n "$candidate_version" && "$path_field" == "$active" ]]; then
        printf 'cmake-language-server %s\n' "$candidate_version"
        return 0
      fi
      continue
    fi
    candidate_version=""
  done < <(uv tool list --show-paths 2>/dev/null)

  # Version detail is optional. An absent, malformed, or shadowed uv install is
  # better represented by no detail than by launching the slow CLI or guessing.
  return 0
}

install() {
  if ! command -v uv &>/dev/null; then
    shdeps_warn "  warning: uv not available — cannot install cmake-language-server"
    return 1
  fi
  # uv tool install fails on musl (Alpine) — pygls requires glibc
  if [ -f /etc/alpine-release ]; then
    return 0
  fi
  uv tool install --force cmake-language-server --with 'pygls<2' &>/dev/null || return 1
}

uninstall() {
  if command -v uv &>/dev/null; then
    uv tool uninstall cmake-language-server &>/dev/null
  fi
}
