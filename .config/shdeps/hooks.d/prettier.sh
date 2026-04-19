# shellcheck shell=bash
# Hook for prettier — Node.js code formatter.
#
# Managed as a custom hook (instead of the built-in `npm` method) so
# that a prettier already present on PATH is treated as satisfying the
# dep. Some hosts ship prettier preinstalled and/or restrict global
# `npm install` via a policy wrapper, which would otherwise cause
# noisy install failures on every `dot update`. When prettier is not
# already available, install it the same way the npm method would —
# into an isolated per-user prefix.

exists() {
  command -v prettier &>/dev/null
}

version() {
  prettier --version 2>/dev/null
}

install() {
  if ! command -v npm &>/dev/null; then
    shdeps_warn "  warning: npm not found — cannot install prettier"
    return 1
  fi

  local install_dir bin_path
  install_dir="$(shdeps_install_dir)/prettier"
  bin_path="$install_dir/bin/prettier"

  mkdir -p "$install_dir/bin" || return 1

  if ! npm install -g --prefix "$install_dir" prettier >/dev/null 2>&1; then
    shdeps_warn "  warning: npm install failed for prettier"
    return 1
  fi

  [[ -x "$bin_path" ]] || {
    shdeps_warn "  warning: prettier binary missing at $bin_path after install"
    return 1
  }

  ln -sfn "$bin_path" "$(shdeps_bin_dir)/prettier"
}
