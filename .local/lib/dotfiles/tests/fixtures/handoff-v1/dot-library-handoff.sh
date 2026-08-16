#!/usr/bin/env bash
# One-time, client-owned migration from the embedded ~/.local/lib/dot tree to
# the standalone public-library link. The record in XDG state is durable before
# the tree moves; filesystem shape is the recovery phase.

set -euo pipefail
CDPATH=
umask 077

dot_handoff_error() {
  printf 'dot library handoff: %s\n' "$*" >&2
}

dot_handoff_normalized_absolute() {
  case $1 in
    '' | / | */ | *//* | */./* | */. | */../* | */.. | *$'\n'* | *$'\r'*)
      return 1
      ;;
    /*) return 0 ;;
    *) return 1 ;;
  esac
}

dot_handoff_stat() {
  local path=$1 output

  if output=$(stat -c '%d:%i %u %a' "$path" 2>/dev/null); then
    :
  elif output=$(stat -f '%d:%i %u %Lp' "$path" 2>/dev/null); then
    :
  else
    return 1
  fi
  DOT_HANDOFF_STAT_IDENTITY=${output%% *}
  output=${output#* }
  DOT_HANDOFF_STAT_UID=${output%% *}
  DOT_HANDOFF_STAT_MODE=${output#* }
}

dot_handoff_private_file() {
  local path=$1

  [[ -f $path && ! -L $path ]] || return 1
  dot_handoff_stat "$path" || return 1
  [[ $DOT_HANDOFF_STAT_UID == "$(id -u)" && $DOT_HANDOFF_STAT_MODE == 600 ]]
}

dot_handoff_private_directory() {
  local path=$1

  [[ -d $path && ! -L $path ]] || return 1
  dot_handoff_stat "$path" || return 1
  [[ $DOT_HANDOFF_STAT_UID == "$(id -u)" && $DOT_HANDOFF_STAT_MODE == 700 ]]
}

dot_handoff_context() {
  local install_home state_home prefix

  [[ -n ${HOME:-} ]] || return 1
  install_home=${SHDEPS_INSTALL_DIR:-$HOME/.local/share}
  while [[ $install_home != / && $install_home == */ ]]; do
    install_home=${install_home%/}
  done
  case $install_home in
    /) DOT_HANDOFF_CHECKOUT=/cgraf78/dot ;;
    /*) DOT_HANDOFF_CHECKOUT=$install_home/cgraf78/dot ;;
    *) return 1 ;;
  esac
  state_home=${XDG_STATE_HOME:-$HOME/.local/state}
  prefix=${PREFIX:-$HOME/.local}
  DOT_HANDOFF_LIBRARY=$prefix/lib/dot
  DOT_HANDOFF_LIBRARY_PARENT=$prefix/lib
  DOT_HANDOFF_TARGET=$DOT_HANDOFF_CHECKOUT/lib/dot/public
  DOT_HANDOFF_BACKUP=$prefix/lib/.dot-library-handoff-v1
  DOT_HANDOFF_FORWARDER=$prefix/bin/dot
  DOT_HANDOFF_LOCK=${DOT_CLIENT_CUTOVER_LOCK:-$prefix/lib/dotfiles/dot-cutover.lock}
  DOT_HANDOFF_TREE_TOOL=${DOT_LIBRARY_TREE_TOOL:-${BASH_SOURCE[0]%/*}/dot-library-tree.py}
  DOT_HANDOFF_STATE=$state_home/dot/library-handoff-v1
  DOT_HANDOFF_CAPABILITY=$DOT_HANDOFF_STATE/capability
  DOT_HANDOFF_TRANSACTION=$DOT_HANDOFF_STATE/transaction

  local path
  for path in "$DOT_HANDOFF_CHECKOUT" "$DOT_HANDOFF_LIBRARY" \
    "$DOT_HANDOFF_LIBRARY_PARENT" "$DOT_HANDOFF_TARGET" "$DOT_HANDOFF_BACKUP" \
    "$DOT_HANDOFF_FORWARDER" "$DOT_HANDOFF_LOCK" "$DOT_HANDOFF_TREE_TOOL" \
    "$DOT_HANDOFF_STATE" "$DOT_HANDOFF_CAPABILITY" "$DOT_HANDOFF_TRANSACTION"; do
    dot_handoff_normalized_absolute "$path" || return 1
  done
}

dot_handoff_ensure_state() {
  mkdir -p "$DOT_HANDOFF_STATE" || return 1
  [[ -d $DOT_HANDOFF_STATE && ! -L $DOT_HANDOFF_STATE ]] || return 1
  chmod 0700 "$DOT_HANDOFF_STATE" || return 1
  dot_handoff_private_directory "$DOT_HANDOFF_STATE"
}

dot_handoff_atomic_write() {
  local destination=$1 content=$2 temporary

  temporary=$(mktemp "$DOT_HANDOFF_STATE/.${destination##*/}.tmp.XXXXXX") || return 1
  if ! chmod 0600 "$temporary" || ! printf '%s\n' "$content" >"$temporary"; then
    rm -f -- "$temporary"
    return 1
  fi
  mv -f -- "$temporary" "$destination" || {
    rm -f -- "$temporary"
    return 1
  }
  dot_handoff_private_file "$destination"
}

