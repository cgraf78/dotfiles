# shellcheck shell=bash
# worktree-gc.sh — multi-repo worktree garbage collection.
#
# Library for the `dot-worktree-gc` entry point. Nothing here runs on
# source except loading the doctor enumeration helpers; the entry point
# calls `worktree_gc_main "$@"`. Written for `set -u` with no `-e`;
# every fallible step handles its own failure explicitly.
#
# Intended future home: `dot worktree gc` (dot refactor item #9). The
# seams that make the move cheap are this single file (no dot-engine
# coupling: explicit argv/env inputs only), the stdout contract below,
# and one function per phase so the native command can absorb them
# piecemeal. External dependencies resolve through env-overridable
# paths: the doctor enumerator sits beside this file, the git-tools
# merge predicate defaults to its Shdeps install path.
#
# Stdout contract (tab-separated, one record per line, stable):
#   would-remove\t<path>\t<reason>        dry run (the default)
#   would-remove-branch\t<branch>\t<git-dir>
#   would-skip-branch\t<branch>\t<reason>
#   removed\t<path>\t<reason>             --apply
#   removed-branch\t<branch>\t<git-dir>
#   skipped-branch\t<branch>\t<reason>
#   kept\t<path>\t<reason>
#   skipped\t<path>\t<reason>
#   failed\t<path>\t<reason>
#   failed-branch\t<branch>\t<reason>
# Diagnostics and the final tally go to stderr; stdout carries records
# only. Exit 0: clean sweep; 1: usage or environment error; 2: a
# removal or branch deletion failed.
#
# Safety rules (all enforced, none optional):
# - never `rm -rf` and never `git worktree remove --force`
# - never touch the live $HOME checkout, any main checkout, a locked
#   worktree, a dirty worktree, or a checkout git cannot inspect
# - checkout removal and branch deletion use split gates. Removing a
#   checkout is recoverable (commits and the branch ref survive), so a
#   gone upstream, an ancestry proof, or a content proof each suffice.
#   Deleting the branch is destructive, so it additionally requires a
#   merge proof (ancestry or content, never gone-alone), a base ref
#   freshly fetched this run, a non-base branch name, no concurrent
#   checkout, and a ref that still holds the proven OID.
# - a fetch failure degrades checkout proof to local refs with a
#   stderr notice and always keeps the branch; the sweep never fails
#   just because the network is down. A successful fetch moves
#   remote-tracking refs, like any fetch.
# - merge proof degrades to ancestry plus upstream-gone when the
#   git-tools predicate library is unavailable, with a stderr notice
#
# Known limitations (documented, not fixed):
# - ignored files (.env, local databases) are invisible to the clean
#   gate and to git's own removal check; back them up first
# - age uses find -mtime on the checkout top directory: `-mtime +N`
#   matches N+1 days and older, and committing inside does not refresh
#   the top directory's mtime (both err toward keeping)

_WORKTREE_GC_AGE_DAYS_DEFAULT=14
_WORKTREE_GC_REMOTE=origin

