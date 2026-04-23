# shellcheck shell=bash
# Hook for tree-sitter-cli — needed by nvim-treesitter for parser compilation.
#
# brew/dnf/pacman have packages; apt doesn't, so we grab the prebuilt
# binary from the GitHub release.

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
      if shdeps_reinstall && brew list tree-sitter-cli &>/dev/null; then
        brew upgrade tree-sitter-cli &>/dev/null || return 1
      else
        brew install tree-sitter-cli &>/dev/null || return 1
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
    apt)
      shdeps_github_release_install tree-sitter-cli tree-sitter tree-sitter/tree-sitter || return 1
      ;;
    *)
      shdeps_warn "  warning: no install method for tree-sitter-cli on ${mgr:-unknown}"
      return 1
      ;;
  esac
}
