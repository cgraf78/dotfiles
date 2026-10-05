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

# Items an older Dot folds into a list row's detail before "and N more".
_DR_LIST_SAMPLE=3

# File one verdict row with every part it may carry: LEVEL (ok, warn, fail,
# skip, or info), MESSAGE, DETAIL (the row's own evidence; may be empty), a
# count N, then N next steps (empty ones are dropped), then one ITEM per
# entry. _dr_list_row and _dr_hint_row cover the usual shapes; this one is
# for a row whose explanation is not a step (detail beside a list) or that
# has more than one step, each of which should stand on its own line. A Dot
# whose doctor API has dot_doctor_item and dot_doctor_hint renders the
# detail on the row, the items as an indented list (folding the tail
# itself), and each step as its own next-step line. On an older one, the
# detail, the first _DR_LIST_SAMPLE items, "and N more", and the steps are
# joined with "; " into the row's detail. Each part becomes one line of
# record text.
_dr_row() {
  local level=$1 message=$2 detail=${3-} count=${4-} item joined
  local -a steps=()
  case $level in
    ok | warn | fail | skip | info) ;;
    *) return 2 ;;
  esac
  [[ $count =~ ^(0|[1-9][0-9]*)$ ]] && (($# >= 4 + count)) || return 2
  shift 4
  for item in "${@:1:count}"; do
    [[ -z $item ]] || steps+=("$item")
  done
  shift "$count"
  if declare -F dot_doctor_item >/dev/null 2>&1 &&
    declare -F dot_doctor_hint >/dev/null 2>&1; then
    _dr_one_line "$detail"
    "_dr_$level" "$message" "$REPLY" || return
    for item; do
      _dr_one_line "$item"
      dot_doctor_item "$REPLY" || return
    done
    for item in ${steps[@]+"${steps[@]}"}; do
      _dr_one_line "$item"
      dot_doctor_hint "$REPLY" || return
    done
    return 0
  fi
  joined=$detail
  for item in "${@:1:_DR_LIST_SAMPLE}"; do
    joined+=${joined:+; }$item
  done
  (($# <= _DR_LIST_SAMPLE)) || joined+="; and $(($# - _DR_LIST_SAMPLE)) more"
  for item in ${steps[@]+"${steps[@]}"}; do
    joined+=${joined:+; }$item
  done
  _dr_one_line "$joined"
  "_dr_$level" "$message" "$REPLY"
}

# File one verdict row whose evidence is a list: LEVEL (ok, warn, fail,
# skip, or info), MESSAGE, a next step HINT (empty for none), then one ITEM
# per entry, rendered as _dr_row renders a row without detail.
_dr_list_row() {
  (($# >= 3)) || return 2
  _dr_row "$1" "$2" '' 1 "$3" "${@:4}"
}

# File one verdict row with a next step: LEVEL (ok, warn, fail, skip, or
# info), MESSAGE, DETAIL (the evidence; may be empty), and HINT (what to
# do; may be empty). A Dot whose doctor API has dot_doctor_hint renders
# the hint as its own next-step line; on an older one it is appended to
# the detail after "; ", which is how every row carried its step before.
# Detail and hint each become one line of record text.
_dr_hint_row() {
  local level=$1 message=$2 detail=${3-} hint=${4-}
  case $level in
    ok | warn | fail | skip | info) ;;
    *) return 2 ;;
  esac
  (($# == 4)) || return 2
  _dr_one_line "$hint"
  hint=$REPLY
  if [[ -n $hint ]] && declare -F dot_doctor_hint >/dev/null 2>&1; then
    _dr_one_line "$detail"
    "_dr_$level" "$message" "$REPLY" || return
    dot_doctor_hint "$hint"
    return
  fi
  _dr_one_line "$detail${detail:+${hint:+; }}$hint"
  "_dr_$level" "$message" "$REPLY"
}

# Next step for a probe that could not create its temporary directory.
_DR_TMPDIR_HINT="check that the temporary directory (TMPDIR, else /tmp) exists, is writable, and has free space, then rerun 'dot doctor'"

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
# caller's. The watchdog takes whole or decimal seconds (0 disables the
# deadline, as for timeout(1)) and returns 125 without running the command
# when the deadline is malformed or its private directory and FIFO cannot
# be created.
#
# The watchdog runs the command as its own process group and signals the
# whole group (TERM at the deadline, then KILL two seconds later), as
# timeout(1) does: a grandchild left behind would keep a `$(...)` capture
# open past the deadline. Once the command itself has exited, by itself or
# by the deadline, its group is KILLed too, so a background child or a
# grandchild that ignores TERM can neither hold the capture nor outlive the
# call. A TERM, HUP, or INT that stops the caller KILLs the group as well.
#
# Nothing else may outlive the call either. On macOS, Dot's supervisor has
# no stable handle on a process outside the leader's process group, so when
# a doctor worker or test suite exits while such a process still lives, it
# refuses the teardown and fails the run. The watchdog therefore stays in
# the caller's group and runs builtins only: it waits with `read -t` on a
# private FIFO rather than an external sleep, which would be orphaned when
# the watchdog is stopped. Everything runs in a subshell, so job control,
# traps, and errexit changes stay inside.
_dr_run_bounded() {
  local secs=$1
  shift
  _dr_timeout_resolve
  if [[ -n $_DR_TIMEOUT_BIN ]]; then
    "$_DR_TIMEOUT_BIN" -k 2 "$secs" "$@"
    return
  fi
  # read -t would reject anything else at once, which the watchdog cannot
  # tell from a broken clock.
  [[ $secs =~ ^[0-9]+([.][0-9]+)?$ ]] || return 125
  (
    set +e
    pid='' wd='' clock=''
    # A private, unpredictable directory for the deadline marker and the
    # watchdog's clock: a FIFO nothing ever writes, so a read on it returns
    # only when its timeout passes. Opening it read-write never blocks and
    # never sees EOF. The clock takes a free descriptor, so none the caller
    # passes on (Dot hands its lease to children by number) is lost.
    marks=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-deadline.XXXXXX" 2>/dev/null) || exit 125
    if ! mkfifo "$marks/clock" 2>/dev/null || ! exec {clock}<>"$marks/clock"; then
      rm -rf "$marks"
      exit 125
    fi
    # The watchdog dies with the caller's group, and the command's group
    # never sees a signal sent there, so stop it here rather than leave it
    # running without a deadline. Signals ignored on entry (INT and QUIT in
    # a background job) cannot be trapped and need nothing.
    trap 'kill -KILL -- "-$pid" "$wd" 2>/dev/null; rm -rf "$marks"; exit 129' HUP
    trap 'kill -KILL -- "-$pid" "$wd" 2>/dev/null; rm -rf "$marks"; exit 130' INT
    trap 'kill -KILL -- "-$pid" "$wd" 2>/dev/null; rm -rf "$marks"; exit 143' TERM
    set -m
    # An async command's stdin is /dev/null unless redirected explicitly, even
    # under job control; keep the caller's, as documented above.
    "$@" {clock}>&- <&0 &
    pid=$!
    set +m
    # Started without job control, so it shares the caller's group. read
    # reports a passed timeout as a status above 128; anything else means
    # the clock broke, and the watchdog stands down rather than fire early.
    (
      read -r -t "$secs" -u "$clock"
      (($? > 128)) || exit 0
      : >"$marks/fired"
      kill -TERM -- "-$pid"
      read -r -t 2 -u "$clock"
      (($? > 128)) || exit 0
      kill -KILL -- "-$pid"
    ) </dev/null >/dev/null 2>&1 &
    wd=$!
    exec {clock}>&-
    wait "$pid"
    rc=$?
    # The command has exited and been reaped. Anything left in its group
    # keeps the group ID reserved, so this KILL reaches only those
    # leftovers; with none left there is no group to find (the same instant
    # of PID reuse the deadline's TERM has always had to accept).
    kill -KILL -- "-$pid" 2>/dev/null
    kill -KILL "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    [[ ! -e $marks/fired ]] || rc=124
    rm -rf "$marks"
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
