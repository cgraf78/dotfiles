# shellcheck shell=bash
# Post-install hook for clangd.

post() {
  # Homebrew installs clangd via the keg-only llvm formula, so expose it on
  # PATH through ~/.local/bin for editors and shells that expect `clangd`.
  if [[ "${_PKG_MGR:-}" != "brew" ]]; then
    return 0
  fi

  local llvm_prefix clangd_bin link_path
  llvm_prefix=$(brew --prefix llvm 2>/dev/null) || return 0
  clangd_bin="$llvm_prefix/bin/clangd"
  [[ -x "$clangd_bin" ]] || return 0

  mkdir -p "$HOME/.local/bin"
  link_path="$HOME/.local/bin/clangd"
  ln -sfn "$clangd_bin" "$link_path"
}
