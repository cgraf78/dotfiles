#!/usr/bin/env bash
# Publish the private proof that this host completed a preparation update.
# The revision-keyed directory is an atomic, monotonic generation: a later
# reviewed minimum creates a new path instead of replacing old authority.

set -euo pipefail
CDPATH=
umask 077

dot_client_ready_error() {
  printf 'dot client readiness: %s\n' "$*" >&2
}

dot_client_ready_normalized_absolute() {
  case $1 in
    '' | / | */ | *//* | */./* | */. | */../* | */.. | *$'\n'* | *$'\r'*)
      return 1
      ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

dot_client_ready_stat() {
  local path=$1 output

  if output=$(stat -c '%u %a' "$path" 2>/dev/null); then
    :
  elif output=$(stat -f '%u %Lp' "$path" 2>/dev/null); then
    :
  else
    return 1
  fi
  DOT_CLIENT_READY_UID=${output%% *}
  DOT_CLIENT_READY_MODE=${output#* }
}

dot_client_ready_private_directory() {
  local path=$1

  [[ -d $path && ! -L $path ]] || return 1
  dot_client_ready_stat "$path" || return 1
  [[ $DOT_CLIENT_READY_UID == "$(id -u)" && $DOT_CLIENT_READY_MODE == 700 ]]
}

dot_client_ready_read_lock() {
  local lock=$1 line count=0 header='' phase_line='' revision_line=''

  [[ -f $lock && ! -L $lock ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    count=$((count + 1))
    case $count in
      1) header=$line ;;
      2) phase_line=$line ;;
      3) revision_line=$line ;;
      *) return 1 ;;
    esac
  done <"$lock"
  [[ $count -eq 3 && $header == 'cgraf78 dot client cutover v2' &&
    $phase_line == phase=* && $revision_line == minimum_revision=* ]] || return 1
  case ${phase_line#phase=} in
    prepare | active) ;;
    *) return 1 ;;
  esac
  DOT_CLIENT_READY_REVISION=${revision_line#minimum_revision=}
  [[ $DOT_CLIENT_READY_REVISION =~ ^[0-9a-f]{40}$ ]]
}

dot_client_ready_ensure_directory() {
  local path=$1

  if [[ ! -e $path && ! -L $path ]]; then
    mkdir -m 0700 "$path" || return 1
  fi
  [[ -d $path && ! -L $path ]] || return 1
  dot_client_ready_stat "$path" || return 1
  [[ $DOT_CLIENT_READY_UID == "$(id -u)" ]] || return 1
  if [[ $DOT_CLIENT_READY_MODE != 700 ]]; then
    # Older update-lock versions created the Dot-owned state directory with
    # the caller's default mode. Harden that recognized user-owned directory
    # before placing activation authority beneath it.
    chmod 0700 "$path" || return 1
  fi
  dot_client_ready_private_directory "$path"
}

dot_client_ready_write() {
  local state_home lock dot_state readiness_root readiness

  [[ -n ${HOME:-} ]] || return 1
  state_home=${XDG_STATE_HOME:-$HOME/.local/state}
  lock=${DOT_CLIENT_CUTOVER_LOCK:-$HOME/.local/lib/dotfiles/dot-cutover.lock}
  dot_client_ready_normalized_absolute "$state_home" || return 1
  dot_client_ready_normalized_absolute "$lock" || return 1
  dot_client_ready_read_lock "$lock" || return 1

  mkdir -p "$state_home" || return 1
  [[ -d $state_home && ! -L $state_home ]] || return 1
  dot_state=$state_home/dot
  readiness_root=$dot_state/client-ready-v2
  readiness=$readiness_root/$DOT_CLIENT_READY_REVISION
  dot_client_ready_ensure_directory "$dot_state" || return 1
  dot_client_ready_ensure_directory "$readiness_root" || return 1
  dot_client_ready_ensure_directory "$readiness"
}

case ${1:-} in
  write)
    [[ $# -eq 1 ]] || exit 2
    dot_client_ready_write || {
      dot_client_ready_error 'could not publish host preparation proof'
      exit 1
    }
    ;;
  *)
    dot_client_ready_error 'usage: dot-client-readiness.sh write'
    exit 2
    ;;
esac
