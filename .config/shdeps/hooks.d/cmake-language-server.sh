# shellcheck shell=bash
# Retirement-only hook for the former Python CMake language server.
#
# Keep this hook while existing fleet manifests can still contain the removed
# custom dependency. `shdeps prune` sources the old dependency hook to remove
# its uv-owned payload before dropping manifest state. With no dependency row
# and no install/status functions, new machines cannot install it.

uninstall() {
  [[ "${1:-}" == "cmake-language-server" ]] || return 1
  command -v uv &>/dev/null || return 0
  uv tool uninstall cmake-language-server &>/dev/null || true
}
