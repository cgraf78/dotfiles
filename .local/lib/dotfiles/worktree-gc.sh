# shellcheck shell=bash
# worktree-gc.sh — multi-repo branch and worktree garbage collection.
#
# Library for the `dot-worktree-gc` entry point. Nothing here runs on
# source except loading the doctor enumeration helpers; the entry point
# calls `worktree_gc_main "$@"`. Written for `set -u` with no `-e`;
# every fallible step handles its own failure explicitly.
#
# Division of labor: this file owns discovery (which repositories and
# checkouts the sweep covers), the age policy, and retiring directories no
# repository can speak for (empty leftovers and metadata-orphaned
# checkouts). Every per-repository decision -- which branches are proven
# merged and which linked checkouts may go -- belongs to
# `git cleanup-repo` from git-tools, driven through its porcelain records
# with --no-update-base, so the sweep never moves a local base and shares
# one set of merge proofs and removal gates with every other git-tools
# command. The git-tools root resolves from GIT_TOOLS_ROOT, defaulting to
# its Shdeps install path.
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
# Branch records cover every proven-merged local branch in a swept
# repository, not only branches of swept checkouts. A kept branch is listed
# only when its checkout was retired without it; other kept branches are
# counted in the tally. Cache entries pruned inside a checkout are reported
# on stderr. Diagnostics and
# the final tally go to stderr; stdout carries records only. Exit 0: clean
# sweep; 1: usage or environment error; 2: a removal, branch deletion, or
# repository cleanup failed.
#
# Safety rules (all enforced, none optional):
# - never `rm -rf` and never `git worktree remove --force`, here or in
#   git-tools
# - checkouts younger than the age limit are never selected; branch
#   deletion needs a merge proof from git-tools (ancestry, exact content,
#   a landed tree, or a merged pull request), and a branch proven only by
#   ancestry must also be at least a day old by its reflog
# - git-tools keeps a checkout that is the main or current one, locked,
#   dirty, holding untracked or ignored content other than tagged caches,
#   mid-operation or mid-checkout, or a process's working directory, and
#   never forces a removal
# - checkout-only proofs keep the branch: a gone own-name upstream, a
#   closed pull request (--include-closed), or a superseded Actions pin
# - metadata-orphaned checkouts require an exact merged-history snapshot;
#   removal uses a private quarantine and checked unlink/rmdir, never refs
# - old, empty directories with no known registration, directly under
#   roots, are removed with rmdir only; symlink targets and in-use dirs stay
# - a missing or older git-tools skips repository cleanup with a notice;
#   empty and orphaned directories are still handled
#
# Known limitations (documented, not fixed):
# - age is the newest of the checkout top directory and its Git HEAD,
#   index, and reftable (the doctor's activity signals, shared through
#   _dr_worktree_old_checkouts): `-mtime +N` matches N+1 days and older,
#   editing files without staging, committing, or checking out does not
#   count as activity, and any tool whose `git status` refreshes the index
#   makes a checkout look active again (both err toward keeping)

_WORKTREE_GC_AGE_DAYS_DEFAULT=14