dot_handoff_sha256() {
  local path=$1 output

  if output=$(sha256sum "$path" 2>/dev/null); then
    REPLY=${output%% *}
  elif output=$(shasum -a 256 "$path" 2>/dev/null); then
    REPLY=${output%% *}
  else
    return 1
  fi
  [[ $REPLY =~ ^[0-9a-f]{64}$ ]]
}

dot_handoff_read_lock() {
  local line count=0 header='' revision_line=''

  [[ -f $DOT_HANDOFF_LOCK && ! -L $DOT_HANDOFF_LOCK ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    count=$((count + 1))
    case $count in
      1) header=$line ;;
      2) revision_line=$line ;;
      *) return 1 ;;
    esac
  done <"$DOT_HANDOFF_LOCK"
  [[ $count -eq 2 && $header == 'cgraf78 dot client cutover v1' &&
    $revision_line == minimum_revision=* ]] || return 1
  DOT_HANDOFF_MINIMUM_REVISION=${revision_line#minimum_revision=}
  [[ $DOT_HANDOFF_MINIMUM_REVISION =~ ^[0-9a-f]{40}$ ]]
}

dot_handoff_git() (
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  unset GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_INDEX_FILE GIT_CONFIG
  unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT
  exec "$DOT_HANDOFF_GIT" "$@"
)

