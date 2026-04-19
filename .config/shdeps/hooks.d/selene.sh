# shellcheck shell=bash
# Hook for selene — Rust-based Lua linter.
#
# Prefers any selene already on PATH, then tries the native package
# manager where selene is packaged (brew on macOS, pacman on Arch
# `extra`), and finally falls back to `cargo install` everywhere
# else. Compiling via cargo takes ~2 min on first install but is
# reproducible across hosts and avoids distro-version skew.
#
# Chosen over luacheck because it ships as a single static Rust
# binary: no lua-argparse runtime tangle, no distro packaging
# roulette (Arch's `luacheck` wrapper breaks when the luarocks
# lua-version layout drifts, which is how this swap came about).

exists() {
  command -v selene &>/dev/null
}

version() {
  selene --version 2>/dev/null
}

install() {
  local mgr
  mgr=$(shdeps_pkg_mgr)

  case "$mgr" in
    brew)
      brew install selene >/dev/null 2>&1 && return 0
      ;;
    pacman)
      if shdeps_require_sudo; then
        sudo pacman -Sy --needed --noconfirm selene >/dev/null 2>&1 && return 0
      fi
      ;;
  esac

  # Fallback: cargo install into an isolated per-user prefix.
  if ! command -v cargo &>/dev/null; then
    shdeps_warn "  warning: cargo not found — cannot install selene"
    return 1
  fi

  local install_dir bin_path
  install_dir="$(shdeps_install_dir)/selene"
  bin_path="$install_dir/bin/selene"

  mkdir -p "$install_dir/bin" || return 1

  if ! cargo install --locked --root "$install_dir" selene >/dev/null 2>&1; then
    shdeps_warn "  warning: cargo install failed for selene"
    return 1
  fi

  [[ -x "$bin_path" ]] || {
    shdeps_warn "  warning: selene binary missing at $bin_path after install"
    return 1
  }

  ln -sfn "$bin_path" "$(shdeps_bin_dir)/selene"
}
