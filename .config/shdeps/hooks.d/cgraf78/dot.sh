# shellcheck shell=bash
# Release installs publish the public command directly; the hook only
# converges the public library link those installs do not manage.

post() {
  local install_home=${SHDEPS_INSTALL_DIR:-$HOME/.local/share}
  local checkout public_lib

  [[ ${1:-} == cgraf78/dot ]] || return 2
  checkout=${install_home%/}/cgraf78/dot
  public_lib=$HOME/.local/lib/dot
  # The public command link is already live. Converge the public library link
  # and fail closed on anything that is not an absent path or a relinkable
  # symlink.
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
