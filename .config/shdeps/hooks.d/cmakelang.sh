# shellcheck shell=bash
# Hook for cmakelang — provides cmake-format and cmake-lint.
#
# Distro packages are inconsistent: some call the package cmake-format,
# others package the upstream Python project as python3-cmakelang. uv is the
# cross-platform fallback because cmakelang is the PyPI package that owns both
# CLIs.

exists() {
  command -v cmake-format &>/dev/null && command -v cmake-lint &>/dev/null
}

version() {
  cmake-format --version 2>/dev/null | head -1
}

install() {
  shdeps_pkg_install_for_mgr \
    brew:cmake-format \
    apt:cmake-format \
    dnf:python3-cmakelang \
    pacman:cmake-format \
    zypper:python3-cmakelang \
    apk:cmake-format && exists && return 0

  if ! command -v uv &>/dev/null; then
    shdeps_warn "  warning: uv not available — cannot install cmakelang"
    return 1
  fi

  local install_dir bin_dir
  install_dir="$(shdeps_install_dir)/cmakelang"
  bin_dir=$(shdeps_bin_dir)
  mkdir -p "$bin_dir"
  env \
    "UV_TOOL_DIR=$install_dir/tools" \
    "UV_TOOL_BIN_DIR=$install_dir/bin" \
    uv tool install --force cmakelang &>/dev/null || return 1

  ln -sf "$install_dir/bin/cmake-format" "$bin_dir/cmake-format"
  ln -sf "$install_dir/bin/cmake-lint" "$bin_dir/cmake-lint"
}

uninstall() {
  if command -v uv &>/dev/null; then
    env \
      "UV_TOOL_DIR=$(shdeps_install_dir)/cmakelang/tools" \
      "UV_TOOL_BIN_DIR=$(shdeps_install_dir)/cmakelang/bin" \
      uv tool uninstall cmakelang &>/dev/null || true
  fi
  rm -f "$(shdeps_bin_dir)/cmake-format" "$(shdeps_bin_dir)/cmake-lint"
}