_WORKTREE_GC_DIR=${BASH_SOURCE[0]%/*}
if [[ -z ${_DR_WORKTREE_WARN_BYTES_DEFAULT:-} ]]; then
  # shellcheck source=doctor.d/lib/worktrees.sh
  . "$_WORKTREE_GC_DIR/doctor.d/lib/worktrees.sh" || return 1
fi

# The superseded Actions-pin proof is specific to cgraf78/actions consumers,
# so it stays here and reaches git-tools as an explicit retirement request.
# shellcheck source=worktree-gc-actions.sh
. "$_WORKTREE_GC_DIR/worktree-gc-actions.sh" || return 1

# --- shared sweep state (initialized by worktree_gc_main) ---
_WORKTREE_GC_AGE=$_WORKTREE_GC_AGE_DAYS_DEFAULT
_WORKTREE_GC_APPLY=0
_WORKTREE_GC_NO_FETCH=0
_WORKTREE_GC_INCLUDE_CLOSED=0
_WORKTREE_GC_CLEANUP=
_WORKTREE_GC_FETCHED=$'\n'
_WORKTREE_GC_FRESH=$'\n'
# Per-repo caches, keyed by common git dir: one `worktree list` per repo
# serves every checkout's registration and main-checkout lookups. Parallel
# indexed arrays (no associative arrays) keep the file on its existing shell
# requirements. Populated in the main shell only.
_WORKTREE_GC_LIST_COMMONS=()
_WORKTREE_GC_LIST_TEXTS=()
_WORKTREE_GC_LIST_MAINS=()
_WORKTREE_GC_MAP_COMMON=()
_WORKTREE_GC_MAP_PHYS=()
_WORKTREE_GC_MAP_REG=()
# Old linked checkouts selected for git-tools, grouped by repository.
_WORKTREE_GC_SEL_COMMON=()
_WORKTREE_GC_SEL_DIR=()
_WORKTREE_GC_SEL_REG=()
_WORKTREE_GC_SEL_BRANCH=()
_WORKTREE_GC_SEL_DONE=()
# Physical live registered checkouts and process working directories, loaded
# once per sweep for the empty-directory and orphan gates.
_WORKTREE_GC_LIVE=()
_WORKTREE_GC_DIRECT=()
_WORKTREE_GC_REGISTERED=()
_WORKTREE_GC_CWDS=()
_WORKTREE_GC_CWDS_LOADED=0
_WORKTREE_GC_CWDS_WARNED=0
_WORKTREE_GC_N_REMOVED=0
_WORKTREE_GC_N_BRANCHES=0
_WORKTREE_GC_N_BRANCHES_KEPT=0
_WORKTREE_GC_N_KEPT=0
_WORKTREE_GC_N_SKIPPED=0
_WORKTREE_GC_N_FAILED=0

_worktree_gc_err() { printf 'dot-worktree-gc: %s\n' "$*" >&2; }

_worktree_gc_usage() {
  cat >&2 <<'USAGE'
usage: dot-worktree-gc [--older-than N[d]] [--dry-run|--apply] [--no-fetch] [--include-closed]
                       [--root DIR]...
  Delete proven-merged local branches in every repo the sweep covers, and
  remove worktrees with no Git activity for over N days (default 14) whose
  work landed or was superseded. Repos covered: ~/.dotfiles, every ~/git/*
  and ~/.dotfiles-* clone, and the owner of every discovered checkout.
  Checkouts swept: ~/.worktrees, ~/git/worktrees, ~/worktrees and
  ~/git/.worktrees (one grouping folder deep), the .worktrees of every
  ~/git/* and ~/.dotfiles-* clone, and checkouts the base dotfiles repo
  registered anywhere.
  Per-repo decisions come from `git cleanup-repo` (git-tools): merge
  proofs, open-PR protection, and the removal gates. A checkout holding
  untracked or ignored content other than cache-tagged directories (and the
  repo's cleanupRepo.worktreePrunePath entries, which are pruned) stays.
  Old empty directories with no known registration are also eligible;
  they are removed with rmdir only. Nonempty directories without .git stay.
  Broken linked-worktree pointers can retire only exact merged snapshots;
  optional Python 3.9+ and readable /proc process information are required.
  Dry run is the default; --apply performs removals.
  --root adds a worktree root (its children only) to the sweep and may
  repeat.
  --no-fetch proves against local refs without touching the network.
  --include-closed also removes checkouts belonging to closed unmerged PRs,
  retaining their branches. An open PR keeps a branch, and its checkout,
  that no local proof covers.
  Records print on stdout; diagnostics and the tally go to stderr.
USAGE
}

# Print the day count for an age argument (N, or N with a d suffix), or fail.
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
  local home=${HOME:-} home_phys dotfiles dotfiles_phys dir
  home_phys=$(_dr_worktree_physical "$home") || home_phys=$home
  _dr_worktree_base_gitdir
  dotfiles=$REPLY
  dotfiles_phys=
  if [[ -n $dotfiles && -d $dotfiles ]]; then
    dotfiles_phys=$(_dr_worktree_physical "$dotfiles") || dotfiles_phys=
  fi
  _dr_worktree_candidates "$@" | LC_ALL=C sort -u |
    while IFS= read -r dir || [[ -n $dir ]]; do
      [[ -n $dir && -d $dir ]] || continue
      [[ $dir == "$home_phys" ]] && continue
      if [[ -n $dotfiles_phys && $dir == "$dotfiles_phys" ]]; then
        continue
      fi
      # Failed orphan cleanups retain files in private quarantine containers.
      # Never rediscover their contents, even through an explicit --root.
      case /$dir/ in
        */.dot-worktree-gc-quarantine-*/*) continue ;;
      esac
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
  local common=$1 wt_list=$2 i path phys main_path='' main_phys=''
  _dr_worktree_porcelain_records "$wt_list"
  for ((i = 0; i < ${#_DR_WORKTREE_REC_PATHS[@]}; i++)); do
    path=${_DR_WORKTREE_REC_PATHS[$i]}
    ((i == 0)) && main_path=$path
    phys=$(_dr_worktree_physical "$path") || continue
    [[ -n $phys ]] || continue
    _WORKTREE_GC_MAP_COMMON+=("$common")
    _WORKTREE_GC_MAP_PHYS+=("$phys")
    _WORKTREE_GC_MAP_REG+=("$path")
  done
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
# The cached list is blind to concurrent admin mutation within a sweep
# (a lock added after caching reads as unlocked; an externally removed
# checkout reads as registered). Worst case is a verdict-label delta,
# never destruction: `git worktree remove` refuses locked checkouts,
# and branch deletion never follows a failed removal.
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

# Run a command that may reach a remote without ever asking for credentials:
# the sweep is unattended, so a remote that wants them (a deleted or private
# HTTPS repository answers 401) must fail and read as unreachable, never stop
# the sweep at a prompt. Git consults GIT_ASKPASS, core.askPass, and
# SSH_ASKPASS before GIT_TERMINAL_PROMPT, so an editor terminal's askpass
# helper (VS Code sets GIT_ASKPASS) would still raise a dialog; an empty
# GIT_ASKPASS skips all three. Configured credential helpers still answer.
# SSH passphrase and host-key prompts read /dev/tty directly and are left to
# the user's SSH setup.
_worktree_gc_batch() {
  GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_ASKPASS='' "$@" </dev/null
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
  _dr_worktree_base_ref_ensure "$dir" || return 0
  ref=$REPLY
  remote=${ref%%/*}
  branch=${ref#*/}
  [[ -n $remote && -n $branch && $branch != "$ref" ]] || return 0
  if err=$(_worktree_gc_batch git --git-dir="$common" fetch --quiet --no-tags \
    "$remote" "$branch" 2>&1); then
    _WORKTREE_GC_FRESH+="$common"$'\n'
    return 0
  fi
  err=${err%%$'\n'*}
  [[ -n $err ]] || err="fetch failed"
  _worktree_gc_err "$common: cannot fetch $ref ($err); using local refs"
  return 0
}

