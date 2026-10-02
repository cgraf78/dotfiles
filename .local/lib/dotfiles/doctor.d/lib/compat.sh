# shellcheck shell=bash
# Client-owned doctor compatibility for application checks moved out of the
# standalone coordinator. All result publication goes through doctor API v1.

dot_doctor_source doctor.d/lib/shdeps-assets.sh || return

_dr_section() { dot_doctor_section "$@"; }
_dr_ok() { dot_doctor_ok "$@"; }
_dr_warn() { dot_doctor_warn "$@"; }
_dr_fail() { dot_doctor_fail "$@"; }
_dr_skip() { dot_doctor_skip "$@"; }
# Display a path for a record: HOME abbreviated, and any TAB or line break
# (legal in file names, illegal in a record, where it would abort the
# worker) turned into a space.
_dr_tilde() {
  local out
  out=$(dot_doctor_display_path "$@") || return
  printf '%s\n' "${out//[$'\t\r\n']/ }"
}

# Report $1 as one line of record text via REPLY.
_dr_one_line() {
  REPLY=${1//[$'\t\r\n']/ }
}

# Informational rows use the coordinator's `info` kind when its doctor API
# provides one, and render as a passing check on older coordinators, so the
# same extension runs against either.
_dr_info() {
  if declare -F dot_doctor_info >/dev/null 2>&1; then
    dot_doctor_info "$@"
  else
    dot_doctor_ok "$@"
  fi
}

_merge_hook_family() {
  printf '%s/%s\n' "$HOME/.config/dot/merge-hooks.d" "$1"
}

# Resolve the deadline runner once per worker into _DR_TIMEOUT_BIN:
# timeout(1), else gtimeout from GNU coreutils, else empty for the builtin
# watchdog. Resolve before narrowing PATH.
#
# Only a coreutils timeout (GNU or uutils) is used: callers rely on its 124
# status to tell a deadline from a failure. BusyBox's (Alpine) execs the
# command in its own place and kills it, so a deadline surfaces as a plain
# SIGTERM death (143) plus the shell's "Terminated" notice on stderr; the
# builtin watchdog reports that case correctly instead.
_dr_timeout_resolve() {
  local bin version
  if [[ -z ${_DR_TIMEOUT_BIN+x} ]]; then
    _DR_TIMEOUT_BIN=
    for bin in timeout gtimeout; do
      bin=$(type -P "$bin" 2>/dev/null) || continue
      version=$("$bin" --version 2>/dev/null </dev/null) || continue
      [[ $version == *coreutils* ]] || continue
      _DR_TIMEOUT_BIN=$bin
      break
    done
  fi
}

# Run an external command with a deadline of $1 seconds and return its
# status, or 124 when the deadline passed. Uses timeout(1) or gtimeout where
# installed; otherwise a builtin watchdog, so a host without either (stock
# macOS) is still bounded. The command's stdin, stdout, and stderr are the
# caller's.
#
# The watchdog runs the command as its own process group and signals the
# whole group (TERM, then KILL two seconds later), as timeout(1) does: a
# grandchild left behind would keep a `$(...)` capture open past the
# deadline. The watchdog is its own process group too, so stopping it stops
# its sleep with it and the worker supervisor sees no leftovers. Everything
# runs in a subshell, so job control and errexit changes stay inside.
_dr_run_bounded() {
  local secs=$1
  shift
  _dr_timeout_resolve
  if [[ -n $_DR_TIMEOUT_BIN ]]; then
    "$_DR_TIMEOUT_BIN" -k 2 "$secs" "$@"
    return
  fi
  (
    set +e
    # A private, unpredictable directory for the deadline marker; without
    # one, a signal death stands in for it.
    marks=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-deadline.XXXXXX" 2>/dev/null) || marks=
    set -m
    "$@" &
    pid=$!
    (
      sleep "$secs"
      [[ -z $marks ]] || : >"$marks/fired"
      kill -TERM -- "-$pid"
      sleep 2
      kill -KILL -- "-$pid"
    ) </dev/null >/dev/null 2>&1 &
    wd=$!
    set +m
    wait "$pid"
    rc=$?
    kill -KILL -- "-$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    if [[ -n $marks ]]; then
      [[ ! -e $marks/fired ]] || rc=124
      rm -rf "$marks"
    elif ((rc == 143 || rc == 137)); then
      rc=124
    fi
    exit "$rc"
  )
}

# Load Dot's public hook runtime into the current shell, so a doctor check
# can source a merge hook and ask it what it would render instead of keeping
# a second renderer that could drift. Call it inside a subshell: the runtime
# defines many functions and globals. The worker exposes the engine root as
# DOT_SOURCE_ROOT; doctor API v1 does not document that, so a missing or
# different layout fails here and the caller reports the check as skipped.
_dr_hook_runtime_source() {
  local lib=${DOT_SOURCE_ROOT:-}/lib/dot/public/hook-runtime-v1 module

  [[ -n ${DOT_SOURCE_ROOT:-} && -r $lib/hook-api.sh ]] || return 1
  # shellcheck source=/dev/null
  . "$DOT_SOURCE_ROOT/lib/dot/public/xdg.sh" || return 1
  for module in log temp merge-block families merge-hooks extension-trust hook-api; do
    # shellcheck source=/dev/null
    . "$lib/$module.sh" || return 1
  done
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
