# shellcheck shell=bash
# Authoritative PATH priority. Vendor and tool bootstraps may mutate PATH
# earlier; this file owns the final, de-duplicated ordering.
#
# Interactive and login shells put the managed directories below first and
# append everything else. Fill-only (non-interactive) shells keep the PATH they
# inherited in the caller's order, so `PATH=/venv/bin:$PATH bash -c ...` and
# git's exec-path prefix still win. Managed directories the caller lacks go
# just before the first inherited system or host package directory
# (/usr/local, Homebrew), so they still beat system tools under a minimal PATH
# (launchd, `env -i`, sudo's secure_path, systemd, sshd) without shadowing a
# caller's own entries; entries env.d fragments added during this load are
# appended. Empty entries mean the current directory and are always dropped;
# fill-only shells drop the `.` spelling too, since with the caller's order
# kept a leading `.` would outrank every managed directory. Other relative
# entries (a Makefile's `node_modules/.bin`) stay where the caller put them.

_path_add() {
  local dir="$1"
  [ -n "$dir" ] || return 0
  case "$dir" in
    . | ./) [ -z "$_path_keep" ] || return 0 ;;
  esac

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
    _path_managed="$_path_managed$dir:"
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
# before the first system or host package directory. /usr/local/bin and the
# Homebrew dirs are managed themselves, so at one of those only the missing
# dirs that outrank it go in (a missing /usr/local/bin must not jump an
# inherited /opt/homebrew/bin); the rest wait for a later anchor.
# shellcheck disable=SC2329 # invoked indirectly through _path_add_list
_path_add_kept() {
  if [ -n "$_path_missing" ]; then
    case "$1" in
      /usr/bin | /bin | /usr/sbin | /sbin | "$_path_system_prefix" | \
        /usr/local/bin | /usr/local/sbin | /opt/homebrew/bin | /opt/homebrew/sbin)
        case "$_path_managed" in
          *":$1:"*)
            _path_before="${_path_managed%%":$1:"*}:"
            _path_later=""
            _path_add_list _path_add_ranked "$_path_missing"
            _path_missing="$_path_later"
            ;;
          *)
            _path_add_list _path_add "$_path_missing"
            _path_missing=""
            ;;
        esac
        ;;
    esac
  fi
  _path_add "$1"
}

# shellcheck disable=SC2329 # invoked indirectly through _path_add_list
_path_add_ranked() {
  case "$_path_before" in
    *":$1:"*) _path_add "$1" ;;
    *) _path_later="${_path_later:+$_path_later:}$1" ;;
  esac
}

_path_new=""
_path_keep=""
_path_missing=""
# Existing managed dirs in priority order, colon-delimited on both ends.
_path_managed=":"
_path_before=""
_path_later=""
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

unset _path_new _path_keep _path_missing _path_managed _path_before \
  _path_later _path_system_prefix
unset -f _path_add _path_add_list _path_add_kept _path_add_ranked _path_prepend
