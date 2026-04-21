# shellcheck shell=bash
# Hook for tree-sitter-cli — needed by nvim-treesitter for grammars
# that require generation (e.g. doxygen).
#
# brew/dnf/pacman have packages; apt doesn't and cargo install requires
# rustc ≥ 1.86 which Debian stable doesn't ship yet.
# TODO: add cargo fallback for apt once Debian ships rustc ≥ 1.86.

exists() {
  command -v tree-sitter &>/dev/null
}

version() {
  tree-sitter --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

install() {
  local mgr
  mgr=$(shdeps_pkg_mgr)

  case "$mgr" in
    brew)
      if shdeps_reinstall && brew list tree-sitter &>/dev/null; then
        brew upgrade tree-sitter &>/dev/null || return 1
      else
        brew install tree-sitter &>/dev/null || return 1
      fi
      ;;
    dnf)
      if ! shdeps_require_sudo; then
        shdeps_warn "  warning: sudo not available — cannot install tree-sitter-cli"
        return 1
      fi
      sudo dnf install -y tree-sitter-cli &>/dev/null || return 1
      ;;
    pacman)
      if ! shdeps_require_sudo; then
        shdeps_warn "  warning: sudo not available — cannot install tree-sitter-cli"
        return 1
      fi
      local pacman_flags=(--noconfirm)
      shdeps_reinstall || pacman_flags+=(--needed)
      sudo pacman -S "${pacman_flags[@]}" tree-sitter-cli &>/dev/null || return 1
      ;;
    *)
      shdeps_warn "  warning: no install method for tree-sitter-cli on ${mgr:-unknown}"
      return 1
      ;;
  esac
}
