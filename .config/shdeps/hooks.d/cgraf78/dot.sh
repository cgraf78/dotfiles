# shellcheck shell=bash
# Shdeps owns the generic checkout lifecycle. Dot's reviewed installer owns the
# two public entry points, including preservation of the client-owned launcher.

post() {
  local install_home=${SHDEPS_INSTALL_DIR:-$HOME/.local/share}
  local checkout installer

  [[ ${1:-} == cgraf78/dot ]] || return 2
  checkout=${install_home%/}/cgraf78/dot
  installer=$checkout/support/install-checkout.sh
  [[ -f $installer && ! -L $installer ]] || return 1
  # PREFIX identifies Termux's system package tree, not this client's public
  # command/library root. Bind Dot's two public surfaces to the same HOME-local
  # paths on every platform so every client observes one installed topology.
  PREFIX=$HOME/.local \
    BIN_DIR=$HOME/.local/bin \
    DOT_PUBLIC_LIB=$HOME/.local/lib/dot \
    "${BASH:-bash}" "$installer"
}