_WORKTREE_GC_DIR=${BASH_SOURCE[0]%/*}
if [[ -z ${_DR_WORKTREE_WARN_BYTES_DEFAULT:-} ]]; then
  # shellcheck source=doctor.d/lib/worktrees.sh
  . "$_WORKTREE_GC_DIR/doctor.d/lib/worktrees.sh" || return 1
fi

# --- shared sweep state (initialized by worktree_gc_main) ---
_WORKTREE_GC_AGE=$_WORKTREE_GC_AGE_DAYS_DEFAULT
_WORKTREE_GC_APPLY=0
_WORKTREE_GC_NO_FETCH=0
_WORKTREE_GC_HAVE_PRED=0
_WORKTREE_GC_FETCHED=$'\n'
_WORKTREE_GC_FRESH=$'\n'
_WORKTREE_GC_TOUCHED=$'\n'
# Per-repo caches, keyed by common git dir. A sweep fans out to dozens of
# checkouts per repo, so one `worktree list` fetch, one phys→registered
# index, and one base-ref resolution serve the whole repo instead of
# paying per checkout. Parallel indexed arrays (no associative arrays)
# keep the file on its existing shell requirements. Populated in the
# main shell only; subshell captures must treat them as read-only.
_WORKTREE_GC_LIST_COMMONS=()
_WORKTREE_GC_LIST_TEXTS=()
_WORKTREE_GC_LIST_MAINS=()
_WORKTREE_GC_MAP_COMMON=()
_WORKTREE_GC_MAP_PHYS=()
_WORKTREE_GC_MAP_REG=()
_WORKTREE_GC_BASE_COMMONS=()
_WORKTREE_GC_BASE_REFS=()
_WORKTREE_GC_N_REMOVED=0
_WORKTREE_GC_N_BRANCHES=0
_WORKTREE_GC_N_BRANCHES_KEPT=0
_WORKTREE_GC_N_KEPT=0
_WORKTREE_GC_N_SKIPPED=0
_WORKTREE_GC_N_FAILED=0

_worktree_gc_err() { printf 'dot-worktree-gc: %s\n' "$*" >&2; }

_worktree_gc_usage() {
  cat >&2 <<'USAGE'
usage: dot-worktree-gc [--older-than Nd] [--dry-run|--apply] [--no-fetch]
                       [--root DIR]...
  Remove worktrees older than Nd days (default 14d) whose branches are
  proven merged, across every repo that owns a discovered checkout.
  Dry run is the default; --apply performs removals. --root adds a
  worktree root to the sweep and may repeat. --no-fetch proves against
  local refs without touching the network.
  Records print on stdout; diagnostics and the tally go to stderr.
USAGE
}

# Print the day count for an age argument (N or Nd), or fail.
_worktree_gc_parse_age() {
  local raw=${1:-} num
  case $raw in
    *d) num=${raw%d} ;;
    *) num=$raw ;;
  esac
  case $num in
    '' | *[!0-9]* | 0) return 1 ;;
  esac
  printf '%s\n' "$num"
}

# Print one stdout record and tally it. Branch records share the shape
# but tally separately from their worktree.
_worktree_gc_record() {
  local verb=$1 path=$2
  shift 2 || return 1
  printf '%s\t%s\t%s\n' "$verb" "$path" "$*"
  case $verb in
    would-remove | removed)
      _WORKTREE_GC_N_REMOVED=$((_WORKTREE_GC_N_REMOVED + 1))
      ;;
    would-remove-branch | removed-branch)
      _WORKTREE_GC_N_BRANCHES=$((_WORKTREE_GC_N_BRANCHES + 1))
      ;;
    would-skip-branch | skipped-branch)
      _WORKTREE_GC_N_BRANCHES_KEPT=$((_WORKTREE_GC_N_BRANCHES_KEPT + 1))
      ;;
    kept) _WORKTREE_GC_N_KEPT=$((_WORKTREE_GC_N_KEPT + 1)) ;;
    skipped) _WORKTREE_GC_N_SKIPPED=$((_WORKTREE_GC_N_SKIPPED + 1)) ;;
    failed | failed-branch)
      _WORKTREE_GC_N_FAILED=$((_WORKTREE_GC_N_FAILED + 1))
      ;;
  esac
}

# Print sorted unique candidates with the live checkout excluded.
# Extra roots pass through to the shared enumerator. Never fails.
_worktree_gc_candidates() {
  local home=${HOME:-} home_phys dotfiles_phys dir
  home_phys=$(_dr_worktree_physical "$home") || home_phys=$home
  dotfiles_phys=
  if [[ -n ${DOTFILES:-} && -d ${DOTFILES:-} ]]; then
    dotfiles_phys=$(_dr_worktree_physical "$DOTFILES") || dotfiles_phys=
  fi
  _dr_worktree_candidates "$@" | LC_ALL=C sort -u |
    while IFS= read -r dir || [[ -n $dir ]]; do
      [[ -n $dir && -d $dir ]] || continue
      [[ $dir == "$home_phys" ]] && continue
      if [[ -n $dotfiles_phys && $dir == "$dotfiles_phys" ]]; then
        continue
      fi
      printf '%s\n' "$dir"
    done
}

# Print the absolute common git dir for a checkout, or fail.
_worktree_gc_common_dir() {
  local dir=$1 common
  common=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -n $common ]] || return 1
  case $common in
    /*) printf '%s\n' "$common" ;;
    *) (cd -- "$dir/$common" 2>/dev/null && pwd -P 2>/dev/null) || return 1 ;;
  esac
}

# Print the absolute git dir (not the common dir) for a checkout, or
# fail. A main checkout's git dir IS the common dir; a linked
# checkout's points into the common worktrees area.
_worktree_gc_git_dir() {
  local dir=$1 gitdir
  gitdir=$(git -C "$dir" rev-parse --git-dir 2>/dev/null) || return 1
  [[ -n $gitdir ]] || return 1
  case $gitdir in
    /*) printf '%s\n' "$gitdir" ;;
    *) (cd -- "$dir/$gitdir" 2>/dev/null && pwd -P 2>/dev/null) || return 1 ;;
  esac
}

# Index one repo's porcelain worktree list into the per-repo caches:
# the raw list text (for the locked-entry scan), the main checkout's
# physical path (for the main-checkout gate), and one phys→registered
# record per resolvable entry. Resolving each entry once here replaces
# the per-checkout linear scan that forked a subshell per list entry.
# Must run in the main shell; callers under $() would discard the index.
_worktree_gc_index_wt_list() {
  local common=$1 wt_list=$2 line path phys main_path='' main_phys=''
  local first=1
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      'worktree '*) path=${line#worktree } ;;
      *) continue ;;
    esac
    if ((first == 1)); then
      first=0
      main_path=$path
    fi
    phys=$(_dr_worktree_physical "$path") || continue
    [[ -n $phys ]] || continue
    _WORKTREE_GC_MAP_COMMON+=("$common")
    _WORKTREE_GC_MAP_PHYS+=("$phys")
    _WORKTREE_GC_MAP_REG+=("$path")
  done <<<"$wt_list"
  if [[ -n $main_path ]]; then
    main_phys=$(_dr_worktree_physical "$main_path") || main_phys=
  fi
  _WORKTREE_GC_LIST_COMMONS+=("$common")
  _WORKTREE_GC_LIST_TEXTS+=("$wt_list")
  _WORKTREE_GC_LIST_MAINS+=("$main_phys")
}

# Ensure one repo's worktree list is cached and print it via REPLY, or
# fail. A failed fetch is never cached, so the next checkout retries
# exactly as an uncached sweep would. Must run in the main shell.
_worktree_gc_ensure_repo() {
  local common=$1 i wt_list
  REPLY=
  for ((i = 0; i < ${#_WORKTREE_GC_LIST_COMMONS[@]}; i++)); do
    if [[ ${_WORKTREE_GC_LIST_COMMONS[$i]} == "$common" ]]; then
      REPLY=${_WORKTREE_GC_LIST_TEXTS[$i]}
      return 0
    fi
  done
  wt_list=$(git --git-dir="$common" worktree list --porcelain 2>/dev/null) || return 1
  _worktree_gc_index_wt_list "$common" "$wt_list"
  REPLY=$wt_list
  return 0
}

# Drop one repo's cached list, index, and main path after a removal
# attempt so the next checkout in that repo proves against a fresh list,
# exactly as an uncached sweep would. The base ref survives: worktree
# removal touches no refs. Must run in the main shell.
_worktree_gc_drop_repo_cache() {
  local common=$1 i
  local -a keep_commons=() keep_texts=() keep_mains=()
  local -a keep_map_common=() keep_map_phys=() keep_map_reg=()
  for ((i = 0; i < ${#_WORKTREE_GC_LIST_COMMONS[@]}; i++)); do
    [[ ${_WORKTREE_GC_LIST_COMMONS[$i]} == "$common" ]] && continue
    keep_commons+=("${_WORKTREE_GC_LIST_COMMONS[$i]}")
    keep_texts+=("${_WORKTREE_GC_LIST_TEXTS[$i]}")
    keep_mains+=("${_WORKTREE_GC_LIST_MAINS[$i]}")
  done
  for ((i = 0; i < ${#_WORKTREE_GC_MAP_COMMON[@]}; i++)); do
    [[ ${_WORKTREE_GC_MAP_COMMON[$i]} == "$common" ]] && continue
    keep_map_common+=("${_WORKTREE_GC_MAP_COMMON[$i]}")
    keep_map_phys+=("${_WORKTREE_GC_MAP_PHYS[$i]}")
    keep_map_reg+=("${_WORKTREE_GC_MAP_REG[$i]}")
  done
  _WORKTREE_GC_LIST_COMMONS=("${keep_commons[@]+"${keep_commons[@]}"}")
  _WORKTREE_GC_LIST_TEXTS=("${keep_texts[@]+"${keep_texts[@]}"}")
  _WORKTREE_GC_LIST_MAINS=("${keep_mains[@]+"${keep_mains[@]}"}")
  _WORKTREE_GC_MAP_COMMON=("${keep_map_common[@]+"${keep_map_common[@]}"}")
  _WORKTREE_GC_MAP_PHYS=("${keep_map_phys[@]+"${keep_map_phys[@]}"}")
  _WORKTREE_GC_MAP_REG=("${keep_map_reg[@]+"${keep_map_reg[@]}"}")
}

# Print the registered spelling of a candidate worktree path from the
# repo index, or fail when it is not registered. Pure list read, safe
# under $(). Never trust that the enumerated spelling matches the admin
# copy: lookup compares physical paths, first list entry wins.
_worktree_gc_cached_registered() {
  local common=$1 dir=$2 j
  for ((j = 0; j < ${#_WORKTREE_GC_MAP_COMMON[@]}; j++)); do
    [[ ${_WORKTREE_GC_MAP_COMMON[$j]} == "$common" ]] || continue
    if [[ ${_WORKTREE_GC_MAP_PHYS[$j]} == "$dir" ]]; then
      printf '%s\n' "${_WORKTREE_GC_MAP_REG[$j]}"
      return 0
    fi
  done
  return 1
}

# Print a repo's cached main-checkout physical path (possibly empty).
# Pure cache read, safe under $().
_worktree_gc_cached_main() {
  local common=$1 i
  for ((i = 0; i < ${#_WORKTREE_GC_LIST_COMMONS[@]}; i++)); do
    if [[ ${_WORKTREE_GC_LIST_COMMONS[$i]} == "$common" ]]; then
      printf '%s\n' "${_WORKTREE_GC_LIST_MAINS[$i]}"
      return 0
    fi
  done
  return 1
}

# Print the local base ref (short remote form, e.g. origin/main) for the
# repo owning a checkout, without touching the network, or fail.
# Prefers the origin HEAD symref, then the conventional origin branch
# names. A non-origin remote HEAD counts only when it is the sole
# remote: with several remotes a fork's feature branch must never win
# by enumeration order. Every candidate must resolve to a commit;
# stale symrefs fall through instead of failing closed wrong.
_worktree_gc_local_base_ref() {
  local dir=$1 ref head_info default_ref candidate
  local -a remotes=()
  ref=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=
  if [[ $ref == */* ]] &&
    git -C "$dir" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$ref"
    return 0
  fi
  mapfile -t remotes < <(git -C "$dir" remote 2>/dev/null)
  if ((${#remotes[@]} == 1)); then
    head_info=$(git -C "$dir" for-each-ref --format='%(symref)' 'refs/remotes/*/HEAD' 2>/dev/null) || head_info=
    default_ref=${head_info%%$'\n'*}
    case $default_ref in
      refs/remotes/*)
        default_ref=${default_ref#refs/remotes/}
        if git -C "$dir" rev-parse --verify -q "$default_ref^{commit}" >/dev/null 2>&1; then
          printf '%s\n' "$default_ref"
          return 0
        fi
        ;;
    esac
  fi
  for candidate in main master trunk; do
    if git -C "$dir" rev-parse --verify -q "origin/$candidate^{commit}" >/dev/null 2>&1; then
      printf 'origin/%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Print the cached local base ref for one repo, resolving once per sweep.
# Remote-tracking refs are repo-level state shared by every checkout, so
# one resolution serves them all; a fetch moves ref targets but never
# renames the base, and the per-checkout OID read stays fresh. Failures
# cache too: with no fetch scheduled for the repo, nothing later in the
# run can grow a base ref. Populates only in the main shell; proof runs
# under $() and relies on the hoist in `_worktree_gc_process`.
_worktree_gc_base_ref_cached() {
  local dir=$1 common=$2 i ref
  for ((i = 0; i < ${#_WORKTREE_GC_BASE_COMMONS[@]}; i++)); do
    [[ ${_WORKTREE_GC_BASE_COMMONS[$i]} == "$common" ]] || continue
    ref=${_WORKTREE_GC_BASE_REFS[$i]}
    if [[ -n $ref ]]; then
      printf '%s\n' "$ref"
      return 0
    fi
    return 1
  done
  if ref=$(_worktree_gc_local_base_ref "$dir"); then
    _WORKTREE_GC_BASE_COMMONS+=("$common")
    _WORKTREE_GC_BASE_REFS+=("$ref")
    printf '%s\n' "$ref"
    return 0
  fi
  _WORKTREE_GC_BASE_COMMONS+=("$common")
  _WORKTREE_GC_BASE_REFS+=("")
  return 1
}

# Fetch the base branch for one repo, at most once per sweep. Never
# fails the sweep: a fetch failure degrades to local refs with a
# notice. Proving against stale refs only withholds proof (fewer
# removals), never fabricates it.
_worktree_gc_fetch_base() {
  local dir=$1 common=$2
  local ref remote branch err
  ((_WORKTREE_GC_NO_FETCH == 1)) && return 0
  case $'\n'"$_WORKTREE_GC_FETCHED"$'\n' in
    *$'\n'"$common"$'\n'*) return 0 ;;
  esac
  _WORKTREE_GC_FETCHED+="$common"$'\n'
  ref=$(_worktree_gc_base_ref_cached "$dir" "$common") || return 0
  remote=${ref%%/*}
  branch=${ref#*/}
  [[ -n $remote && -n $branch && $branch != "$ref" ]] || return 0
  if err=$(git --git-dir="$common" fetch --quiet --no-tags "$remote" "$branch" 2>&1); then
    _WORKTREE_GC_FRESH+="$common"$'\n'
    return 0
  fi
  err=${err%%$'\n'*}
  [[ -n $err ]] || err="fetch failed"
  _worktree_gc_err "$common: cannot fetch $ref ($err); using local refs"
  return 0
}

# Fetch-then-resolve split: `_worktree_gc_fetch_base` and
# `_worktree_gc_base_ref_cached` mutate the fetch and base caches and
# must run in the main shell, while `_worktree_gc_local_base_ref` is
# pure and safe to capture. Calling the mutators through $() would
# silently discard the cache writes. The hoist lives in
# `_worktree_gc_process`, ahead of the `$()` capture; the inner calls
# inside prove stay as no-ops for direct callers.

# A branch name counts as a base branch when it matches the resolved
# base's short name or the conventional set. Base branches are never
# deleted: a synced main checkout is disposable, its ref is not.
_worktree_gc_is_base_branch() {
  local branch=$1 base_ref=$2
  case $branch in
    main | master | trunk) return 0 ;;
  esac
  [[ -n $base_ref && $branch == "${base_ref#*/}" ]]
}

