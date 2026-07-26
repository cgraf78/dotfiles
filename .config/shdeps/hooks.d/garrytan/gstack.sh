# shellcheck shell=bash
# Post-install hook for gstack.

_dot_gstack_register_lib="${DOT_GSTACK_REGISTER_LIB:-$HOME/.local/lib/dot/gstack-register/api.sh}"
# shellcheck source=../../../../.local/lib/dot/gstack-register/api.sh disable=SC1091
. "$_dot_gstack_register_lib"

post() {
  dot_gstack_register_all
}

uninstall() {
  dot_gstack_unregister_all
}
