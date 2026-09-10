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
#   removed\t<path>\t<reason>             --apply
#   removed-branch\t<branch>\t<git-dir>
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
# - a branch is deleted only when its ref still holds the proven OID
# - a fetch failure degrades to local refs with a stderr notice; the
#   sweep never fails just because the network is down. A successful
#   fetch moves remote-tracking refs, like any fetch.
# - merge proof degrades to ancestry plus upstream-gone when the
#   git-tools predicate library is unavailable, with a stderr notice

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
_WORKTREE_GC_TOUCHED=$'\n'
_WORKTREE_GC_N_REMOVED=0
_WORKTREE_GC_N_BRANCHES=0
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

# Print the registered spelling of a candidate worktree path by
# comparing physical paths, or fail when it is not registered. Never
# trust that the enumerated spelling matches the admin copy.
_worktree_gc_registered() {
  local wt_list=$1 dir=$2 line path phys
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      'worktree '*) path=${line#worktree } ;;
      *) continue ;;
    esac
    phys=$(_dr_worktree_physical "$path") || continue
    [[ -n $phys ]] || continue
    if [[ $phys == "$dir" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done <<<"$wt_list"
  return 1
}

# Print the local base ref (short remote form, e.g. origin/main) for the
# repo owning a checkout, without touching the network, or fail.
# Prefers the origin HEAD symref, then any remote HEAD symref, then the
# conventional origin branch names. Every candidate must resolve to a
# commit; stale symrefs fall through instead of failing closed wrong.
_worktree_gc_local_base_ref() {
  local dir=$1 ref head_info default_ref candidate
  ref=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=
  if [[ $ref == */* ]] &&
    git -C "$dir" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$ref"
    return 0
  fi
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
  for candidate in main master trunk; do
    if git -C "$dir" rev-parse --verify -q "origin/$candidate^{commit}" >/dev/null 2>&1; then
      printf 'origin/%s\n' "$candidate"
      return 0
    fi
  done
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
  ref=$(_worktree_gc_local_base_ref "$dir") || return 0
  remote=${ref%%/*}
  branch=${ref#*/}
  [[ -n $remote && -n $branch && $branch != "$ref" ]] || return 0
  if err=$(git --git-dir="$common" fetch --quiet --no-tags "$remote" "$branch" 2>&1); then
    return 0
  fi
  err=${err%%$'\n'*}
  [[ -n $err ]] || err="fetch failed"
  _worktree_gc_err "$common: cannot fetch $ref ($err); using local refs"
  return 0
}

# Print the base ref for the repo owning a checkout, fetching it first
# unless --no-fetch, or fail when no remote base exists.
_worktree_gc_base_ref() {
  local dir=$1 common=$2
  _worktree_gc_fetch_base "$dir" "$common"
  _worktree_gc_local_base_ref "$dir"
}

# Prove whether an old checkout is safe to remove. Prints one tab-led
# verdict line and always returns 0 so callers parse output, not status:
#   eligible\t<reason>\t<branch-oid-or-empty>
#   skip\t<reason>
# Proof order is cheapest-first: a gone upstream needs no base OID, an
# ancestor needs no content scan, and the content predicate runs last.
# Detached checkouts take the same OID-based proofs; they simply never
# produce a branch deletion because they hold no branch.
_worktree_gc_prove() {
  local dir=$1 common=$2 branch=$3
  local head_oid proof_oid upstream_info upstream_short upstream_track
  local base_ref base_oid
  head_oid=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || {
    printf 'skip\tbroken git pointer\n'
    return 0
  }
  proof_oid=
  if [[ -n $branch ]]; then
    proof_oid=$(git -C "$dir" rev-parse --verify -q "refs/heads/$branch^{commit}" 2>/dev/null) || {
      printf 'skip\tbroken git pointer\n'
      return 0
    }
    upstream_info=$(git -C "$dir" for-each-ref --format='%(upstream:short)%09%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || upstream_info=
    IFS=$'\t' read -r upstream_short upstream_track <<<"$upstream_info"
    if [[ $upstream_track == '[gone]' ]]; then
      printf 'eligible\tupstream %s is gone\t%s\n' "${upstream_short:-$branch}" "$proof_oid"
      return 0
    fi
  fi
  base_ref=$(_worktree_gc_base_ref "$dir" "$common") || {
    printf 'skip\tno remote base branch\n'
    return 0
  }
  base_oid=$(git -C "$dir" rev-parse --verify -q "$base_ref^{commit}" 2>/dev/null) || {
    printf 'skip\tno remote base branch\n'
    return 0
  }
  if git -C "$dir" merge-base --is-ancestor "$head_oid" "$base_oid" 2>/dev/null; then
    printf 'eligible\tmerged into %s\t%s\n' "$base_ref" "$proof_oid"
    return 0
  fi
  if ((_WORKTREE_GC_HAVE_PRED == 1)) &&
    (cd -- "$dir" 2>/dev/null && _gt_branch_content_merged_oids "$head_oid" "$base_oid"); then
    printf 'eligible\tcontent-merged into %s\t%s\n' "$base_ref" "$proof_oid"
    return 0
  fi
  if [[ -n $branch ]]; then
    printf 'skip\tunmerged branch %s\n' "$branch"
  else
    printf 'skip\tdetached HEAD, unmerged\n'
  fi
  return 0
}

# Delete a local branch only when its ref still holds the proven OID.
# The expected-OID comparison is the recheck: a branch that moved since
# proof (new commits, concurrent gc) is refused, never force-deleted.
worktree_gc_delete_branch() {
  local common=$1 branch=$2 expected=$3
  [[ -n $common && -n $branch && -n $expected ]] || return 1
  [[ -d $common ]] || return 1
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || return 1
  case $expected in
    '' | *[!0-9a-f]*) return 1 ;;
  esac
  git --git-dir="$common" update-ref -d "refs/heads/$branch" "$expected" >/dev/null 2>&1
}

# Record the removal of one eligible checkout: print the dry-run intent
# or perform it. A removal that cannot unlink its top directory (parent
# not writable) fails fast before git partially empties the checkout.
# The branch is deleted only after its checkout is gone and only at the
# proven OID; a failed checkout removal deletes nothing.
_worktree_gc_remove() {
  local dir=$1 registered=$2 common=$3 branch=$4 reason=$5 proof_oid=$6
  local err
  if ((_WORKTREE_GC_APPLY == 0)); then
    _worktree_gc_record would-remove "$dir" "$reason"
    if [[ -n $branch ]]; then
      _worktree_gc_record would-remove-branch "$branch" "$common"
    fi
    return 0
  fi
  local parent=${registered%/*}
  if [[ ! -w $parent ]]; then
    _worktree_gc_record failed "$dir" "parent directory not writable"
    return 0
  fi
  if err=$(git --git-dir="$common" worktree remove "$registered" 2>&1); then
    _worktree_gc_record removed "$dir" "$reason"
    case $'\n'"$_WORKTREE_GC_TOUCHED"$'\n' in
      *$'\n'"$common"$'\n'*) ;;
      *) _WORKTREE_GC_TOUCHED+="$common"$'\n' ;;
    esac
    if [[ -n $branch ]]; then
      if worktree_gc_delete_branch "$common" "$branch" "$proof_oid" 2>/dev/null; then
        _worktree_gc_record removed-branch "$branch" "$common"
      else
        _worktree_gc_record failed-branch "$branch" "branch changed since proof"
      fi
    fi
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
  local common wt_list registered main_line main_path main_phys branch
  local verdict rest reason proof_oid
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
  if ! wt_list=$(git --git-dir="$common" worktree list --porcelain 2>/dev/null) ||
    ! registered=$(_worktree_gc_registered "$wt_list" "$dir"); then
    _worktree_gc_record skipped "$dir" "orphan (not in any worktree list)"
    return 0
  fi
  main_line=$(grep -m1 '^worktree ' <<<"$wt_list") || main_line=
  main_path=${main_line#worktree }
  main_phys=$(_dr_worktree_physical "$main_path") || main_phys=
  if [[ -n $main_phys && $main_phys == "$dir" ]]; then
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
  if [[ -n $(git -C "$dir" status --porcelain 2>/dev/null) ]]; then
    _worktree_gc_record skipped "$dir" "dirty (uncommitted/untracked changes)"
    return 0
  fi
  if ! branch=$(git -C "$dir" branch --show-current 2>/dev/null); then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  verdict=$(_worktree_gc_prove "$dir" "$common" "$branch")
  case $verdict in
    eligible$'\t'*)
      rest=${verdict#*$'\t'}
      reason=${rest%%$'\t'*}
      proof_oid=${rest#*$'\t'}
      _worktree_gc_remove "$dir" "$registered" "$common" "$branch" "$reason" "$proof_oid"
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
    . "$gt_lib" 2>/dev/null || true
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
  _worktree_gc_err "done: $_WORKTREE_GC_N_REMOVED removed, $_WORKTREE_GC_N_BRANCHES branches deleted, $_WORKTREE_GC_N_KEPT kept, $_WORKTREE_GC_N_SKIPPED skipped, $_WORKTREE_GC_N_FAILED failed ($mode)"
}

# Sweep entry point. Parses argv, enumerates candidates once, gates on
# age with a single find pass, then proves and acts per checkout.
# Returns 0 on a clean sweep, 1 on usage or environment errors, 2 when
# any removal or branch deletion failed.
worktree_gc_main() {
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
  _WORKTREE_GC_TOUCHED=$'\n'
  _WORKTREE_GC_N_REMOVED=0
  _WORKTREE_GC_N_BRANCHES=0
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
    old_list=$(find "${cands[@]}" -maxdepth 0 -mtime +"$age" 2>/dev/null) || old_list=
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