dot_handoff_validate_static() {
  local checkout_physical top top_physical template

  dot_handoff_read_lock || return 1
  [[ -f $DOT_HANDOFF_FORWARDER && ! -L $DOT_HANDOFF_FORWARDER &&
    -x $DOT_HANDOFF_FORWARDER ]] || return 1
  template=$DOT_HANDOFF_CHECKOUT/support/client-launcher.sh
  [[ -f $template && ! -L $template ]] || return 1
  cmp -s "$DOT_HANDOFF_FORWARDER" "$template" || return 1
  [[ -d $DOT_HANDOFF_TARGET && ! -L $DOT_HANDOFF_TARGET ]] || return 1
  [[ -f $DOT_HANDOFF_TREE_TOOL && ! -L $DOT_HANDOFF_TREE_TOOL ]] || return 1
  DOT_HANDOFF_GIT=$(type -P git 2>/dev/null) || return 1
  dot_handoff_normalized_absolute "$DOT_HANDOFF_GIT" || return 1
  checkout_physical=$(cd -P -- "$DOT_HANDOFF_CHECKOUT" 2>/dev/null && pwd -P) ||
    return 1
  top=$(dot_handoff_git -C "$DOT_HANDOFF_CHECKOUT" rev-parse --show-toplevel 2>/dev/null) ||
    return 1
  top_physical=$(cd -P -- "$top" 2>/dev/null && pwd -P) || return 1
  [[ $top_physical == "$checkout_physical" ]] || return 1
  DOT_HANDOFF_REVISION=$(dot_handoff_git -C "$DOT_HANDOFF_CHECKOUT" \
    rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || return 1
  [[ $DOT_HANDOFF_REVISION =~ ^[0-9a-f]{40}$ &&
    $DOT_HANDOFF_REVISION == "$DOT_HANDOFF_MINIMUM_REVISION" ]] || return 1
  dot_handoff_sha256 "$DOT_HANDOFF_FORWARDER" || return 1
  DOT_HANDOFF_FORWARDER_SHA256=$REPLY
  dot_handoff_stat "$DOT_HANDOFF_LIBRARY_PARENT" || return 1
  DOT_HANDOFF_PARENT_IDENTITY=$DOT_HANDOFF_STAT_IDENTITY
}

dot_handoff_tree_identity() {
  local path=$1 output extra=''

  output=$(python3 "$DOT_HANDOFF_TREE_TOOL" "$path") || return 1
  IFS=$'\t' read -r DOT_HANDOFF_TREE_IDENTITY DOT_HANDOFF_TREE_DIGEST extra <<<"$output"
  [[ -z $extra && $DOT_HANDOFF_TREE_IDENTITY =~ ^[0-9]+:[0-9]+$ &&
    $DOT_HANDOFF_TREE_DIGEST =~ ^[0-9a-f]{64}$ ]]
}

dot_handoff_record_content() {
  local header=$1

  printf '%s\n' "$header"
  printf 'checkout=%s\n' "$DOT_HANDOFF_CHECKOUT"
  printf 'revision=%s\n' "$DOT_HANDOFF_REVISION"
  printf 'forwarder_sha256=%s\n' "$DOT_HANDOFF_FORWARDER_SHA256"
  printf 'library=%s\n' "$DOT_HANDOFF_LIBRARY"
  printf 'library_identity=%s\n' "$DOT_HANDOFF_TREE_IDENTITY"
  printf 'library_digest=%s\n' "$DOT_HANDOFF_TREE_DIGEST"
  printf 'library_parent_identity=%s\n' "$DOT_HANDOFF_PARENT_IDENTITY"
  printf 'target=%s\n' "$DOT_HANDOFF_TARGET"
  printf 'backup=%s\n' "$DOT_HANDOFF_BACKUP"
}

dot_handoff_read_record() {
  local path=$1 expected_header=$2 line count=0 key value
  local checkout='' revision='' forwarder='' library='' identity='' digest=''
  local parent_identity='' target='' backup=''

  dot_handoff_private_file "$path" || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    count=$((count + 1))
    if [[ $count -eq 1 ]]; then
      [[ $line == "$expected_header" ]] || return 1
      continue
    fi
    [[ $line == *=* ]] || return 1
    key=${line%%=*}
    value=${line#*=}
    case $key in
      checkout)
        [[ -z $checkout ]] || return 1
        checkout=$value
        ;;
      revision)
        [[ -z $revision ]] || return 1
        revision=$value
        ;;
      forwarder_sha256)
        [[ -z $forwarder ]] || return 1
        forwarder=$value
        ;;
      library)
        [[ -z $library ]] || return 1
        library=$value
        ;;
      library_identity)
        [[ -z $identity ]] || return 1
        identity=$value
        ;;
      library_digest)
        [[ -z $digest ]] || return 1
        digest=$value
        ;;
      library_parent_identity)
        [[ -z $parent_identity ]] || return 1
        parent_identity=$value
        ;;
      target)
        [[ -z $target ]] || return 1
        target=$value
        ;;
      backup)
        [[ -z $backup ]] || return 1
        backup=$value
        ;;
      *) return 1 ;;
    esac
  done <"$path"
  [[ $count -eq 10 && $checkout == "$DOT_HANDOFF_CHECKOUT" &&
    $library == "$DOT_HANDOFF_LIBRARY" && $target == "$DOT_HANDOFF_TARGET" &&
    $backup == "$DOT_HANDOFF_BACKUP" && $revision =~ ^[0-9a-f]{40}$ &&
    $forwarder =~ ^[0-9a-f]{64}$ && $identity =~ ^[0-9]+:[0-9]+$ &&
    $digest =~ ^[0-9a-f]{64}$ && $parent_identity =~ ^[0-9]+:[0-9]+$ ]] ||
    return 1
  DOT_HANDOFF_RECORD_REVISION=$revision
  DOT_HANDOFF_RECORD_FORWARDER_SHA256=$forwarder
  DOT_HANDOFF_RECORD_LIBRARY_IDENTITY=$identity
  DOT_HANDOFF_RECORD_LIBRARY_DIGEST=$digest
  DOT_HANDOFF_RECORD_PARENT_IDENTITY=$parent_identity
}

