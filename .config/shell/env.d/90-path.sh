# shellcheck shell=bash
# Authoritative PATH priority. Vendor and tool bootstraps may mutate PATH
# earlier; this file owns the final, de-duplicated ordering.
#
# Interactive and login shells put the managed directories below first and
# append everything else. Fill-only (non-interactive) shells keep the PATH they
# inherited in the caller's order, so `PATH=/venv/bin:$PATH bash -c ...` and
# git's exec-path prefix still win. Managed directories the caller lacks go
# just before the first inherited system directory, so they still beat system
# tools under a minimal PATH (launchd, `env -i`) without shadowing a caller's
# own entries; entries env.d fragments added during this load are appended.

_path_add() {
  local dir="$1"
  [ -n "$dir" ] || return 0

  case ":$_path_new:" in
    *":$dir:"*) return 0 ;;
  esac

  if [ -n "$_path_new" ]; then
    _path_new="$_path_new:$dir"
  else
    _path_new="$dir"
  fi
}

# Pass each entry of a colon-separated list, in order, to a function. Field
# splitting is much cheaper than peeling entries off with ${rest%%:*}, which
# bash evaluates in quadratic time under multibyte locales; with two lists to
# scan in fill-only shells that cost was measurable. The eval keeps bash from
# parsing zsh's split flag.
if [ -n "${ZSH_VERSION:-}" ]; then
  eval '_path_add_list() {
    local part
    for part in "${(@s.:.)2}"; do "$1" "$part"; done
  }'
else
  _path_add_list() {
    local part IFS=: noglob=0
    case $- in *f*) noglob=1 ;; esac
    set -f
    for part in $2; do "$1" "$part"; done
    [ "$noglob" = 1 ] || set +f
  }
fi

_path_prepend() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  if [ -n "$_path_keep" ]; then
    # Fill-only: a managed dir the caller already has stays where they put
    # it; a missing one waits for _path_add_kept to place it.
    case "$_path_keep" in
      *":$dir:"*) return 0 ;;
    esac
    _path_missing="${_path_missing:+$_path_missing:}$dir"
    return 0
  fi
  _path_add "$dir"
}

# Fill-only: add an inherited entry, placing the missing managed dirs right
# before the first system directory.
# shellcheck disable=SC2329 # invoked indirectly through _path_add_list
_path_add_kept() {
  if [ -n "$_path_missing" ]; then
    case "$1" in
      /usr/bin | /bin | /usr/sbin | /sbin | "$_path_system_prefix")
        _path_add_list _path_add "$_path_missing"
        _path_missing=""
        ;;
    esac
  fi
  _path_add "$1"
}

_path_new=""
_path_keep=""
_path_missing=""
# Termux has no /usr/bin; its system binaries live under $PREFIX/bin.
_path_system_prefix=/usr/bin
if [ -n "${TERMUX_VERSION:-}" ] && [ -n "${PREFIX:-}" ]; then
  _path_system_prefix="$PREFIX/bin"
fi
# The guard keeps this file usable when sourced on its own (tests, probes).
if command -v _shell_env_inherited >/dev/null 2>&1 &&
  _shell_env_inherited PATH; then
  _path_keep=":$_SHELL_ENV_INHERITED_PATH:"
fi

_path_prepend "$HOME/.local/bin"
_path_prepend "$HOME/bin"
_path_prepend "$HOME/.local/share/mise/shims"
_path_prepend "$HOME/.bun/bin"
# Optional vendor bin. Missing dirs are skipped; ~/.local/bin stays first so
# an installer symlink there continues to win over this directory.
_path_prepend "$HOME/.grok/bin"
_path_prepend /opt/homebrew/bin
_path_prepend /opt/homebrew/sbin
_path_prepend /usr/local/bin

if [ -n "$_path_keep" ]; then
  _path_add_list _path_add_kept "$_SHELL_ENV_INHERITED_PATH"
  # No inherited system directory: append whatever is still missing.
  _path_add_list _path_add "$_path_missing"
fi
_path_add_list _path_add "${PATH:-}"

PATH="$_path_new"
export PATH

unset _path_new _path_keep _path_missing _path_system_prefix
unset -f _path_add _path_add_list _path_add_kept _path_prepend
