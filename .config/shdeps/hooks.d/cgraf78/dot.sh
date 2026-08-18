# shellcheck shell=bash
# Shdeps owns the generic checkout lifecycle. Dot's reviewed installer owns the
# two public entry points, including preservation of the client-owned adapter.

post() {
  local checkout installer

  [[ ${1:-} == cgraf78/dot ]] || return 2
  checkout=${SHDEPS_INSTALL_DIR%/}/cgraf78/dot
  installer=$checkout/support/install-checkout.sh
  [[ -f $installer && ! -L $installer ]] || return 1
  "${BASH:-bash}" "$installer"
}