dot_handoff_exact_link() {
  local path=$1 target=$2
  [[ -L $path && $(readlink "$path") == "$target" ]]
}

dot_handoff_backup_safe() {
  local entry count=0

  dot_handoff_private_directory "$DOT_HANDOFF_BACKUP" || return 1
  for entry in "$DOT_HANDOFF_BACKUP"/* "$DOT_HANDOFF_BACKUP"/.[!.]* \
    "$DOT_HANDOFF_BACKUP"/..?*; do
    [[ -e $entry || -L $entry ]] || continue
    count=$((count + 1))
    case ${entry##*/} in
      previous | retired) ;;
      *) return 1 ;;
    esac
  done
  [[ $count -le 1 ]]
}

dot_handoff_remove_authority() {
  rm -f -- "$DOT_HANDOFF_TRANSACTION"
}

dot_handoff_failpoint() {
  if [[ ${DOT_LIBRARY_HANDOFF_FAILPOINT:-} == "pause-$1" ]]; then
    [[ -n ${DOT_LIBRARY_HANDOFF_PAUSE_MARKER:-} ]] || return 1
    : >"$DOT_LIBRARY_HANDOFF_PAUSE_MARKER" || return 1
    while :; do
      sleep 1
    done
  fi
  [[ ${DOT_LIBRARY_HANDOFF_FAILPOINT:-} != "$1" ]] || exit 97
}

dot_handoff_signal() {
  local status=$1

  trap - HUP INT TERM
  dot_handoff_restore >/dev/null 2>&1 || dot_handoff_recover >/dev/null 2>&1 || true
  exit "$status"
}

dot_handoff_prepare() {
  local content

  dot_handoff_context || {
    dot_handoff_error 'invalid migration paths'
    return 1
  }
  dot_handoff_ensure_state || return 1
  [[ ! -e $DOT_HANDOFF_TRANSACTION && ! -L $DOT_HANDOFF_TRANSACTION ]] ||
    dot_handoff_recover || return 1
  dot_handoff_validate_static || {
    dot_handoff_error 'standalone checkout or forwarder did not match the cutover lock'
    return 1
  }
  [[ -d $DOT_HANDOFF_LIBRARY && ! -L $DOT_HANDOFF_LIBRARY ]] || return 1
  dot_handoff_tree_identity "$DOT_HANDOFF_LIBRARY" || return 1
  content=$(dot_handoff_record_content 'cgraf78 dot library handoff capability v1') ||
    return 1
  if [[ -e $DOT_HANDOFF_CAPABILITY || -L $DOT_HANDOFF_CAPABILITY ]]; then
    dot_handoff_read_record "$DOT_HANDOFF_CAPABILITY" \
      'cgraf78 dot library handoff capability v1' || return 1
    [[ $DOT_HANDOFF_RECORD_REVISION == "$DOT_HANDOFF_REVISION" &&
      $DOT_HANDOFF_RECORD_FORWARDER_SHA256 == "$DOT_HANDOFF_FORWARDER_SHA256" &&
      $DOT_HANDOFF_RECORD_LIBRARY_IDENTITY == "$DOT_HANDOFF_TREE_IDENTITY" &&
      $DOT_HANDOFF_RECORD_LIBRARY_DIGEST == "$DOT_HANDOFF_TREE_DIGEST" &&
      $DOT_HANDOFF_RECORD_PARENT_IDENTITY == "$DOT_HANDOFF_PARENT_IDENTITY" ]]
    return
  fi
  dot_handoff_atomic_write "$DOT_HANDOFF_CAPABILITY" "$content"
}

