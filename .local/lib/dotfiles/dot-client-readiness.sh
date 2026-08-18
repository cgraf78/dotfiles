#!/usr/bin/env bash
# Publish the private proof that this host completed a preparation update.
# The symbolic topology generation invalidates an older proof without adding
# another standalone revision pin; the adapter still validates the runtime on
# every dispatch.

set -euo pipefail
CDPATH=
shopt -u nocasematch 2>/dev/null || true
umask 077

dot_client_ready_error() {
  if [[ ${DOT_QUIET:-0} == 1 || ${SHDEPS_QUIET:-0} == 1 ]]; then
    return 0
  fi
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

dot_client_ready_state_home() {
  local value=${XDG_STATE_HOME:-}

  case $value in
    /) DOT_CLIENT_READY_STATE_HOME=/ ;;
    /*)
      dot_client_ready_normalized_absolute "$value" || return 1
      DOT_CLIENT_READY_STATE_HOME=$value
      ;;
    *)
      DOT_CLIENT_READY_STATE_HOME=$HOME/.local/state
      dot_client_ready_normalized_absolute "$DOT_CLIENT_READY_STATE_HOME"
      ;;
  esac
}

dot_client_ready_config_path() {
  local value=${XDG_CONFIG_HOME:-}

  case $value in
    /) DOT_CLIENT_READY_CONFIG_PATH=/dot/config ;;
    /*)
      dot_client_ready_normalized_absolute "$value" || return 1
      DOT_CLIENT_READY_CONFIG_PATH=$value/dot/config
      ;;
    *)
      DOT_CLIENT_READY_CONFIG_PATH=$HOME/.config/dot/config
      dot_client_ready_normalized_absolute "$DOT_CLIENT_READY_CONFIG_PATH"
      ;;
  esac
}

dot_client_ready_resolve_checkout() {
  local install_home=${SHDEPS_INSTALL_DIR:-$HOME/.local/share}

  while [[ $install_home != / && $install_home == */ ]]; do
    install_home=${install_home%/}
  done
  case $install_home in
    '' | *//* | */./* | */. | */../* | */.. | *$'\n'* | *$'\r'*)
      return 1
      ;;
    /) DOT_CLIENT_READY_CHECKOUT=/cgraf78/dot ;;
    /*) DOT_CLIENT_READY_CHECKOUT=$install_home/cgraf78/dot ;;
    *) return 1 ;;
  esac
}

dot_client_ready_git() (
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_INDEX_FILE GIT_CONFIG
  unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
  exec "$DOT_CLIENT_READY_GIT" "$@"
)

dot_client_ready_exact_file() {
  local expected=$1 actual=$2

  dot_client_ready_git --no-pager diff --no-index --quiet --no-ext-diff \
    --no-textconv -- "$expected" "$actual"
}

dot_client_ready_exact_link() {
  local path=$1 expected=$2 actual

  [[ -L $path ]] || return 1
  actual=$(readlink "$path") || return 1
  [[ $actual == "$expected" ]]
}

dot_client_ready_stat() {
  local path=$1 output

  if output=$(stat -c '%u %a %h' "$path" 2>/dev/null); then
    :
  elif output=$(stat -f '%u %Lp %l' "$path" 2>/dev/null); then
    :
  else
    return 1
  fi
  DOT_CLIENT_READY_UID=${output%% *}
  output=${output#* }
  DOT_CLIENT_READY_MODE=${output%% *}
  DOT_CLIENT_READY_LINKS=${output#* }
}

dot_client_ready_private_file() {
  local path=$1

  [[ -f $path && ! -L $path ]] || return 1
  dot_client_ready_stat "$path" || return 1
  [[ $DOT_CLIENT_READY_UID == "$(id -u)" &&
  $DOT_CLIENT_READY_MODE == 600 && $DOT_CLIENT_READY_LINKS == 1 ]]
}

dot_client_ready_private_directory() {
  local path=$1

  [[ -d $path && ! -L $path ]] || return 1
  dot_client_ready_stat "$path" || return 1
  [[ $DOT_CLIENT_READY_UID == "$(id -u)" && $DOT_CLIENT_READY_MODE == 700 ]]
}

dot_client_ready_read_lock() {
  local LC_ALL=C
  local lock=$1 line count=0 header='' phase_line=''
  local revision_line='' generation_line=''

  [[ -f $lock && ! -L $lock ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    count=$((count + 1))
    case $count in
      1) header=$line ;;
      2) phase_line=$line ;;
      3) revision_line=$line ;;
      4) generation_line=$line ;;
      *) return 1 ;;
    esac
  done <"$lock"
  [[ $count -eq 4 && $header == 'cgraf78 dot client cutover v4' &&
    $phase_line == phase=* && $revision_line == minimum_revision=* &&
    $generation_line == readiness_generation=* ]] || return 1
  case ${phase_line#phase=} in
    prepare | active) ;;
    *) return 1 ;;
  esac
  DOT_CLIENT_READY_REVISION=${revision_line#minimum_revision=}
  [[ $DOT_CLIENT_READY_REVISION =~ ^[0-9a-f]{40}$ ]] || return 1
  DOT_CLIENT_READY_GENERATION=${generation_line#readiness_generation=}
  [[ $DOT_CLIENT_READY_GENERATION =~ ^[0-9a-z][0-9a-z-]{0,63}$ ]]
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
    # Older update-lock generations created the Dot-owned state directory with
    # the caller's default mode. Harden only that recognized user-owned path.
    chmod 0700 "$path" || return 1
  fi
  dot_client_ready_private_directory "$path"
}

dot_client_ready_validate_config() (
  local checkout=$1

  # Parse the installed client file with the reviewed standalone parser rather
  # than duplicating its grammar in this temporary fleet proof.
  # shellcheck source=/dev/null
  . "$checkout/lib/dot/public/xdg.sh"
  # shellcheck source=/dev/null
  . "$checkout/lib/dot/config.sh"
  dot_config_load "$DOT_CLIENT_READY_CONFIG_PATH" || return 1
  [[ $DOT_CONFIG_VERSION == 1 && $DOT_EXTENSION_API == 1 &&
    $DOT_EXTENSIONS_DIR == "$HOME/.local/lib/dotfiles" &&
    $DOT_DEPENDENCY_PROVIDER == shdeps ]]
)

dot_client_ready_validate_topology() {
  local lock=$1 checkout launcher runtime public_link public_source

  dot_client_ready_resolve_checkout || return 1
  checkout=$DOT_CLIENT_READY_CHECKOUT
  launcher=$HOME/.local/bin/dot
  runtime=$checkout/bin/dot
  public_link=$HOME/.local/lib/dot
  public_source=$checkout/lib/dot/public

  # Reuse the adapter's complete checkout-authority proof before sourcing or
  # executing any standalone bytes. This keeps one Git trust boundary for the
  # preparation writer and active dispatch instead of letting them drift.
  DOT_CLIENT_CUTOVER_LOCK=$lock \
    "$launcher" __client validate-checkout || return 1
  [[ -d $HOME/.local/lib/dotfiles && ! -L $HOME/.local/lib/dotfiles ]] ||
    return 1
  dot_client_ready_exact_link "$public_link" "$public_source" || return 1
  dot_client_ready_config_path || return 1
  dot_client_ready_validate_config "$checkout" || return 1
  DOT_CLIENT_READY_GIT=$(type -P git 2>/dev/null) || return 1
  dot_client_ready_normalized_absolute "$DOT_CLIENT_READY_GIT" || return 1
  [[ -f $DOT_CLIENT_READY_GIT && -x $DOT_CLIENT_READY_GIT ]] || return 1
  DOT_CLIENT_READY_CONFIG_OID=$(dot_client_ready_git -C "$checkout" hash-object \
    --no-filters -- "$DOT_CLIENT_READY_CONFIG_PATH" 2>/dev/null) || return 1
  [[ $DOT_CLIENT_READY_CONFIG_OID =~ ^[0-9a-f]{40}$ ]] || return 1
  "$runtime" --version >/dev/null 2>&1
}

dot_client_ready_publish_record() {
  local readiness=$1

  if [[ -e $readiness || -L $readiness ]]; then
    return 1
  fi
  # The parent is private, and noclobber makes the record itself the commit
  # point. An interrupted short write is not valid authority and is removed by
  # the next pre-mutation revoke.
  (
    set -C
    umask 077
    printf 'cgraf78 dot client readiness v4\nconfig_path=%s\nconfig_oid=%s\n' \
      "$DOT_CLIENT_READY_CONFIG_PATH" "$DOT_CLIENT_READY_CONFIG_OID" >"$readiness"
  ) || return 1
  dot_client_ready_private_file "$readiness"
}

dot_client_ready_write() {
  local lock dot_state readiness_root generation_root readiness

  [[ -n ${HOME:-} ]] || return 1
  lock=${DOT_CLIENT_CUTOVER_LOCK:-$HOME/.local/lib/dotfiles/dot-cutover.lock}
  dot_client_ready_normalized_absolute "$lock" || return 1
  dot_client_ready_state_home || return 1
  dot_client_ready_read_lock "$lock" || return 1
  dot_client_ready_validate_topology "$lock" || return 1

  mkdir -p "$DOT_CLIENT_READY_STATE_HOME" || return 1
  [[ -d $DOT_CLIENT_READY_STATE_HOME && ! -L $DOT_CLIENT_READY_STATE_HOME ]] ||
    return 1
  if [[ $DOT_CLIENT_READY_STATE_HOME == / ]]; then
    dot_state=/dot
  else
    dot_state=$DOT_CLIENT_READY_STATE_HOME/dot
  fi
  readiness_root=$dot_state/client-ready-v4
  generation_root=$readiness_root/$DOT_CLIENT_READY_GENERATION
  readiness=$generation_root/$DOT_CLIENT_READY_REVISION
  dot_client_ready_ensure_directory "$dot_state" || return 1
  dot_client_ready_ensure_directory "$readiness_root" || return 1
  dot_client_ready_ensure_directory "$generation_root" || return 1
  dot_client_ready_publish_record "$readiness"
}

dot_client_ready_revoke() {
  local lock dot_state readiness_root generation_root readiness

  [[ -n ${HOME:-} ]] || return 1
  lock=${DOT_CLIENT_CUTOVER_LOCK:-$HOME/.local/lib/dotfiles/dot-cutover.lock}
  dot_client_ready_normalized_absolute "$lock" || return 1
  dot_client_ready_state_home || return 1
  dot_client_ready_read_lock "$lock" || return 1
  if [[ $DOT_CLIENT_READY_STATE_HOME == / ]]; then
    dot_state=/dot
  else
    dot_state=$DOT_CLIENT_READY_STATE_HOME/dot
  fi
  readiness_root=$dot_state/client-ready-v4
  generation_root=$readiness_root/$DOT_CLIENT_READY_GENERATION
  readiness=$generation_root/$DOT_CLIENT_READY_REVISION
  if [[ ! -e $dot_state && ! -L $dot_state ]]; then
    return 0
  fi
  # The path is authority only inside the exact private directory chain the
  # writer created. Do not follow a substituted state parent to another tree.
  # The update lock may have created this recognized user-owned state root
  # with the caller's default mode before revocation runs. Apply the same
  # bounded hardening rule as the writer; deeper authority parents stay strict.
  dot_client_ready_ensure_directory "$dot_state" || return 1
  if [[ ! -e $readiness_root && ! -L $readiness_root ]]; then
    return 0
  fi
  dot_client_ready_private_directory "$readiness_root" || return 1
  if [[ ! -e $generation_root && ! -L $generation_root ]]; then
    return 0
  fi
  dot_client_ready_private_directory "$generation_root" || return 1
  if [[ ! -e $readiness && ! -L $readiness ]]; then
    return 0
  fi
  # Remove only the exact private v4 record. Unexpected type, mode, owner, or
  # link count stops the update before it can mutate under stale authority.
  dot_client_ready_private_file "$readiness" || return 1
  rm -f "$readiness"
}

case ${1:-} in
  write)
    [[ $# -eq 1 ]] || exit 2
    dot_client_ready_write || {
      dot_client_ready_error 'could not publish host preparation proof'
      exit 1
    }
    ;;
  revoke)
    [[ $# -eq 1 ]] || exit 2
    dot_client_ready_revoke || {
      dot_client_ready_error 'could not revoke host preparation proof'
      exit 1
    }
    ;;
  *)
    dot_client_ready_error 'usage: dot-client-readiness.sh write|revoke'
    exit 2
    ;;
esac
