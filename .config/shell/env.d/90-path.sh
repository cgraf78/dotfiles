# shellcheck shell=bash
# Authoritative PATH priority. Vendor and tool bootstraps may mutate PATH
# earlier; this file owns the final, de-duplicated ordering.

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

_path_prepend() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  _path_add "$dir"
}

_path_new=""

_path_prepend "$HOME/.local/bin"
_path_prepend "$HOME/bin"
_path_prepend "$HOME/.local/share/mise/shims"
_path_prepend "$HOME/.bun/bin"
_path_prepend /opt/homebrew/bin
_path_prepend /opt/homebrew/sbin
_path_prepend /usr/local/bin

_path_rest="${PATH:-}"
while [ -n "$_path_rest" ]; do
  case "$_path_rest" in
    *:*)
      _path_part="${_path_rest%%:*}"
      _path_rest="${_path_rest#*:}"
      ;;
    *)
      _path_part="$_path_rest"
      _path_rest=""
      ;;
  esac
  _path_add "$_path_part"
done

PATH="$_path_new"
export PATH

unset _path_new _path_rest _path_part
unset -f _path_add _path_prepend