dot_handoff_recover() {
  local previous retired

  dot_handoff_context || return 1
  if [[ ! -e $DOT_HANDOFF_TRANSACTION && ! -L $DOT_HANDOFF_TRANSACTION ]]; then
    [[ ! -e $DOT_HANDOFF_BACKUP && ! -L $DOT_HANDOFF_BACKUP ]]
    return
  fi
  dot_handoff_read_record "$DOT_HANDOFF_TRANSACTION" \
    'cgraf78 dot library handoff transaction v1' || return 1
  dot_handoff_stat "$DOT_HANDOFF_LIBRARY_PARENT" || return 1
  [[ $DOT_HANDOFF_STAT_IDENTITY == "$DOT_HANDOFF_RECORD_PARENT_IDENTITY" ]] ||
    return 1
  previous=$DOT_HANDOFF_BACKUP/previous
  retired=$DOT_HANDOFF_BACKUP/retired

  if [[ ! -e $DOT_HANDOFF_BACKUP && ! -L $DOT_HANDOFF_BACKUP ]]; then
    if [[ -d $DOT_HANDOFF_LIBRARY && ! -L $DOT_HANDOFF_LIBRARY ]]; then
      dot_handoff_tree_identity "$DOT_HANDOFF_LIBRARY" || return 1
      [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
        $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
        return 1
      dot_handoff_remove_authority
      return
    fi
    if dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET"; then
      dot_handoff_remove_authority
      return
    fi
    return 1
  fi

  dot_handoff_backup_safe || return 1
  if [[ ! -e $previous && ! -L $previous && ! -e $retired && ! -L $retired ]]; then
    [[ -d $DOT_HANDOFF_LIBRARY && ! -L $DOT_HANDOFF_LIBRARY ]] || return 1
    dot_handoff_tree_identity "$DOT_HANDOFF_LIBRARY" || return 1
    [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
      $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
      return 1
    rmdir "$DOT_HANDOFF_BACKUP" || return 1
    dot_handoff_remove_authority
    return
  fi

  if [[ -e $retired || -L $retired ]]; then
    [[ -d $retired && ! -L $retired ]] || return 1
    dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET" || return 1
    rm -rf -- "$retired" || return 1
    rmdir "$DOT_HANDOFF_BACKUP" || return 1
    dot_handoff_remove_authority
    return
  fi

  [[ -d $previous && ! -L $previous ]] || return 1
  dot_handoff_tree_identity "$previous" || return 1
  [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
    $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
    return 1
  if [[ ! -e $DOT_HANDOFF_LIBRARY && ! -L $DOT_HANDOFF_LIBRARY ]]; then
    mv -- "$previous" "$DOT_HANDOFF_LIBRARY" || return 1
    rmdir "$DOT_HANDOFF_BACKUP" || return 1
    dot_handoff_remove_authority
    return
  fi
  dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET"
}

dot_handoff_apply() {
  local content previous

  dot_handoff_context || return 1
  dot_handoff_ensure_state || return 1
  dot_handoff_recover || return 1
  if dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET"; then
    return 0
  fi
  dot_handoff_read_record "$DOT_HANDOFF_CAPABILITY" \
    'cgraf78 dot library handoff capability v1' || return 1
  dot_handoff_validate_static || return 1
  [[ $DOT_HANDOFF_RECORD_REVISION == "$DOT_HANDOFF_REVISION" &&
    $DOT_HANDOFF_RECORD_FORWARDER_SHA256 == "$DOT_HANDOFF_FORWARDER_SHA256" &&
    $DOT_HANDOFF_RECORD_PARENT_IDENTITY == "$DOT_HANDOFF_PARENT_IDENTITY" ]] ||
    return 1
  [[ -d $DOT_HANDOFF_LIBRARY && ! -L $DOT_HANDOFF_LIBRARY ]] || return 1
  dot_handoff_tree_identity "$DOT_HANDOFF_LIBRARY" || return 1
  [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
    $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
    return 1
  [[ ! -e $DOT_HANDOFF_BACKUP && ! -L $DOT_HANDOFF_BACKUP ]] || return 1

  content=$(dot_handoff_record_content 'cgraf78 dot library handoff transaction v1') ||
    return 1
  dot_handoff_atomic_write "$DOT_HANDOFF_TRANSACTION" "$content" || return 1
  trap 'dot_handoff_signal 129' HUP
  trap 'dot_handoff_signal 130' INT
  trap 'dot_handoff_signal 143' TERM
  dot_handoff_failpoint after-record
  mkdir "$DOT_HANDOFF_BACKUP" || return 1
  chmod 0700 "$DOT_HANDOFF_BACKUP" || return 1
  dot_handoff_failpoint after-backup-dir
  previous=$DOT_HANDOFF_BACKUP/previous
  mv -- "$DOT_HANDOFF_LIBRARY" "$previous" || return 1
  dot_handoff_failpoint after-move
  if ! python3 "$DOT_HANDOFF_TREE_TOOL" symlink \
    "$DOT_HANDOFF_TARGET" "$DOT_HANDOFF_LIBRARY"; then
    dot_handoff_recover || true
    return 1
  fi
  dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET" || return 1
  dot_handoff_failpoint after-link
  trap - HUP INT TERM
}

dot_handoff_restore() {
  local previous

  dot_handoff_context || return 1
  dot_handoff_recover || return 1
  [[ -e $DOT_HANDOFF_TRANSACTION || -L $DOT_HANDOFF_TRANSACTION ]] || return 0
  dot_handoff_read_record "$DOT_HANDOFF_TRANSACTION" \
    'cgraf78 dot library handoff transaction v1' || return 1
  previous=$DOT_HANDOFF_BACKUP/previous
  dot_handoff_backup_safe || return 1
  [[ -d $previous && ! -L $previous ]] || return 1
  dot_handoff_tree_identity "$previous" || return 1
  [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
    $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
    return 1
  dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET" || return 1
  rm -f -- "$DOT_HANDOFF_LIBRARY" || return 1
  mv -- "$previous" "$DOT_HANDOFF_LIBRARY" || return 1
  rmdir "$DOT_HANDOFF_BACKUP" || return 1
  dot_handoff_remove_authority
}

dot_handoff_retire() {
  local previous retired

  dot_handoff_context || return 1
  dot_handoff_recover || return 1
  [[ -e $DOT_HANDOFF_TRANSACTION || -L $DOT_HANDOFF_TRANSACTION ]] || return 0
  dot_handoff_read_record "$DOT_HANDOFF_TRANSACTION" \
    'cgraf78 dot library handoff transaction v1' || return 1
  previous=$DOT_HANDOFF_BACKUP/previous
  retired=$DOT_HANDOFF_BACKUP/retired
  dot_handoff_backup_safe || return 1
  dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET" || return 1
  [[ -d $previous && ! -L $previous && ! -e $retired && ! -L $retired ]] ||
    return 1
  dot_handoff_tree_identity "$previous" || return 1
  [[ $DOT_HANDOFF_TREE_IDENTITY == "$DOT_HANDOFF_RECORD_LIBRARY_IDENTITY" &&
    $DOT_HANDOFF_TREE_DIGEST == "$DOT_HANDOFF_RECORD_LIBRARY_DIGEST" ]] ||
    return 1
  mv -- "$previous" "$retired" || return 1
  dot_handoff_failpoint after-retired-move
  dot_handoff_recover
}

dot_handoff_status() {
  dot_handoff_context || return 1
  if [[ -e $DOT_HANDOFF_TRANSACTION || -L $DOT_HANDOFF_TRANSACTION ]]; then
    dot_handoff_read_record "$DOT_HANDOFF_TRANSACTION" \
      'cgraf78 dot library handoff transaction v1' || return 1
    if dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET"; then
      printf 'committed\n'
    else
      printf 'recoverable\n'
    fi
  elif [[ -e $DOT_HANDOFF_CAPABILITY || -L $DOT_HANDOFF_CAPABILITY ]]; then
    if dot_handoff_exact_link "$DOT_HANDOFF_LIBRARY" "$DOT_HANDOFF_TARGET"; then
      printf 'retired\n'
    else
      printf 'prepared\n'
    fi
  else
    printf 'unprepared\n'
  fi
}

case ${1:-} in
  prepare)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_prepare
    ;;
  apply)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_apply
    ;;
  recover)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_recover
    ;;
  restore)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_restore
    ;;
  retire)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_retire
    ;;
  status)
    [[ $# -eq 1 ]] || exit 2
    dot_handoff_status
    ;;
  *)
    dot_handoff_error 'usage: dot-library-handoff.sh prepare|apply|recover|restore|retire|status'
    exit 2
    ;;
esac