# Prove whether an old checkout is safe to remove. Prints one tab-led
# verdict line and always returns 0 so callers parse output, not status:
#   eligible\t<reason>\t<branch-oid-or-empty>\t<branch-action>
#   skip\t<reason>
# The branch action is `delete`, `none` (detached), or
# `keep:<reason>`. Checkout removal and branch deletion use split
# gates: a gone upstream, an ancestry proof, or a content proof each
# suffice for the recoverable checkout, while the destructive branch
# deletion additionally requires a merge proof, a base freshly fetched
# this run, and a non-base name. Proofs run against the single
# branch-tip read so a commit landing mid-proof cannot shift the
# target between the merge check and the deletion recheck.
_worktree_gc_prove() {
  local dir=$1 common=$2 branch=$3
  local head_oid proof_oid target upstream_info upstream_short upstream_track
  local base_ref base_oid gone=0 ancestor=0 content=0 fresh=0
  head_oid=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || {
    printf 'skip\tbroken git pointer\n'
    return 0
  }
  proof_oid=
  target=$head_oid
  if [[ -n $branch ]]; then
    proof_oid=$(git -C "$dir" rev-parse --verify -q "refs/heads/$branch^{commit}" 2>/dev/null) || {
      printf 'skip\tbroken git pointer\n'
      return 0
    }
    target=$proof_oid
    upstream_info=$(git -C "$dir" for-each-ref --format='%(upstream:short)%09%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || upstream_info=
    IFS=$'\t' read -r upstream_short upstream_track <<<"$upstream_info"
    if [[ $upstream_track == '[gone]' ]]; then
      gone=1
    fi
  fi
  _worktree_gc_fetch_base "$dir" "$common"
  if base_ref=$(_worktree_gc_base_ref_cached "$dir" "$common") &&
    base_oid=$(git -C "$dir" rev-parse --verify -q "$base_ref^{commit}" 2>/dev/null); then
    if git -C "$dir" merge-base --is-ancestor "$target" "$base_oid" 2>/dev/null; then
      ancestor=1
    elif ((_WORKTREE_GC_HAVE_PRED == 1)) &&
      (cd -- "$dir" 2>/dev/null && _gt_branch_content_merged_oids "$target" "$base_oid" >/dev/null); then
      content=1
    fi
  else
    base_ref=
  fi
  case $'\n'"$_WORKTREE_GC_FRESH"$'\n' in
    *$'\n'"$common"$'\n'*) fresh=1 ;;
  esac

  local reason=
  if ((gone == 1)); then
    reason="upstream ${upstream_short:-$branch} is gone"
  elif ((ancestor == 1)); then
    reason="merged into $base_ref"
  elif ((content == 1)); then
    reason="content-merged into $base_ref"
  elif [[ -z $base_ref ]]; then
    printf 'skip\tno remote base branch\n'
    return 0
  elif [[ -n $branch ]]; then
    printf 'skip\tunmerged branch %s\n' "$branch"
    return 0
  else
    printf 'skip\tdetached HEAD, unmerged\n'
    return 0
  fi

  local action=none
  if [[ -n $branch ]]; then
    if _worktree_gc_is_base_branch "$branch" "$base_ref"; then
      action='keep:base branch'
    elif ((ancestor == 1 || content == 1)); then
      if ((fresh == 1)); then
        action=delete
      else
        action='keep:base not fetched'
      fi
    else
      action='keep:merge unproven'
    fi
  fi
  printf 'eligible\t%s\t%s\t%s\n' "$reason" "$proof_oid" "$action"
  return 0
}

