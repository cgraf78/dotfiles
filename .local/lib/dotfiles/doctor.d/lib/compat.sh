# shellcheck shell=bash
# Client-owned doctor compatibility for application checks moved out of the
# standalone coordinator. All result publication goes through doctor API v1.

dot_doctor_source doctor.d/lib/shdeps-assets.sh || return

_dr_section() { dot_doctor_section "$@"; }
_dr_ok() { dot_doctor_ok "$@"; }
_dr_warn() { dot_doctor_warn "$@"; }
_dr_fail() { dot_doctor_fail "$@"; }
_dr_skip() { dot_doctor_skip "$@"; }
_dr_tilde() { dot_doctor_display_path "$@"; }

_merge_hook_family() {
  printf '%s/%s\n' "$HOME/.config/dot/merge-hooks.d" "$1"
}

_dr_account_home() {
  local account entry name _password _uid _gid _gecos home _shell
  local candidate id_command="" getent_command=""

  REPLY=
  for candidate in \
    /data/data/com.termux/files/usr/bin/id \
    /usr/bin/id \
    /bin/id; do
    [[ -x "$candidate" ]] || continue
    id_command=$candidate
    break
  done
  [[ -n "$id_command" ]] || return 1
  account=$("$id_command" -un 2>/dev/null) || return 1
  case "$account" in
    "" | *[!A-Za-z0-9._-]*) return 1 ;;
  esac

  for candidate in \
    /usr/bin/getent \
    /bin/getent \
    /data/data/com.termux/files/usr/bin/getent; do
    [[ -x "$candidate" ]] || continue
    getent_command=$candidate
    break
  done
  if [[ -n "$getent_command" ]]; then
    entry=$("$getent_command" passwd "$account" 2>/dev/null) || entry=
    if IFS=: read -r name _password _uid _gid _gecos home _shell <<<"$entry" &&
      [[ "$name" == "$account" ]]; then
      REPLY=$home
    fi
  fi

  if [[ -z "$REPLY" &&
    "$id_command" == /data/data/com.termux/files/usr/bin/id &&
    -d /data/data/com.termux/files/home ]]; then
    REPLY=/data/data/com.termux/files/home
  fi

  if [[ -z "$REPLY" && -x /usr/bin/dscl ]]; then
    entry=$(/usr/bin/dscl /Search -read "/Users/$account" NFSHomeDirectory 2>/dev/null) || entry=
    case "$entry" in
      "NFSHomeDirectory: "*) REPLY=${entry#NFSHomeDirectory: } ;;
    esac
  fi

  if [[ -z "$REPLY" && -r /etc/passwd ]]; then
    while IFS=: read -r name _password _uid _gid _gecos home _shell; do
      [[ "$name" == "$account" ]] || continue
      REPLY=$home
      break
    done </etc/passwd
  fi

  [[ "$REPLY" == /* && -d "$REPLY" ]]
}

_dr_account_scoped_command() {
  local label="$1" command_name="$2" test_command="${3:-}"
  local account_home

  if [[ "${DOT_TEST:-0}" == "1" ]]; then
    if [[ -z "$test_command" || ! -x "$test_command" ]]; then
      _dr_skip "$label skipped: test $command_name is not configured"
      return 1
    fi
    REPLY="$test_command"
    return 0
  fi

  if ! _dr_account_home; then
    _dr_skip "$label skipped: account home could not be resolved"
    return 1
  fi
  account_home="$REPLY"
  if [[ ! -d "$HOME" || ! "$HOME" -ef "$account_home" ]]; then
    _dr_skip "$label skipped: HOME is not the account home: $HOME"
    return 1
  fi

  if ! REPLY=$(command -v "$command_name" 2>/dev/null); then
    _dr_skip "$label skipped: $command_name not found"
    return 1
  fi
}

# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOT_SHELL_ENV_DIR=$HOME/.config/shell/env.d
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOT_SHELL_INTERACTIVE_DIR=$HOME/.config/shell/interactive.d
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOTFILES=${DOT_CLIENT_GIT_DIR:-$HOME/.dotfiles}
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"

_dr_physical_path() {
  local path=$1 directory base
  while [[ $path != / && $path == */ ]]; do
    path=${path%/}
  done
  case $path in
    /)
      directory=/
      base=/
      ;;
    */*)
      directory=${path%/*}
      base=${path##*/}
      [[ -n $directory ]] || directory=/
      ;;
    *)
      directory=.
      base=$path
      ;;
  esac
  [[ -d $directory ]] || return 1
  directory=$(cd "$directory" && pwd -P) || return 1
  printf '%s/%s\n' "$directory" "$base"
}

_dr_symlink_target_path() {
  local link=$1 target link_directory
  target=$(readlink "$link") || return 1
  case $target in
    /*) _dr_physical_path "$target" ;;
    *)
      case $link in
        */*)
          link_directory=${link%/*}
          [[ -n $link_directory ]] || link_directory=/
          ;;
        *) link_directory=. ;;
      esac
      _dr_physical_path "$link_directory/$target"
      ;;
  esac
}

_dr_symlink_points_to() {
  local link=$1 expected=$2 actual expected_physical
  [[ -e $expected ]] || return 1
  actual=$(_dr_symlink_target_path "$link") || return 1
  expected_physical=$(_dr_physical_path "$expected") || return 1
  [[ $actual == "$expected_physical" ]]
}

_dr_is_dotfiles_checkout() {
  local root home_real root_real
  root=$(git -C "$HOME" rev-parse --show-toplevel 2>/dev/null) || return 1
  home_real=$(cd "$HOME" && pwd -P) || return 1
  root_real=$(cd "$root" && pwd -P) || return 1
  [[ $root_real == "$home_real" ]]
}