# Succeed when some process's working directory is DIR or inside it: an idle
# shell or agent session parked in a checkout is still using it. Reads the
# working directories once per sweep, on first use (_worktree_gc_load_cwds),
# so only a sweep with a removable checkout pays; where they cannot be read
# the check is skipped. Must run in the main shell.
_worktree_gc_in_use() {
  local dir=$1 cwd
  ((_WORKTREE_GC_CWDS_LOADED == 1)) || _worktree_gc_load_cwds
  for cwd in ${_WORKTREE_GC_CWDS[@]+"${_WORKTREE_GC_CWDS[@]}"}; do
    [[ $cwd == "$dir" || $cwd == "$dir"/* ]] && return 0
  done
  return 1
}

# Fill _WORKTREE_GC_CWDS with every readable process working directory
# under _WORKTREE_GC_PROC (/proc). One subshell resolves every `<pid>/cwd`
# link with builtins only: `cd -P` follows the kernel's link and `pwd -P`
# reads the result back, so there is no process per pid and no GNU-only tool
# (BusyBox find has no -printf, which silently emptied an earlier version
# on Alpine). Other users' processes are unreadable and skipped. Without
# /proc (macOS, BSD) the list stays empty and the check is off by design.
# Where /proc exists but resolves nothing at all, not even this sweep's own
# process, the scan is broken rather than idle: say so once on stderr
# instead of reporting nothing in use. Must run in the main shell.
_WORKTREE_GC_PROC=/proc
_worktree_gc_load_cwds() {
  local proc=$_WORKTREE_GC_PROC
  _WORKTREE_GC_CWDS=()
  _WORKTREE_GC_CWDS_LOADED=1
  [[ -d $proc ]] || return 0
  # A process in another mount namespace lets `cd` in but not `pwd -P`
  # back out; it prints nothing and is skipped, like an unreadable one.
  mapfile -t _WORKTREE_GC_CWDS < <(
    for link in "$proc"/[0-9]*/cwd; do
      cd -P -- "$link" && pwd -P
    done 2>/dev/null
  )
  if ((${#_WORKTREE_GC_CWDS[@]} == 0 && _WORKTREE_GC_CWDS_WARNED == 0)); then
    _WORKTREE_GC_CWDS_WARNED=1
    _worktree_gc_err "cannot read process working directories under $proc; the in-use check is off for this sweep"
  fi
  return 0
}

# Fill _WORKTREE_GC_LIVE with the physical path of every live checkout a
# clone root registered (the doctor's admin scan: file reads only), for the
# nested-checkout gate. Must run in the main shell.
_worktree_gc_load_live() {
  local path phys
  _WORKTREE_GC_LIVE=()
  _WORKTREE_GC_REGISTERED=()
  _dr_worktree_admin_scan
  for path in ${_DR_WORKTREE_ADMIN_PATHS[@]+"${_DR_WORKTREE_ADMIN_PATHS[@]}"}; do
    phys=$(_dr_worktree_physical "$path") || continue
    [[ -z $phys ]] || _WORKTREE_GC_REGISTERED+=("$phys")
  done
  for path in ${_DR_WORKTREE_ADMIN_LIVE[@]+"${_DR_WORKTREE_ADMIN_LIVE[@]}"}; do
    phys=$(_dr_worktree_physical "$path")
    [[ -n $phys ]] && _WORKTREE_GC_LIVE+=("$phys")
  done
  return 0
}

# Test emptiness including dotfiles without leaking glob options to callers.
# Unreadable directories cannot establish absence of valuable contents.
_worktree_gc_empty() (
  local dir=$1
  [[ -d $dir && ! -L $dir && -r $dir && -x $dir ]] || return 1
  shopt -s nullglob dotglob
  local -a entries=("$dir"/*)
  ((${#entries[@]} == 0))
)

_worktree_gc_registered() {
  local dir=$1 registered
  for registered in ${_WORKTREE_GC_REGISTERED[@]+"${_WORKTREE_GC_REGISTERED[@]}"}; do
    [[ $registered != "$dir" ]] || return 0
  done
  return 1
}

# Retire an old empty container, not a Git checkout. rmdir is the final atomic
# guard: a file appearing after inspection makes it refuse removal. Never use
# recursive deletion, and never follow a candidate alias to an unrelated dir.
_worktree_gc_remove_empty() {
  local dir=$1 direct found=0 err
  if ! _worktree_gc_empty "$dir"; then
    _worktree_gc_record skipped "$dir" "no .git"
    return 0
  fi
  for direct in ${_WORKTREE_GC_DIRECT[@]+"${_WORKTREE_GC_DIRECT[@]}"}; do
    [[ $direct != "$dir" ]] || found=1
  done
  if ((found == 0)); then
    _worktree_gc_record skipped "$dir" "empty directory reached through symlink"
    return 0
  fi
  # Refresh the discovered repositories' registrations before preview or apply;
  # a missing .git file does not imply that a known owner forgot this checkout.
  # Unknown owners cannot be recovered from an empty directory alone, so the
  # record reports absence of known registration, never a global Git proof.
  _worktree_gc_load_live
  if _worktree_gc_registered "$dir"; then
    _worktree_gc_record skipped "$dir" "registered worktree, missing .git"
    return 0
  fi
  # Even an empty directory may be an idle shell's working directory.
  _worktree_gc_load_cwds
  if _worktree_gc_in_use "$dir"; then
    _worktree_gc_record skipped "$dir" "in use (a process's working directory)"
    return 0
  fi
  if ((_WORKTREE_GC_APPLY == 0)); then
    _worktree_gc_record would-remove "$dir" "empty directory, no known registration"
  elif err=$(rmdir -- "$dir" 2>&1); then
    _worktree_gc_record removed "$dir" "empty directory, no known registration"
  elif ! _worktree_gc_empty "$dir"; then
    _worktree_gc_record skipped "$dir" "directory changed during cleanup"
  else
    err=${err%%$'\n'*}
    _worktree_gc_record failed "$dir" "${err:-rmdir failed}"
  fi
  return 0
}

# Recover only a missing linked-worktree registration, never an arbitrary bad
# repository. The helper proves the complete disk snapshot without an index and
# leaves Git objects, refs, and administrative state untouched.
_worktree_gc_remove_orphan() {
  local dir=$1 direct found=0 common base_ref base_oid oid err status nested
  local repo_dir
  local helper=$_WORKTREE_GC_DIR/worktree-gc-orphans.py
  for direct in ${_WORKTREE_GC_DIRECT[@]+"${_WORKTREE_GC_DIRECT[@]}"}; do
    [[ $direct != "$dir" ]] || found=1
  done
  if ((found == 0)) || ! command -v python3 >/dev/null 2>&1 || [[ ! -f $helper ]]; then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  common=$(python3 "$helper" owner "$dir" 2>/dev/null) || {
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  }
  _worktree_gc_load_live
  for nested in ${_WORKTREE_GC_LIVE[@]+"${_WORKTREE_GC_LIVE[@]}"} \
    ${_WORKTREE_GC_REGISTERED[@]+"${_WORKTREE_GC_REGISTERED[@]}"}; do
    if [[ $nested == "$dir"/* ]]; then
      _worktree_gc_record skipped "$dir" "contains another checkout (${nested#"$dir"/})"
      return 0
    fi
  done
  if _worktree_gc_registered "$dir"; then
    _worktree_gc_record skipped "$dir" "registered worktree with broken git pointer"
    return 0
  fi
  _worktree_gc_load_cwds
  if _worktree_gc_in_use "$dir"; then
    _worktree_gc_record skipped "$dir" "in use (a process's working directory)"
    return 0
  fi
  # Resolve through a checkout, not the bare Git directory (see
  # _worktree_gc_sweep_repo): a PATH launcher can reroute Git run there.
  repo_dir=$common
  _worktree_gc_ensure_repo "$common" && _worktree_gc_repo_dir "$common" &&
    repo_dir=$REPLY
  _worktree_gc_fetch_base "$repo_dir" "$common"
  if ! _dr_worktree_base_ref_ensure "$repo_dir"; then
    _worktree_gc_record skipped "$dir" "orphaned checkout has no base ref"
    return 0
  fi
  base_ref=$REPLY
  base_oid=$(git --git-dir="$common" rev-parse --verify "$base_ref^{commit}" 2>/dev/null) || {
    _worktree_gc_record skipped "$dir" "orphaned checkout has no base commit"
    return 0
  }
  err=$(mktemp) || {
    _worktree_gc_record failed "$dir" "cannot prepare orphan inspection"
    return 0
  }
  if ((_WORKTREE_GC_APPLY == 0)); then
    oid=$(python3 "$helper" prove "$dir" "$base_oid" 2>"$err")
    status=$?
  else
    oid=$(python3 "$helper" remove "$dir" "$base_oid" 2>"$err")
    status=$?
  fi
  if ((status == 0)); then
    if ((_WORKTREE_GC_APPLY == 0)); then
      _worktree_gc_record would-remove "$dir" "orphaned checkout matches merged commit $oid"
    else
      _worktree_gc_record removed "$dir" "orphaned checkout matches merged commit $oid"
    fi
  else
    IFS= read -r oid <"$err" || true
    if ((status == 2)); then
      _worktree_gc_record failed "$dir" "${oid:-orphan cleanup failed}"
    else
      _worktree_gc_record skipped "$dir" "${oid:-broken git pointer}"
    fi
  fi
  rm -f -- "$err"
  return 0
}

# Locate the git-tools cleanup provider. Anything missing or too old leaves
# _WORKTREE_GC_CLEANUP empty with one notice; the sweep still handles empty
# and orphaned directories, which need no repository decision.
_worktree_gc_load_provider() {
  local root=${GIT_TOOLS_ROOT:-$HOME/.local/share/cgraf78/git-tools} bin
  bin=$root/bin/git-cleanup-repo
  _WORKTREE_GC_CLEANUP=
  if [[ ! -x $bin ]]; then
    _worktree_gc_err "git-tools not found at $root; branch and checkout cleanup skipped"
    return 0
  fi
  # A release predating the porcelain interface rejects these options before
  # it reaches --help, so the exit status answers without parsing usage text.
  # The interface shipped as one git-tools release, so these options also
  # imply its unreachable-remote status and pull request lookup guard.
  if ! "$bin" --porcelain --no-update-base --worktree . --retire-worktree . \
    --include-closed --min-age 1 --help >/dev/null 2>&1; then
    _worktree_gc_err "git-tools at $root predates porcelain cleanup; run 'dot update' to clean branches and checkouts"
    return 0
  fi
  _WORKTREE_GC_CLEANUP=$bin
}

# Print the display reason for a git-tools reason code and detail. The codes
# drive control flow; this text is only rendered.
_worktree_gc_reason() {
  local code=$1 detail=${2:-}
  case $code in
    merged) printf 'merged' ;;
    content-merged) printf 'content-merged' ;;
    tree-landed) printf 'tree landed' ;;
    merged-pr) printf 'merged PR' ;;
    upstream-gone) printf 'upstream gone (branch kept)' ;;
    closed-pr) printf 'closed unmerged PR (branch kept)' ;;
    requested) printf 'Actions pin superseded (branch kept)' ;;
    merge-unproven) printf 'merge unproven' ;;
    open-pr) printf 'open PR #%s' "$detail" ;;
    too-new) printf 'branch created or moved within a day' ;;
    current-worktree) printf 'current checkout' ;;
    main-worktree) printf 'main checkout' ;;
    locked) printf 'locked' ;;
    dirty) printf 'dirty (uncommitted changes)' ;;
    hidden) printf 'untracked or ignored local content' ;;
    operation) printf 'active %s' "$detail" ;;
    in-use) printf "in use (a process's working directory)" ;;
    checkout-in-flight) printf 'a Git command is running there' ;;
    missing) printf 'directory gone' ;;
    not-linked) printf 'not a linked worktree' ;;
    unreachable-head) printf 'detached HEAD on no branch' ;;
    branch-changed) printf 'changed during cleanup' ;;
    uninspectable) printf 'cannot inspect' ;;
    checked-out) printf 'checked out in another worktree' ;;
    reserved) printf 'checked out during cleanup' ;;
    prune-failed | remove-failed) printf 'removal failed' ;;
    pr-unknown) printf 'open-PR check unavailable' ;;
    *) printf '%s' "$code" ;;
  esac
}

# Undo the porcelain escaping of one field (\\, \t, \n).
_worktree_gc_unescape() {
  local value=$1 out='' rest
  while [[ $value == *\\* ]]; do
    out+=${value%%\\*}
    rest=${value#*\\}
    case ${rest:0:1} in
      t) out+=$'\t' ;;
      n) out+=$'\n' ;;
      *) out+=${rest:0:1} ;;
    esac
    value=${rest:1}
  done
  REPLY=$out$value
}

# Run git-tools cleanup for one repository with the given arguments, filling
# _WORKTREE_GC_OUT with its records and _WORKTREE_GC_ERRLINE with its last
# diagnostic, which is the fatal one on failure (earlier lines are notes,
# such as a followed default branch). The base client's work tree is HOME,
# so it runs from HOME with GIT_DIR and GIT_WORK_TREE naming both, as the
# `git` launcher does: a fresh client records HOME in core.worktree, but a
# legacy bare client (core.bare=true) only gets a work tree from the
# environment, and Git alone would call it bare. Any other repository runs
# from its main checkout. Credential prompts are off (_worktree_gc_batch), so
# a remote that wants credentials reads as unreachable and falls back to
# local refs. Returns the provider's status, or 125 when the repository has
# no checkout to run from.
_worktree_gc_run_cleanup() {
  local common=$1 base main err line status=0
  shift
  _WORKTREE_GC_OUT=
  _WORKTREE_GC_ERRLINE=
  err=$(mktemp) || return 1
  _dr_worktree_base_gitdir
  base=$REPLY
  if [[ -n $base && -d $base && $common -ef $base ]]; then
    _WORKTREE_GC_OUT=$(cd -- "$HOME" &&
      GIT_DIR=$common GIT_WORK_TREE=$HOME \
        _worktree_gc_batch "$_WORKTREE_GC_CLEANUP" "$@" 2>"$err") || status=$?
  else
    main=$(_worktree_gc_cached_main "$common") || main=
    if [[ -z $main || ! -e $main/.git ]]; then
      rm -f -- "$err"
      return 125
    fi
    _WORKTREE_GC_OUT=$(cd -- "$main" &&
      _worktree_gc_batch "$_WORKTREE_GC_CLEANUP" "$@" 2>"$err") || status=$?
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -z $line ]] || _WORKTREE_GC_ERRLINE=$line
  done <"$err"
  rm -f -- "$err"
  return "$status"
}

# Report via REPLY the directory to run Git for a repository from: HOME for
# the base client, whose work tree it is, else its main checkout. Fails when
# the repository has no checkout.
_worktree_gc_repo_dir() {
  local common=$1 base main
  REPLY=
  _dr_worktree_base_gitdir
  base=$REPLY
  REPLY=
  if [[ -n $base && -d $base && $common -ef $base ]]; then
    REPLY=$HOME
    return 0
  fi
  main=$(_worktree_gc_cached_main "$common") || return 1
  [[ -n $main && -e $main/.git ]] || return 1
  REPLY=$main
}

# Index of a selected checkout by its registered path in the current repo, or
# fail.
_worktree_gc_sel_index() {
  local common=$1 path=$2 i
  for ((i = 0; i < ${#_WORKTREE_GC_SEL_REG[@]}; i++)); do
    [[ ${_WORKTREE_GC_SEL_COMMON[$i]} == "$common" ]] || continue
    if [[ ${_WORKTREE_GC_SEL_REG[$i]} == "$path" ]]; then
      REPLY=$i
      return 0
    fi
  done
  return 1
}

# Render one git-tools record for repository COMMON as sweep records.
_worktree_gc_map_record() {
  local common=$1 event=$2 subject=$3 code=$4 detail=$5 reason idx dir
  reason=$(_worktree_gc_reason "$code" "$detail")
  case $event in
    delete-branch | would-delete-branch)
      if ((_WORKTREE_GC_APPLY == 1)); then
        _worktree_gc_record removed-branch "$subject" "$common"
      else
        _worktree_gc_record would-remove-branch "$subject" "$common"
      fi
      ;;
    keep-branch)
      if [[ $code == ref-delete-failed ]]; then
        _worktree_gc_record failed-branch "$subject" "exact ref deletion failed"
        return 0
      fi
      # A selected checkout's branch is accounted for by that checkout's own
      # record; any other kept branch is counted, not listed, since a
      # repository can hold hundreds of unproven branches.
      for ((idx = 0; idx < ${#_WORKTREE_GC_SEL_BRANCH[@]}; idx++)); do
        [[ ${_WORKTREE_GC_SEL_COMMON[$idx]} == "$common" &&
          ${_WORKTREE_GC_SEL_BRANCH[$idx]} == "$subject" ]] && return 0
      done
      _WORKTREE_GC_N_BRANCHES_KEPT=$((_WORKTREE_GC_N_BRANCHES_KEPT + 1))
      ;;
    prune-entry | would-prune-entry)
      # Cache pruning inside a checkout is a diagnostic, not a sweep record.
      _worktree_gc_err "${event%-entry} cache $subject/$detail"
      ;;
    remove-worktree | would-remove-worktree | keep-worktree)
      _worktree_gc_sel_index "$common" "$subject" || return 0
      idx=$REPLY
      dir=${_WORKTREE_GC_SEL_DIR[$idx]}
      _WORKTREE_GC_SEL_DONE[idx]=1
      case $event in
        remove-worktree) _worktree_gc_record removed "$dir" "$reason" ;;
        would-remove-worktree) _worktree_gc_record would-remove "$dir" "$reason" ;;
        keep-worktree)
          case $code in
            remove-failed | prune-failed)
              _worktree_gc_record failed "$dir" "removal failed"
              ;;
            *) _worktree_gc_record skipped "$dir" "$reason" ;;
          esac
          return 0
          ;;
      esac
      # A checkout retired on its own evidence keeps its branch; say so,
      # matching the branch records of earlier sweeps.
      case $code in
        upstream-gone | closed-pr | requested)
          [[ -z $detail ]] && return 0
          if ((_WORKTREE_GC_APPLY == 1)); then
            _worktree_gc_record skipped-branch "$detail" "$reason"
          else
            _worktree_gc_record would-skip-branch "$detail" "$reason"
          fi
          ;;
      esac
      ;;
  esac
  return 0
}

# Print REMOTE's HEAD symref as a short <remote>/<branch> name, or nothing.
# The base client's HOME has no .git of its own, so it names its Git
# directory, as base resolution does.
_worktree_gc_head_symref() {
  local repo_dir=$1 common=$2 remote=$3
  if [[ $repo_dir == "$HOME" ]]; then
    git --git-dir="$common" symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null
  else
    git -C "$repo_dir" symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2>/dev/null
  fi
  return 0
}

# Sweep one repository: delete its proven-merged branches and decide every
# selected old checkout it owns, in one git-tools run.
_worktree_gc_sweep_repo() {
  local common=$1 repo_dir base_ref remote i dir reg tip base_oid status
  local event subject code detail rec
  local -a args=(--no-update-base --porcelain --min-age 1) selections=() offline=()

  # A bare repository, or one whose main checkout is gone, has nowhere to run
  # cleanup from; its selected checkouts stay.
  if ! _worktree_gc_repo_dir "$common"; then
    _worktree_gc_skip_selected "$common" "repository has no main checkout"
    return 0
  fi
  repo_dir=$REPLY
  # Resolve from a checkout: Git run inside a bare Git directory can be
  # rerouted by a PATH launcher (the dotfiles `git` maps directories under
  # HOME without a work tree to the base client) and answer for the wrong
  # repository. The base client's HOME has no .git of its own; name its Git
  # directory instead.
  base_ref=
  if [[ $repo_dir == "$HOME" ]]; then
    GIT_DIR=$common _dr_worktree_base_ref_ensure "$repo_dir" && base_ref=$REPLY
  else
    _dr_worktree_base_ref_ensure "$repo_dir" && base_ref=$REPLY
  fi
  # Without a resolvable remote base there is nothing to prove against.
  if [[ -z $base_ref ]]; then
    _worktree_gc_skip_selected "$common" "no remote base branch"
    return 0
  fi
  # A base read from <remote>/HEAD can be stale: Git records it at clone time,
  # so an upstream that renamed master to main still looks like master here.
  # Leave that base to git-tools, which reads the same symref (so the base is
  # unchanged offline or with an older git-tools) and, on a fetching run,
  # follows the remote's own default when the named branch is gone. A base
  # from any other source (no symref, or one whose target was pruned) is
  # passed explicitly, so both tools keep proving against the same branch.
  remote=${base_ref%%/*}
  args+=(--remote "$remote")
  if [[ $(_worktree_gc_head_symref "$repo_dir" "$common" "$remote") != "$base_ref" ]]; then
    args+=(--base "${base_ref#*/}")
  fi
  ((_WORKTREE_GC_APPLY == 1)) || args+=(--dry-run)
  ((_WORKTREE_GC_INCLUDE_CLOSED == 0)) || args+=(--include-closed)
  for ((i = 0; i < ${#_WORKTREE_GC_SEL_REG[@]}; i++)); do
    [[ ${_WORKTREE_GC_SEL_COMMON[$i]} == "$common" ]] || continue
    dir=${_WORKTREE_GC_SEL_DIR[$i]}
    reg=${_WORKTREE_GC_SEL_REG[$i]}
    offline+=(--worktree "$reg")
    # A superseded Actions pin retires the checkout on gc's own evidence;
    # git-tools still deletes the branch instead when it can prove a merge,
    # and keeps the checkout when an open PR, an unreadable PR lookup, or a
    # gate says so.
    tip=$(git -C "$dir" rev-parse --verify -q HEAD 2>/dev/null) || tip=
    base_oid=$(git -C "$dir" rev-parse --verify -q "$base_ref^{commit}" 2>/dev/null) || base_oid=
    if [[ -n $tip && -n $base_oid ]] &&
      git -C "$dir" symbolic-ref -q HEAD >/dev/null 2>&1 &&
      _worktree_gc_actions_superseded "$dir" "$tip" "$base_oid"; then
      selections+=(--retire-worktree "$reg")
    else
      selections+=(--worktree "$reg")
    fi
  done

  status=0
  if ((_WORKTREE_GC_NO_FETCH == 1)); then
    _worktree_gc_run_cleanup "$common" "${args[@]}" --no-fetch \
      ${offline[@]+"${offline[@]}"} || status=$?
  else
    _worktree_gc_run_cleanup "$common" "${args[@]}" \
      ${selections[@]+"${selections[@]}"} || status=$?
    if ((status == 3)); then
      # The remote base was unreachable, before any decision: an unreachable
      # remote must not stop the sweep, so prove against local refs, which
      # can only keep more. Offline, nothing can confirm that no open PR
      # holds a branch, so retirement requests become plain selections.
      _worktree_gc_err "$common: remote base unreachable (${_WORKTREE_GC_ERRLINE:-no detail}); using local refs"
      status=0
      _worktree_gc_run_cleanup "$common" "${args[@]}" --no-fetch \
        ${offline[@]+"${offline[@]}"} || status=$?
    fi
  fi
  while IFS= read -r rec; do
    [[ -n $rec ]] || continue
    # Split by hand: `read` with a TAB IFS would merge an empty field into
    # the next one.
    event=${rec%%$'\t'*}
    rec=${rec#*$'\t'}
    subject=${rec%%$'\t'*}
    rec=${rec#*$'\t'}
    code=${rec%%$'\t'*}
    detail=
    [[ $rec == *$'\t'* ]] && detail=${rec#*$'\t'}
    _worktree_gc_unescape "$subject"
    subject=$REPLY
    _worktree_gc_unescape "$detail"
    detail=$REPLY
    _worktree_gc_map_record "$common" "$event" "$subject" "$code" "$detail"
  done <<<"$_WORKTREE_GC_OUT"
  if ((status != 0)); then
    _worktree_gc_record failed "$common" "git cleanup-repo failed: ${_WORKTREE_GC_ERRLINE:-exit $status}"
  fi
  # git-tools promises one outcome per selected checkout; never leave one
  # unreported if it breaks that promise or stopped early.
  _worktree_gc_skip_selected "$common" "no cleanup decision"
}

# Record every still-undecided selected checkout of a repository as skipped.
_worktree_gc_skip_selected() {
  local common=$1 reason=$2 i
  for ((i = 0; i < ${#_WORKTREE_GC_SEL_REG[@]}; i++)); do
    [[ ${_WORKTREE_GC_SEL_COMMON[$i]} == "$common" ]] || continue
    [[ ${_WORKTREE_GC_SEL_DONE[$i]} == 1 ]] && continue
    _worktree_gc_record skipped "${_WORKTREE_GC_SEL_DIR[$i]}" "$reason"
    _WORKTREE_GC_SEL_DONE[i]=1
  done
}

# Classify one candidate: young checkouts are kept, non-checkouts go to the
# empty and orphan paths, and old registered linked checkouts are selected
# for their repository's git-tools run. Prints COMMON for selected and
# registered candidates via REPLY so the caller can sweep that repository.
_worktree_gc_classify() {
  local dir=$1 old=$2 common registered main_phys git_dir
  REPLY=
  # List young broken pointers as orphans, as the doctor's row promises,
  # without permitting age to authorize cleanup.
  if ((old == 0)) && _dr_worktree_orphan "$dir"; then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  if ((old == 0)); then
    _worktree_gc_record kept "$dir" "younger than $_WORKTREE_GC_AGE days"
    # Only a checkout names its repository: Git would walk up from a plain
    # directory to whatever repository encloses it.
    if [[ -e $dir/.git ]] && common=$(_worktree_gc_common_dir "$dir"); then
      REPLY=$common
    fi
    return 0
  fi
  if [[ ! -e $dir/.git ]]; then
    _worktree_gc_remove_empty "$dir"
    return 0
  fi
  if ! common=$(_worktree_gc_common_dir "$dir"); then
    _worktree_gc_remove_orphan "$dir"
    return 0
  fi
  if ! _worktree_gc_ensure_repo "$common" ||
    ! registered=$(_worktree_gc_cached_registered "$common" "$dir"); then
    _worktree_gc_record skipped "$dir" "orphan (not in any worktree list)"
    return 0
  fi
  REPLY=$common
  main_phys=$(_worktree_gc_cached_main "$common") || main_phys=
  if [[ -n $main_phys && $main_phys == "$dir" ]] ||
    { git_dir=$(_worktree_gc_git_dir "$dir") && [[ $git_dir == "$common" ]]; }; then
    _worktree_gc_record skipped "$dir" "main checkout"
    return 0
  fi
  if [[ -z $_WORKTREE_GC_CLEANUP ]]; then
    _worktree_gc_record skipped "$dir" "git-tools cleanup unavailable"
    return 0
  fi
  _WORKTREE_GC_SEL_COMMON+=("$common")
  _WORKTREE_GC_SEL_DIR+=("$dir")
  _WORKTREE_GC_SEL_REG+=("$registered")
  _WORKTREE_GC_SEL_BRANCH+=("$(git -C "$dir" symbolic-ref -q --short HEAD 2>/dev/null)")
  _WORKTREE_GC_SEL_DONE+=(0)
}

_worktree_gc_tally() {
  local mode=applied
  ((_WORKTREE_GC_APPLY == 0)) && mode="dry run"
  _worktree_gc_err "done: $_WORKTREE_GC_N_REMOVED removed, $_WORKTREE_GC_N_BRANCHES branches deleted, $_WORKTREE_GC_N_BRANCHES_KEPT branches kept, $_WORKTREE_GC_N_KEPT kept, $_WORKTREE_GC_N_SKIPPED skipped, $_WORKTREE_GC_N_FAILED failed ($mode)"
}

# Sweep entry point. Parses argv, enumerates candidates once, gates on age
# with a single find pass, classifies every candidate, then runs git-tools
# once per repository the sweep covers. Returns 0 on a clean sweep, 1 on
# usage or environment errors, 2 when any removal, branch deletion, or
# repository cleanup failed.
worktree_gc_main() {
  _WORKTREE_GC_APPLY=0
  _WORKTREE_GC_NO_FETCH=0
  _WORKTREE_GC_INCLUDE_CLOSED=0
  local age=$_WORKTREE_GC_AGE_DAYS_DEFAULT
  local saw_dry=0 saw_apply=0
  local -a extra_roots=()
  local arg root old_list dir old common
  local -a cands=() repos=()

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
      --include-closed) _WORKTREE_GC_INCLUDE_CLOSED=1 ;;
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
  _WORKTREE_GC_LIST_COMMONS=()
  _WORKTREE_GC_LIST_TEXTS=()
  _WORKTREE_GC_LIST_MAINS=()
  _WORKTREE_GC_MAP_COMMON=()
  _WORKTREE_GC_MAP_PHYS=()
  _WORKTREE_GC_MAP_REG=()
  _WORKTREE_GC_SEL_COMMON=()
  _WORKTREE_GC_SEL_DIR=()
  _WORKTREE_GC_SEL_REG=()
  _WORKTREE_GC_SEL_BRANCH=()
  _WORKTREE_GC_SEL_DONE=()
  _DR_WORKTREE_BASE_KEYS=()
  _DR_WORKTREE_BASE_REFS=()
  _WORKTREE_GC_N_REMOVED=0
  _WORKTREE_GC_N_BRANCHES=0
  _WORKTREE_GC_N_BRANCHES_KEPT=0
  _WORKTREE_GC_N_KEPT=0
  _WORKTREE_GC_N_SKIPPED=0
  _WORKTREE_GC_N_FAILED=0
  _worktree_gc_load_provider
  _worktree_gc_load_live
  _WORKTREE_GC_CWDS=()
  _WORKTREE_GC_CWDS_LOADED=0
  _WORKTREE_GC_CWDS_WARNED=0

  # Reuse the shared discovery scope with symlinked children suppressed;
  # physical-path discovery alone loses the provenance needed by rmdir.
  if ((${#extra_roots[@]} > 0)); then
    mapfile -t cands < <(_worktree_gc_candidates "${extra_roots[@]}")
    mapfile -t _WORKTREE_GC_DIRECT < <(_DR_WORKTREE_SKIP_SYMLINK_CANDIDATES=1 _worktree_gc_candidates "${extra_roots[@]}")
  else
    mapfile -t cands < <(_worktree_gc_candidates)
    mapfile -t _WORKTREE_GC_DIRECT < <(_DR_WORKTREE_SKIP_SYMLINK_CANDIDATES=1 _worktree_gc_candidates)
  fi

  # Every managed clone gets branch cleanup, whether or not it owns a
  # discovered checkout: most merged branches have no checkout left.
  while IFS= read -r common; do
    [[ -n $common ]] || continue
    common=$(_dr_worktree_physical "$common")
    [[ -n $common ]] && repos+=("$common")
  done < <(_dr_worktree_clone_commons)

  old_list=
  if ((${#cands[@]} > 0)); then
    # Age by the same Git activity signals the doctor reports, so the gc
    # never removes a checkout the doctor considers active. A path that
    # vanishes mid-pass reads young (kept) instead of failing the sweep.
    _dr_worktree_old_checkouts "$age" "${cands[@]}"
    old_list=$(printf '%s\n' ${_DR_WORKTREE_OLD[@]+"${_DR_WORKTREE_OLD[@]}"})
    for dir in "${cands[@]}"; do
      old=0
      case $'\n'"$old_list"$'\n' in
        *$'\n'"$dir"$'\n'*) old=1 ;;
      esac
      _worktree_gc_classify "$dir" "$old"
      [[ -n $REPLY ]] && repos+=("$REPLY")
    done
  fi

  if [[ -n $_WORKTREE_GC_CLEANUP ]]; then
    while IFS= read -r common; do
      [[ -n $common ]] || continue
      _worktree_gc_ensure_repo "$common" || continue
      _worktree_gc_sweep_repo "$common"
    done < <(printf '%s\n' ${repos[@]+"${repos[@]}"} | LC_ALL=C sort -u)
  fi

  # No `git worktree prune` afterwards: `worktree remove` already deletes the
  # removed checkout's admin entry, and a repo-wide prune would also drop the
  # entry of any checkout that was moved without repair, orphaning it. The
  # doctor reports truly prunable entries with the prune command.
  _worktree_gc_tally
  if ((_WORKTREE_GC_N_FAILED > 0)); then
    return 2
  fi
  return 0
}