# Delete a local branch only when its ref still holds the proven OID
# and no checkout currently holds it. The expected-OID comparison is
# the recheck: a branch that moved since proof (new commits,
# concurrent gc) is refused, never force-deleted. The linkage recheck
# closes the remove-then-delete window against a concurrent checkout.
worktree_gc_delete_branch() {
  local common=$1 branch=$2 expected=$3 wt_list
  [[ -n $common && -n $branch && -n $expected ]] || return 1
  [[ -d $common ]] || return 1
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || return 1
  case $expected in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  wt_list=$(git --git-dir="$common" worktree list --porcelain 2>/dev/null) || return 1
  if grep -qxF "branch refs/heads/$branch" <<<"$wt_list"; then
    return 1
  fi
  git --git-dir="$common" update-ref -d "refs/heads/$branch" "$expected" >/dev/null 2>&1
}

# Record the removal of one eligible checkout: print the dry-run intent
# or perform it. A removal that cannot unlink its top directory (parent
# not writable) fails fast before git partially empties the checkout.
# The branch action comes from proof: `delete` removes the branch only
# after its checkout is gone and only at the proven OID;
# `keep:<reason>` and `none` (detached) record the keep without
# touching the ref. A failed checkout removal deletes nothing, and a
# failed branch deletion names the orphaned branch on stderr so the
# operator can finish it by hand.
_worktree_gc_remove() {
  local dir=$1 registered=$2 common=$3 branch=$4 reason=$5 proof_oid=$6 action=$7
  local err keep_reason remove_status
  if ((_WORKTREE_GC_APPLY == 0)); then
    _worktree_gc_record would-remove "$dir" "$reason"
    case $action in
      delete) _worktree_gc_record would-remove-branch "$branch" "$common" ;;
      keep:*)
        keep_reason=${action#keep:}
        _worktree_gc_record would-skip-branch "$branch" "$keep_reason"
        ;;
    esac
    return 0
  fi
  local parent=${registered%/*}
  if [[ ! -w $parent ]]; then
    _worktree_gc_record failed "$dir" "parent directory not writable"
    return 0
  fi
  err=$(git --git-dir="$common" worktree remove "$registered" 2>&1)
  remove_status=$?
  # The repo's list changed shape (or may have, on failure), so later
  # checkouts refetch instead of proving against the stale index.
  _worktree_gc_drop_repo_cache "$common"
  if ((remove_status == 0)); then
    _worktree_gc_record removed "$dir" "$reason"
    case $'\n'"$_WORKTREE_GC_TOUCHED"$'\n' in
      *$'\n'"$common"$'\n'*) ;;
      *) _WORKTREE_GC_TOUCHED+="$common"$'\n' ;;
    esac
    case $action in
      delete)
        if worktree_gc_delete_branch "$common" "$branch" "$proof_oid" 2>/dev/null; then
          _worktree_gc_record removed-branch "$branch" "$common"
        else
          _worktree_gc_record failed-branch "$branch" "branch changed since proof"
          _worktree_gc_err "branch $branch left without a checkout in $common; delete it manually once its merge is confirmed"
        fi
        ;;
      keep:*)
        keep_reason=${action#keep:}
        _worktree_gc_record skipped-branch "$branch" "$keep_reason"
        ;;
    esac
  else
    err=${err%%$'\n'*}
    [[ -n $err ]] || err="git worktree remove failed"
    _worktree_gc_record failed "$dir" "$err"
  fi
}

# Run the gate sequence for one candidate: young checkouts are kept and
# old ones need every gate (inspectable, registered, not main, not
# locked, clean) plus a merge proof before removal.
_worktree_gc_process() {
  local dir=$1 old=$2
  local common wt_list registered main_phys git_dir branch
  local status_out verdict rest reason proof_oid action
  if ((old == 0)); then
    _worktree_gc_record kept "$dir" "younger than $_WORKTREE_GC_AGE days"
    return 0
  fi
  if [[ ! -e $dir/.git ]]; then
    _worktree_gc_record skipped "$dir" "no .git"
    return 0
  fi
  if ! common=$(_worktree_gc_common_dir "$dir"); then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  if ! _worktree_gc_ensure_repo "$common"; then
    _worktree_gc_record skipped "$dir" "orphan (not in any worktree list)"
    return 0
  fi
  wt_list=$REPLY
  if ! registered=$(_worktree_gc_cached_registered "$common" "$dir"); then
    _worktree_gc_record skipped "$dir" "orphan (not in any worktree list)"
    return 0
  fi
  main_phys=$(_worktree_gc_cached_main "$common") || main_phys=
  if [[ -n $main_phys && $main_phys == "$dir" ]]; then
    _worktree_gc_record skipped "$dir" "main checkout"
    return 0
  fi
  if git_dir=$(_worktree_gc_git_dir "$dir") && [[ $git_dir == "$common" ]]; then
    _worktree_gc_record skipped "$dir" "main checkout"
    return 0
  fi
  if awk -v d="worktree $registered" '
      $0 == d { in_wt = 1; next }
      /^worktree / { in_wt = 0 }
      in_wt && /^locked/ { found = 1 }
      END { exit !found }' <<<"$wt_list"; then
    _worktree_gc_record skipped "$dir" "locked"
    return 0
  fi
  if ! status_out=$(git -C "$dir" status --porcelain 2>/dev/null); then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  if [[ -n $status_out ]]; then
    _worktree_gc_record skipped "$dir" "dirty (uncommitted/untracked changes)"
    return 0
  fi
  if ! branch=$(git -C "$dir" branch --show-current 2>/dev/null); then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  # Fetch and base-ref resolution run in the main shell: proof runs
  # under $() below, so cache writes made inside it would die with the
  # subshell. Hoisting keeps the at-most-once-per-sweep fetch (one fetch
  # per repo, one notice per dead origin) and the once-per-repo base
  # resolution (which --no-fetch would otherwise skip past); the inner
  # calls inside prove then inherit the populated caches and are no-ops.
  _worktree_gc_fetch_base "$dir" "$common"
  _worktree_gc_base_ref_cached "$dir" "$common" >/dev/null 2>&1 || true
  verdict=$(_worktree_gc_prove "$dir" "$common" "$branch")
  case $verdict in
    eligible$'\t'*)
      rest=${verdict#*$'\t'}
      reason=${rest%%$'\t'*}
      rest=${rest#*$'\t'}
      proof_oid=${rest%%$'\t'*}
      action=${rest#*$'\t'}
      _worktree_gc_remove "$dir" "$registered" "$common" "$branch" "$reason" "$proof_oid" "$action"
      ;;
    skip$'\t'*)
      _worktree_gc_record skipped "$dir" "${verdict#*$'\t'}"
      ;;
    *)
      _worktree_gc_record skipped "$dir" "broken git pointer"
      ;;
  esac
}

# Load the git-tools content-merge predicate when its library is
# available and defines it. Anything else degrades to ancestry plus
# upstream-gone with a notice; the sweep never depends on the network
# or on Shdeps state to run.
_worktree_gc_load_predicate() {
  local gt_lib=${GIT_TOOLS_BASE_LIB:-$HOME/.local/share/cgraf78/git-tools/lib/git-tools-base.sh}
  _WORKTREE_GC_HAVE_PRED=0
  if [[ -f $gt_lib ]]; then
    # shellcheck disable=SC1090
    . "$gt_lib" >/dev/null 2>&1 || true
  fi
  if declare -F _gt_branch_content_merged_oids >/dev/null 2>&1; then
    _WORKTREE_GC_HAVE_PRED=1
    return 0
  fi
  if [[ -f $gt_lib ]]; then
    _worktree_gc_err "degraded proof: $gt_lib defines no _gt_branch_content_merged_oids; content-merge detection disabled"
  else
    _worktree_gc_err "degraded proof: $gt_lib not found; content-merge detection disabled"
  fi
  return 0
}

# Prune worktree admin entries for every repo that lost a checkout.
_worktree_gc_prune_touched() {
  local common
  while IFS= read -r common || [[ -n $common ]]; do
    [[ -n $common ]] || continue
    git --git-dir="$common" worktree prune 2>/dev/null || true
  done <<<"$_WORKTREE_GC_TOUCHED"
}

_worktree_gc_tally() {
  local mode=applied
  ((_WORKTREE_GC_APPLY == 0)) && mode="dry run"
  _worktree_gc_err "done: $_WORKTREE_GC_N_REMOVED removed, $_WORKTREE_GC_N_BRANCHES branches deleted, $_WORKTREE_GC_N_BRANCHES_KEPT branches kept, $_WORKTREE_GC_N_KEPT kept, $_WORKTREE_GC_N_SKIPPED skipped, $_WORKTREE_GC_N_FAILED failed ($mode)"
}

# Sweep entry point. Parses argv, enumerates candidates once, gates on
# age with a single find pass, then proves and acts per checkout.
# Returns 0 on a clean sweep, 1 on usage or environment errors, 2 when
# any removal or branch deletion failed.
worktree_gc_main() {
  _WORKTREE_GC_APPLY=0
  _WORKTREE_GC_NO_FETCH=0
  local age=$_WORKTREE_GC_AGE_DAYS_DEFAULT
  local saw_dry=0 saw_apply=0
  local -a extra_roots=()
  local arg root old_list dir old
  local -a cands=()

  while (($# > 0)); do
    arg=$1
    case $arg in
      --older-than)
        (($# >= 2)) || {
          _worktree_gc_usage
          return 1
        }
        age=$(_worktree_gc_parse_age "$2") || {
          _worktree_gc_usage
          return 1
        }
        shift 2
        continue
        ;;
      --older-than=*)
        age=$(_worktree_gc_parse_age "${arg#--older-than=}") || {
          _worktree_gc_usage
          return 1
        }
        shift
        continue
        ;;
      --dry-run) saw_dry=1 ;;
      --apply) saw_apply=1 ;;
      --no-fetch) _WORKTREE_GC_NO_FETCH=1 ;;
      --root)
        (($# >= 2)) || {
          _worktree_gc_usage
          return 1
        }
        extra_roots+=("$2")
        shift 2
        continue
        ;;
      --root=*) extra_roots+=("${arg#--root=}") ;;
      -h | --help)
        _worktree_gc_usage
        return 0
        ;;
      *)
        _worktree_gc_usage
        return 1
        ;;
    esac
    shift
  done
  if ((saw_dry == 1 && saw_apply == 1)); then
    _worktree_gc_usage
    return 1
  fi
  if ((saw_apply == 1)); then
    _WORKTREE_GC_APPLY=1
  fi

  if [[ -z ${HOME:-} || ! -d ${HOME:-} ]]; then
    _worktree_gc_err "HOME is not set to a directory"
    return 1
  fi
  command -v git >/dev/null 2>&1 || {
    _worktree_gc_err "git is not on PATH"
    return 1
  }

  local i
  for ((i = 0; i < ${#extra_roots[@]}; i++)); do
    root=${extra_roots[$i]}
    if [[ ! -d $root ]]; then
      _worktree_gc_err "no such root: $root"
    fi
  done

  _WORKTREE_GC_AGE=$age
  _WORKTREE_GC_FETCHED=$'\n'
  _WORKTREE_GC_FRESH=$'\n'
  _WORKTREE_GC_TOUCHED=$'\n'
  _WORKTREE_GC_LIST_COMMONS=()
  _WORKTREE_GC_LIST_TEXTS=()
  _WORKTREE_GC_LIST_MAINS=()
  _WORKTREE_GC_MAP_COMMON=()
  _WORKTREE_GC_MAP_PHYS=()
  _WORKTREE_GC_MAP_REG=()
  _WORKTREE_GC_BASE_COMMONS=()
  _WORKTREE_GC_BASE_REFS=()
  _WORKTREE_GC_N_REMOVED=0
  _WORKTREE_GC_N_BRANCHES=0
  _WORKTREE_GC_N_BRANCHES_KEPT=0
  _WORKTREE_GC_N_KEPT=0
  _WORKTREE_GC_N_SKIPPED=0
  _WORKTREE_GC_N_FAILED=0
  _worktree_gc_load_predicate

  if ((${#extra_roots[@]} > 0)); then
    mapfile -t cands < <(_worktree_gc_candidates "${extra_roots[@]}")
  else
    mapfile -t cands < <(_worktree_gc_candidates)
  fi
  old_list=
  if ((${#cands[@]} > 0)); then
    # Keep partial results: find still prints the surviving matches when
    # one path vanishes mid-pass, and discarding them would silently treat
    # every old checkout as young (keep-everything) for this run.
    old_list=$(find "${cands[@]}" -maxdepth 0 -mtime +"$age" 2>/dev/null) || true
    for dir in "${cands[@]}"; do
      old=0
      case $'\n'"$old_list"$'\n' in
        *$'\n'"$dir"$'\n'*) old=1 ;;
      esac
      _worktree_gc_process "$dir" "$old"
    done
  fi

  if ((_WORKTREE_GC_APPLY == 1)); then
    _worktree_gc_prune_touched
  fi
  _worktree_gc_tally
  if ((_WORKTREE_GC_N_FAILED > 0)); then
    return 2
  fi
  return 0
}
