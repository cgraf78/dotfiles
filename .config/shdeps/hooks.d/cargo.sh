# shellcheck shell=bash
# Post-install hook for cargo (Rust toolchain).

post() {
  # On some platforms (apt, brew CI runners) rustup is installed but no
  # default toolchain is configured, leaving rustfmt/cargo non-functional.
  if command -v rustup &>/dev/null && ! rustup show active-toolchain &>/dev/null 2>&1; then
    rustup default stable
  fi
}
