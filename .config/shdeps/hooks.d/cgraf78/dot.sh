# shellcheck shell=bash
# Shdeps owns the generic checkout lifecycle. Dot's reviewed installer owns the
# two public entry points for checkout installs, including preservation of the
# client-owned launcher. Release installs publish the public command directly;
# the hook only converges the public library link those installs do not manage.

post() {
  local install_home=${SHDEPS_INSTALL_DIR:-$HOME/.local/share}
  local checkout installer public_lib

  [[ ${1:-} == cgraf78/dot ]] || return 2
  checkout=${install_home%/}/cgraf78/dot
  public_lib=$HOME/.local/lib/dot
  installer=$checkout/support/install-checkout.sh
  if [[ -f $installer && ! -L $installer ]]; then
    # PREFIX identifies Termux's system package tree, not this client's public
    # command/library root. Bind Dot's two public surfaces to the same HOME-local
    # paths on every platform so every client observes one installed topology.
    PREFIX=$HOME/.local \
      BIN_DIR=$HOME/.local/bin \
      DOT_PUBLIC_LIB=$public_lib \
      "${BASH:-bash}" "$installer" || return 1
    return 0
  fi
  # Release roots carry no installer: the public command link is already live.
  # Converge the public library link and fail closed on anything that is not
  # an absent path or a relinkable symlink.
  [[ -d $checkout/lib/dot/public && ! -L $checkout/lib/dot/public ]] || return 1
  if [[ -L $public_lib ]]; then
    [[ $public_lib -ef $checkout/lib/dot/public ]] && return 0
    rm -f -- "$public_lib" || return 1
  elif [[ -e $public_lib ]]; then
    printf 'dot.sh: refusing to replace non-link public library path: %s\n' "$public_lib" >&2
    return 1
  fi
  mkdir -p -- "${public_lib%/*}" || return 1
  ln -s -- "$checkout/lib/dot/public" "$public_lib" || return 1
  return 0
}
