# shellcheck shell=bash
# Custom dep: ensure an active Rust toolchain is configured via rustup.
# This is a no-op on platforms where the pkg manager installs a full
# toolchain (e.g. pacman's rust). On platforms that install rustup as
# a shim without a default (e.g. apt, brew on CI), it runs
# `rustup default stable` so that rustfmt and cargo are functional.

exists() {
  command -v rustup &>/dev/null || return 0
  rustup show active-toolchain &>/dev/null 2>&1
}

install() {
  rustup default stable
}

version() {
  rustup show active-toolchain 2>/dev/null | awk '{print $1}'
}
