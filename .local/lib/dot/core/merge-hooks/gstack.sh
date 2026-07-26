# shellcheck shell=bash
# gstack install-shape migration.
#
# shdeps post hooks only run when a dependency changes. This merge hook keeps
# `dot update` refreshing lightweight registrations so newly installed agents
# pick up gstack without requiring gstack itself to update.

_dot_gstack_register_lib="${DOT_GSTACK_REGISTER_LIB:-$HOME/.local/lib/dot/gstack-register/api.sh}"
# shellcheck source=../../gstack-register/api.sh disable=SC1091
. "$_dot_gstack_register_lib"

merge() {
  local dir
  dir=$(dot_gstack_dir)

  [[ -d "$dir" ]] || return 0

  dot_gstack_register_all
}
