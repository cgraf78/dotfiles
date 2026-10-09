# shellcheck shell=bash
# worktree-gc.sh — multi-repo branch and worktree garbage collection.
#
# Library for the `dot-worktree-gc` entry point. Nothing here runs on
# source except loading the doctor enumeration and Shdeps helpers; the entry
# point calls `worktree_gc_main "$@"`, which also drops any
# repository-selecting Git variables the process inherited (GIT_DIR and the
# like, but not environment-injected configuration) and resolves the real
# Git behind the dotfiles launcher for its own probes. Needs Bash 4 (the
# entry point checks). Written for `set -u` with no `-e`; every fallible
# step handles its own failure explicitly.
#
# Division of labor: this file owns discovery (which repositories and
# checkouts the sweep covers), the age policy, and retiring directories no
# repository can speak for (empty leftovers and metadata-orphaned
# checkouts). Every per-repository decision -- which branches are proven
# merged and which linked checkouts may go -- belongs to
# `git cleanup-repo` from git-tools, driven through its porcelain records
# with --no-update-base, so the sweep never moves a local base and shares
# one set of merge proofs and removal gates with every other git-tools
# command. The git-tools root comes from GIT_TOOLS_ROOT when set (relative
# to the starting directory), otherwise from shdeps, which owns where the
# dependency lives (a ~/git development clone wins over the install root);
# it must report porcelain interface version 2 or newer.
# A repository with no selected checkout and at most its checked-out branch
# is not handed to git-tools at all: there is nothing to decide.
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
# Fields escape backslash, tab, and newline as \\, \t, and \n (git-tools'
# porcelain escaping), so a path holding one never breaks a record.
# Branch records cover every proven-merged local branch in a swept
# repository, not only branches of swept checkouts. A kept branch is listed
# only when its checkout was removed without it: retired on the checkout's
# own evidence, or kept by git-tools after the removal (checked out again,
# moved, or a checkout in flight); other kept branches are counted in the
# tally. A failed removal's reason carries git-tools' diagnostic when a
# diagnostic names that checkout. A grouping folder gets no record; a
# quarantine left by a failed orphan cleanup, a name holding a newline, and
# a checkout moved without repair are skipped with a record saying so.
# Cache entries pruned inside a checkout are reported on stderr, as are a
# clone with something to decide but remotes and no resolvable base branch,
# and (in one line) every repository whose pull request lookups failed.
# Diagnostics and the final tally (what a dry run would do, kept branches by
# reason) go to stderr; stdout carries records only. Exit 0: clean sweep;
# 1: usage or environment error (a --root that does not exist included);
# 2: a removal, branch deletion, or repository cleanup failed.
#
# Safety rules (all enforced, none optional):
# - never `rm -rf` and never `git worktree remove --force`, here or in
#   git-tools
# - checkouts younger than the age limit are never selected; branch
#   deletion needs a merge proof from git-tools (ancestry, exact content,
#   a landed tree, or a merged pull request), and a branch proven only by
#   ancestry must also be at least a day old by its reflog (or, once the
#   reflog expired, by its tip commit; a branch never logged is kept)
# - git-tools keeps a checkout that is the main or current one, locked,
#   dirty, holding untracked or ignored content other than tagged caches
#   and cleanupRepo.worktreePrunePath entries, holding a submodule
#   directory with content (populated, or files in an unpopulated one),
#   mid-operation or mid-checkout, a process's working directory, or
#   commits only its HEAD reflog or own refs hold that git-tools does not
#   excuse as replaced (unique-commits), and never forces a removal
# - checkout-only proofs keep the branch: a gone own-name upstream (never a
#   gone default branch, main/master/trunk or the remote's recorded HEAD,
#   which a rename removes, nor a branch git-tools keeps as unpublished or
#   pr-unknown), a closed pull request (--include-closed), or a superseded
#   Actions pin
# - metadata-orphaned checkouts require an exact merged-history snapshot;
#   removal uses a private quarantine and checked unlink/rmdir, never refs
# - old, empty directories with no known registration, directly under
#   roots, are removed with rmdir only; symlink targets and in-use dirs stay
# - a dry run fetches nothing itself (git-tools fetches its base without
#   moving remote-tracking refs), so previewing changes no refs
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

_WORKTREE_GC_DIR=${BASH_SOURCE[0]%/*}
if [[ -z ${_DR_WORKTREE_WARN_BYTES_DEFAULT:-} ]]; then
  # shellcheck source=doctor.d/lib/worktrees.sh
  . "$_WORKTREE_GC_DIR/doctor.d/lib/worktrees.sh" || return 1
fi

# shellcheck source=shdeps-assets.sh
. "$_WORKTREE_GC_DIR/shdeps-assets.sh" || return 1

# The minimum branch age, in days, git-tools requires of a branch proven
# merged only by ancestry (--min-age): a branch just created from the base
# and not yet committed to is an ancestor of the base too, and must survive
# the sweep. Rendered in the too-new reason, so both stay in step.
_WORKTREE_GC_MIN_AGE_DAYS=1

# The superseded Actions-pin proof is specific to cgraf78/actions consumers,
# so it stays here and reaches git-tools as an explicit retirement request.
# shellcheck source=worktree-gc-actions.sh
. "$_WORKTREE_GC_DIR/worktree-gc-actions.sh" || return 1

# --- shared sweep state (initialized by worktree_gc_main) ---
# The default age limit is the doctor's stale window, so the doctor never
# calls a checkout stale that the default sweep would still keep for age.
_WORKTREE_GC_AGE=$_DR_WORKTREE_STALE_DAYS
_WORKTREE_GC_APPLY=0
_WORKTREE_GC_NO_FETCH=0
_WORKTREE_GC_INCLUDE_CLOSED=0
_WORKTREE_GC_CLEANUP=
_WORKTREE_GC_FETCHED=$'\n'
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
# 1 while a selected checkout is removed but its branch has no record yet:
# git-tools can still keep that branch afterwards (see
# _worktree_gc_map_record), and the sweep promises to list it then.
_WORKTREE_GC_SEL_PENDING=()
# The aliases (keep-branch symref detail) of a selected checkout's branch.
_WORKTREE_GC_SEL_ALIAS=()
# Main checkouts Git cannot name: a ~/git/* or ~/.dotfiles-* clone made with
# --separate-git-dir, or whose .git is a symlink, lists its real Git
# directory as its main worktree, so the clone root found by discovery is
# remembered per common Git directory.
_WORKTREE_GC_ROOT_COMMONS=()
_WORKTREE_GC_ROOT_DIRS=()
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
# Of the removed and kept counts, those that are plain directories (empty
# leftovers) rather than checkouts, so the tally names them apart.
_WORKTREE_GC_N_REMOVED_DIRS=0
_WORKTREE_GC_N_KEPT_DIRS=0
# The repository a classified candidate names (_worktree_gc_classify).
_WORKTREE_GC_OWNER=
# Set when any record of the repository being swept says pull request
# lookups failed (pr-unknown).
_WORKTREE_GC_PR_UNKNOWN=0
# Repositories whose pull request lookups failed, noted together at the end:
# a globally broken gh setup would otherwise repeat one notice per clone.
_WORKTREE_GC_PR_UNKNOWN_REPOS=()
# Kept branches by short reason (_worktree_gc_kept_label), for the tally.
_WORKTREE_GC_KEPT_LABELS=()
_WORKTREE_GC_KEPT_COUNTS=()

_worktree_gc_err() { printf 'dot-worktree-gc: %s\n' "$*" >&2; }

# The heredoc expands only the default age (single-sourced on the doctor's
# stale window); backticks in the text are escaped.
_worktree_gc_usage() {
  cat >&2 <<USAGE
usage: dot-worktree-gc [--older-than N[d]] [--dry-run|--apply] [--no-fetch] [--include-closed]
                       [--root DIR]...
  Delete proven-merged local branches in every repo the sweep covers, and
  remove worktrees with no Git activity for over N days
  (default $_DR_WORKTREE_STALE_DAYS) whose work landed or was superseded.
  Repos covered: ~/.dotfiles, every ~/git/* and ~/.dotfiles-* clone, and the
  owner of every discovered checkout.
  Checkouts swept: ~/.worktrees, ~/git/worktrees, ~/worktrees and
  ~/git/.worktrees (one grouping folder deep; a ~/git/worktrees that is
  itself a clone is swept as that clone instead, and a clone at
  ~/git/.worktrees is not swept), the .worktrees of every ~/git/* and
  ~/.dotfiles-* clone, and checkouts the base dotfiles repo registered
  anywhere. A linked worktree parked under ~/git (or as a ~/.dotfiles-*
  root) is not treated as a clone; its own .worktrees is swept only when
  its repository is ~/.dotfiles or a ~/git/* or ~/.dotfiles-* clone, so
  parking alone never brings a repository into the sweep.
  Per-repo decisions come from \`git cleanup-repo\` (git-tools): merge
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
  --no-fetch proves against local refs without touching the network. A dry
  run moves no refs: git-tools fetches the remote base without updating
  remote-tracking refs.
  --include-closed also removes checkouts belonging to closed unmerged PRs,
  retaining their branches. An open PR keeps a branch, and its checkout,
  that no local proof covers.
  Records print on stdout; diagnostics and the tally go to stderr.
USAGE
}

# Print the day count for an age argument (N, or N with a d suffix), or fail.
# Read as decimal whatever the leading zeros (Bash arithmetic would take 08
# for bad octal), and refuse zero in any spelling and absurd lengths that
# would overflow.
_worktree_gc_parse_age() {
  local raw=${1:-} num
  case $raw in
    *d) num=${raw%d} ;;
    *) num=$raw ;;
  esac
  case $num in
    '' | *[!0-9]*) return 1 ;;
  esac
  ((${#num} <= 9)) || return 1
  num=$((10#$num))
  ((num > 0)) || return 1
  printf '%s\n' "$num"
}

# Report "COUNT NOUN" via REPLY, with the singular noun only for 1.
_worktree_gc_plural() {
  if (($1 == 1)); then
    REPLY="$1 $2"
  else
    REPLY="$1 $3"
  fi
}

# Print one stdout record, its fields escaped (_dr_worktree_escape: a path
# holding a tab or newline cannot break one record per line), and
# tally it. Branch records share the shape but tally separately from their
# worktree.
_worktree_gc_record() {
  local verb=$1 path=$2 reason
  shift 2 || return 1
  _dr_worktree_escape "$*"
  reason=$_DR_WORKTREE_ESCAPED
  _dr_worktree_escape "$path"
  printf '%s\t%s\t%s\n' "$verb" "$_DR_WORKTREE_ESCAPED" "$reason"
  case $verb in
    would-remove | removed)
      _WORKTREE_GC_N_REMOVED=$((_WORKTREE_GC_N_REMOVED + 1))
      ;;
    would-remove-branch | removed-branch)
      _WORKTREE_GC_N_BRANCHES=$((_WORKTREE_GC_N_BRANCHES + 1))
      ;;
    would-skip-branch | skipped-branch) ;; # see _worktree_gc_count_kept
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
  common=$(_dr_git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 1
  [[ -n $common ]] || return 1
  case $common in
    /*) printf '%s\n' "$common" ;;
    *)
      _dr_worktree_resolve_line "$dir/$common" || return 1
      printf '%s\n' "$_DR_WORKTREE_RESOLVED"
      ;;
  esac
}

# Print the absolute git dir (not the common dir) for a checkout, or
# fail. A main checkout's git dir IS the common dir; a linked
# checkout's points into the common worktrees area.
_worktree_gc_git_dir() {
  local dir=$1 gitdir
  gitdir=$(_dr_git -C "$dir" rev-parse --git-dir 2>/dev/null) || return 1
  [[ -n $gitdir ]] || return 1
  case $gitdir in
    /*) printf '%s\n' "$gitdir" ;;
    *)
      _dr_worktree_resolve_line "$dir/$gitdir" || return 1
      printf '%s\n' "$_DR_WORKTREE_RESOLVED"
      ;;
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
  wt_list=$(_dr_git --git-dir="$common" worktree list --porcelain 2>/dev/null) || return 1
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

# Report via REPLY the remote base ref (short form, e.g. origin/main) of the
# repository with common Git directory COMMON, run from REPO_DIR (see
# _worktree_gc_repo_dir; COMMON itself when it has no checkout), or fail.
# Every caller resolves through here so the sweep, the orphan proof, and its
# fetch agree on one base. A directory without its own .git -- the base
# client's HOME, or a bare Git directory -- names COMMON through GIT_DIR:
# otherwise Git would find no repository there, or only through a PATH
# launcher (the dotfiles `git` maps directories under HOME without a work
# tree to the base client) that may answer for the wrong one.
_worktree_gc_base_ref() {
  local repo_dir=$1 common=$2
  if [[ -e $repo_dir/.git ]]; then
    _dr_worktree_base_ref_ensure "$repo_dir"
  else
    GIT_DIR=$common _dr_worktree_base_ref_ensure "$repo_dir"
  fi
}

# Fetch the base branch for one repo, at most once per sweep, and only when
# applying: a dry run proves against the refs it finds, so previewing never
# moves remote-tracking refs. Never fails the sweep: a fetch failure degrades
# to local refs with a notice. Proving against stale refs only withholds
# proof (fewer removals), never fabricates it.
_worktree_gc_fetch_base() {
  local dir=$1 common=$2
  local ref remote branch err
  ((_WORKTREE_GC_NO_FETCH == 0 && _WORKTREE_GC_APPLY == 1)) || return 0
  case $'\n'"$_WORKTREE_GC_FETCHED"$'\n' in
    *$'\n'"$common"$'\n'*) return 0 ;;
  esac
  _WORKTREE_GC_FETCHED+="$common"$'\n'
  _worktree_gc_base_ref "$dir" "$common" || return 0
  ref=$REPLY
  remote=${ref%%/*}
  branch=${ref#*/}
  [[ -n $remote && -n $branch && $branch != "$ref" ]] || return 0
  if err=$(_worktree_gc_batch _dr_git --git-dir="$common" fetch --quiet --no-tags \
    "$remote" "$branch" 2>&1); then
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

# Reread registrations and process working directories right before a
# removal. A dry run reads the state loaded once per sweep (registrations at
# the start, working directories on first use): rescanning every admin area
# and /proc per empty or orphaned candidate made a preview of hundreds of
# leftovers crawl, and a preview removes nothing. Applying rereads both
# before each removal, so a checkout registered or entered during a long
# sweep is still caught. Must run in the main shell.
_worktree_gc_refresh_gates() {
  ((_WORKTREE_GC_APPLY == 1)) || return 0
  _worktree_gc_load_live
  _worktree_gc_load_cwds
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
  # A missing .git file does not imply that a known owner forgot this
  # checkout. Unknown owners cannot be recovered from an empty directory
  # alone, so the record reports absence of known registration, never a
  # global Git proof.
  _worktree_gc_refresh_gates
  if _worktree_gc_registered "$dir"; then
    _worktree_gc_record skipped "$dir" "registered worktree, missing .git"
    return 0
  fi
  # Even an empty directory may be an idle shell's working directory.
  if _worktree_gc_in_use "$dir"; then
    _worktree_gc_record skipped "$dir" "in use (a process's working directory)"
    return 0
  fi
  if ((_WORKTREE_GC_APPLY == 0)); then
    _worktree_gc_record would-remove "$dir" "empty directory, no known registration"
    _WORKTREE_GC_N_REMOVED_DIRS=$((_WORKTREE_GC_N_REMOVED_DIRS + 1))
  elif err=$(rmdir -- "$dir" 2>&1); then
    _worktree_gc_record removed "$dir" "empty directory, no known registration"
    _WORKTREE_GC_N_REMOVED_DIRS=$((_WORKTREE_GC_N_REMOVED_DIRS + 1))
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
  # The helper's Git reads use the Git the sweep resolved (DOT_WORKTREE_GC_GIT),
  # not the PATH launcher.
  local helper=$_WORKTREE_GC_DIR/worktree-gc-orphans.py
  for direct in ${_WORKTREE_GC_DIRECT[@]+"${_WORKTREE_GC_DIRECT[@]}"}; do
    [[ $direct != "$dir" ]] || found=1
  done
  if ((found == 0)) || ! command -v python3 >/dev/null 2>&1 || [[ ! -f $helper ]]; then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  common=$(DOT_WORKTREE_GC_GIT=${_DR_WORKTREE_GIT:-git} python3 "$helper" owner "$dir" 2>/dev/null) || {
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  }
  _worktree_gc_refresh_gates
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
  if _worktree_gc_in_use "$dir"; then
    _worktree_gc_record skipped "$dir" "in use (a process's working directory)"
    return 0
  fi
  # Prove against the same base the repository's own sweep uses.
  repo_dir=$common
  _worktree_gc_ensure_repo "$common" && _worktree_gc_repo_dir "$common" &&
    repo_dir=$REPLY
  _worktree_gc_fetch_base "$repo_dir" "$common"
  if ! _worktree_gc_base_ref "$repo_dir" "$common"; then
    _worktree_gc_record skipped "$dir" "orphaned checkout has no base ref"
    return 0
  fi
  base_ref=$REPLY
  base_oid=$(_dr_git --git-dir="$common" rev-parse --verify "$base_ref^{commit}" 2>/dev/null) || {
    _worktree_gc_record skipped "$dir" "orphaned checkout has no base commit"
    return 0
  }
  err=$(mktemp) || {
    _worktree_gc_record failed "$dir" "cannot prepare orphan inspection"
    return 0
  }
  if ((_WORKTREE_GC_APPLY == 0)); then
    oid=$(DOT_WORKTREE_GC_GIT=${_DR_WORKTREE_GIT:-git} python3 "$helper" prove "$dir" "$base_oid" 2>"$err")
    status=$?
  else
    oid=$(DOT_WORKTREE_GC_GIT=${_DR_WORKTREE_GIT:-git} python3 "$helper" remove "$dir" "$base_oid" 2>"$err")
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

# The oldest `git cleanup-repo --interface-version` the sweep can drive. It
# names the porcelain contract as a whole (options, records, codes, exit
# statuses) and grows whenever that contract gains or changes something;
# the contract arrived over several git-tools changes, so no single
# option's presence can stand in for it. Only a bare integer counts. 1:
# exit status 3; pr-unknown, closed-pr, symref, and submodule codes;
# following a renamed remote default; symref and ignored-file safety. 2:
# unpublished and unique-commits codes (a checkout whose HEAD reflog or own
# refs hold commits nothing else reaches is kept, which the age gate alone
# cannot see); dating an expired reflog by the tip commit; submodule also
# covering files in an unpopulated submodule directory. Required, not
# merely understood: an older git-tools would remove such checkouts.
_WORKTREE_GC_INTERFACE_MIN=2

# Locate the git-tools cleanup provider. GIT_TOOLS_ROOT names a root
# explicitly (tests and provider development). Otherwise ask shdeps, which
# owns the dependency's location: for repository installs a development clone
# under ~/git wins over the install root, and a host whose profile does not
# declare git-tools gets no answer even if an old install lingers. Anything
# missing or too old leaves _WORKTREE_GC_CLEANUP empty with one notice; the
# sweep still handles empty and orphaned directories, which need no
# repository decision. git-tools is not part of the base profile: the
# dotfiles-dev overlay declares it, so the notices point there.
_worktree_gc_load_provider() {
  local root bin version
  local hint="git-tools comes from the dev profile: run 'dot update' with it enabled, or set GIT_TOOLS_ROOT"
  _WORKTREE_GC_CLEANUP=
  if [[ -n ${GIT_TOOLS_ROOT:-} ]]; then
    root=$GIT_TOOLS_ROOT
    # Every repository's run starts in that repository's directory, so a
    # relative root must be pinned to where the sweep started.
    [[ $root == /* ]] || root=$PWD/$root
    bin=$root/bin/git-cleanup-repo
  else
    bin=$(dot_shdeps_dep_file cgraf78/git-tools bin/git-cleanup-repo 2>/dev/null) || bin=
    if [[ -z $bin ]]; then
      _worktree_gc_err "git-tools not found: shdeps did not resolve cgraf78/git-tools; branch and checkout cleanup skipped ($hint)"
      return 0
    fi
    root=${bin%/bin/git-cleanup-repo}
  fi
  if [[ ! -x $bin ]]; then
    _worktree_gc_err "git-tools not found at $root; branch and checkout cleanup skipped ($hint)"
    return 0
  fi
  # A git-tools without the flag rejects it as an unknown option (or, older
  # still, prints something that is not a version); either way the answer is
  # not an integer and the provider is treated as too old. No repository is
  # needed, and stdin is closed so nothing can wait on the terminal.
  version=$("$bin" --interface-version 2>/dev/null </dev/null) || version=
  case $version in
    '' | *[!0-9]*) version=0 ;;
  esac
  if ((10#$version < _WORKTREE_GC_INTERFACE_MIN)); then
    _worktree_gc_err "git-tools at $root predates porcelain cleanup interface $_WORKTREE_GC_INTERFACE_MIN; branch and checkout cleanup skipped ($hint)"
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
    # Proven only by ancestry, which a branch fresh off the base also passes.
    # The detail is when it was last created or moved (its newest reflog
    # entry, or its tip's commit time once the reflog expired; the epoch
    # alone does not say which), empty when its age is unknown (a branch
    # never logged, typically).
    too-new)
      if [[ -z $detail ]]; then
        printf 'merged by ancestry only, and its age is unknown (a branch never logged, say)'
      else
        _worktree_gc_plural "$_WORKTREE_GC_MIN_AGE_DAYS" day days
        printf 'merged by ancestry only, but its reflog or tip commit is under %s old' "$REPLY"
      fi
      ;;
    current-worktree) printf 'current checkout' ;;
    main-worktree) printf 'main checkout' ;;
    locked) printf 'locked' ;;
    dirty) printf 'dirty (uncommitted changes)' ;;
    hidden) printf 'untracked or ignored local content' ;;
    operation) printf 'active %s' "$detail" ;;
    # A populated submodule, or files in an unpopulated submodule's
    # directory, which status does not show and a removal would delete.
    submodule) printf 'holds a submodule directory with content (Git cannot remove it safely)' ;;
    # A gone upstream whose tip GitHub never saw is unpushed work, not a
    # landing.
    unpublished) printf 'upstream gone, but GitHub never saw its tip (unpushed commits)' ;;
    # The checkout's HEAD reflog (either side of any entry) or its own
    # refs/worktree, refs/bisect, or refs/rewritten hold a commit no branch,
    # tag, remote branch, or the stash reaches and none of git-tools'
    # exceptions (an amended or rebased-away commit, say) excuses; removing
    # the checkout would drop that history. The detail is one such commit.
    unique-commits)
      printf "commits only this worktree's history or own refs hold"
      [[ -z $detail ]] || printf ' (such as %s)' "$detail"
      ;;
    # A symbolic ref under refs/heads (master -> main, say) points at the
    # branch; on keep-branch the detail is the aliases' short names,
    # space-separated (keep-worktree carries the branch instead; see
    # _worktree_gc_map_record).
    symref)
      if [[ $detail == *' '* ]]; then
        printf 'aliases (%s) point at it' "$detail"
      else
        printf 'an alias (%s) points at it' "$detail"
      fi
      ;;
    in-use) printf "in use (a process's working directory)" ;;
    checkout-in-flight) printf 'a Git command is running there' ;;
    missing) printf 'directory gone' ;;
    not-linked) printf 'not a linked worktree' ;;
    unreachable-head) printf 'detached HEAD on no branch' ;;
    branch-changed) printf 'changed during cleanup' ;;
    # Git or the process view could not be read, or (the common case) the
    # repository keeps the checkout's HEAD reflog in reftable, where
    # git-tools cannot look for commits only that history holds.
    uninspectable) printf 'cannot inspect (unreadable Git state, or a HEAD reflog in reftable)' ;;
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

# Succeed when COMMON is the base client's separate Git directory, whose
# work tree is HOME.
_worktree_gc_is_base() {
  local common=$1 base
  _dr_worktree_base_gitdir
  base=$REPLY
  [[ -n $base && -d $base && $common -ef $base ]]
}

# Run git-tools cleanup for one repository with the given arguments, filling
# _WORKTREE_GC_OUT with its records, _WORKTREE_GC_ERRTEXT with every line of
# its stderr, and _WORKTREE_GC_ERRLINE with the last one, which is the fatal
# one on failure (earlier lines are notes, such as a followed default
# branch). Stderr is kept whatever the exit status: in porcelain mode a
# failed removal still exits 0, and only Git's own refusal on stderr says
# why. The base client's work tree is HOME, so it runs from HOME with
# GIT_DIR and GIT_WORK_TREE naming both, as the `git` launcher does: a fresh
# client records HOME in core.worktree, but a legacy bare client
# (core.bare=true) only gets a work tree from the environment, and Git alone
# would call it bare. Any other repository runs from its main checkout.
# Credential prompts are off (_worktree_gc_batch), so a remote that wants
# credentials reads as unreachable and falls back to local refs. Returns the
# provider's status, or 125 when the repository has no checkout to run from.
_worktree_gc_run_cleanup() {
  local common=$1 dir err line status=0
  shift
  _WORKTREE_GC_OUT=
  _WORKTREE_GC_ERRTEXT=
  _WORKTREE_GC_ERRLINE=
  _worktree_gc_repo_dir "$common" || return 125
  dir=$REPLY
  err=$(mktemp) || return 1
  if _worktree_gc_is_base "$common"; then
    _WORKTREE_GC_OUT=$(cd -- "$dir" &&
      GIT_DIR=$common GIT_WORK_TREE=$dir \
        _worktree_gc_batch "$_WORKTREE_GC_CLEANUP" "$@" 2>"$err") || status=$?
  else
    _WORKTREE_GC_OUT=$(cd -- "$dir" &&
      _worktree_gc_batch "$_WORKTREE_GC_CLEANUP" "$@" 2>"$err") || status=$?
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    [[ -n $line ]] || continue
    _WORKTREE_GC_ERRTEXT+=$line$'\n'
    _WORKTREE_GC_ERRLINE=$line
  done <"$err"
  rm -f -- "$err"
  return "$status"
}

# Report via REPLY the provider diagnostic that explains a failed removal of
# the checkout registered at PATH: the last stderr line naming it, quoted as
# Git's own refusal does ('PATH') or as the directory of an entry inside it
# (PATH/...), else nothing. Display only. No line of a run that failed
# several removals, or added notes, may be pinned on a checkout it does not
# name, and a sibling such as PATH-2 must not match.
_worktree_gc_failure_cause() {
  local path=$1 line
  REPLY=
  while IFS= read -r line; do
    [[ $line == *"'$path'"* || $line == *"$path/"* ]] && REPLY=$line
  done <<<"$_WORKTREE_GC_ERRTEXT"
  return 0
}

# Report via REPLY the directory to run Git for a repository from: HOME for
# the base client, whose work tree it is, else its main checkout. A clone
# made with --separate-git-dir, or whose .git is a symlink, lists its real
# Git directory as the main worktree, so discovery's clone root stands in
# for it. Fails when the repository has no checkout, which includes any bare
# repository other than the base client: one cloned bare into foo/.git looks
# like foo's checkout by path, but git-tools refuses to run there.
_worktree_gc_repo_dir() {
  local common=$1 main i
  if _worktree_gc_is_base "$common"; then
    REPLY=$HOME
    return 0
  fi
  REPLY=
  ! _dr_worktree_bare "$common" || return 1
  main=$(_worktree_gc_cached_main "$common") || main=
  if [[ -z $main || ! -e $main/.git ]]; then
    main=
    for ((i = 0; i < ${#_WORKTREE_GC_ROOT_COMMONS[@]}; i++)); do
      if [[ ${_WORKTREE_GC_ROOT_COMMONS[$i]} == "$common" ]]; then
        main=${_WORKTREE_GC_ROOT_DIRS[$i]}
        break
      fi
    done
    [[ -n $main && -e $main/.git ]] || return 1
  fi
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

# Print the branch record for a branch a removed checkout leaves behind.
# Those are listed, unlike the many unproven branches the tally only counts:
# the checkout's own record no longer speaks for its branch.
_worktree_gc_record_kept_branch() {
  local branch=$1 reason=$2 code=$3
  _worktree_gc_count_kept "$code"
  if ((_WORKTREE_GC_APPLY == 1)); then
    _worktree_gc_record skipped-branch "$branch" "$reason"
  else
    _worktree_gc_record would-skip-branch "$branch" "$reason"
  fi
}

# Render one git-tools record for repository COMMON as sweep records.
_worktree_gc_map_record() {
  local common=$1 event=$2 subject=$3 code=$4 detail=$5 reason idx dir
  reason=$(_worktree_gc_reason "$code" "$detail")
  # A failed pull request lookup is a repository-wide condition (gh is not
  # authenticated, or the API is down): _worktree_gc_sweep_repo collects the
  # repository, and the tally notes every one in a single line rather than
  # per branch.
  [[ $code != pr-unknown ]] || _WORKTREE_GC_PR_UNKNOWN=1
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
      # record, unless git-tools removed the checkout and only then kept the
      # branch (checked out again, moved, or a checkout in flight by the time
      # it came to delete it): that branch is listed like any other a retired
      # checkout leaves behind. Any other kept branch is counted, not listed,
      # since a repository can hold hundreds of unproven branches.
      for ((idx = 0; idx < ${#_WORKTREE_GC_SEL_BRANCH[@]}; idx++)); do
        [[ ${_WORKTREE_GC_SEL_COMMON[$idx]} == "$common" &&
          ${_WORKTREE_GC_SEL_BRANCH[$idx]} == "$subject" ]] || continue
        if [[ ${_WORKTREE_GC_SEL_PENDING[$idx]} == 1 ]]; then
          _WORKTREE_GC_SEL_PENDING[idx]=0
          _worktree_gc_record_kept_branch "$subject" "$reason" "$code"
        fi
        # The keep-worktree record that follows names only the branch; keep
        # the alias names this record carries for it.
        [[ $code != symref ]] || _WORKTREE_GC_SEL_ALIAS[idx]=$detail
        return 0
      done
      _worktree_gc_count_kept "$code"
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
              # The record's detail is only the path; the cause is on stderr.
              _worktree_gc_failure_cause "$subject"
              _worktree_gc_record failed "$dir" "$reason${REPLY:+: $REPLY}"
              ;;
            # The reason text above is written for a retired checkout; one
            # kept for its closed PR stays only because --include-closed was
            # not given.
            closed-pr)
              _worktree_gc_record skipped "$dir" "closed unmerged PR; --include-closed retires it"
              ;;
            # Its detail is the branch; the aliases came with the branch's
            # own keep-branch record, when there was one.
            symref)
              if [[ -n ${_WORKTREE_GC_SEL_ALIAS[idx]:-} ]]; then
                reason=$(_worktree_gc_reason symref "${_WORKTREE_GC_SEL_ALIAS[idx]}")
                _worktree_gc_record skipped "$dir" "its branch is kept: $reason"
              else
                _worktree_gc_record skipped "$dir" "a branch alias points at its branch"
              fi
              ;;
            *) _worktree_gc_record skipped "$dir" "$reason" ;;
          esac
          return 0
          ;;
      esac
      # A checkout retired on its own evidence keeps its branch; say so,
      # matching the branch records of earlier sweeps. One removed with a
      # proven branch waits for that branch's own record (see keep-branch).
      case $code in
        upstream-gone | closed-pr | requested)
          [[ -z $detail ]] || _worktree_gc_record_kept_branch "$detail" "$reason" "$code"
          ;;
        *) [[ -z $detail ]] || _WORKTREE_GC_SEL_PENDING[idx]=1 ;;
      esac
      ;;
  esac
  return 0
}

# Print REMOTE's HEAD symref as a short <remote>/<branch> name, or nothing.
# --git-dir reads it straight from the repository, so the base client's
# HOME (no .git of its own) needs no special case. The refs/remotes/ prefix
# is stripped by hand: `--short` turns to remotes/<remote>/<branch> when a
# local branch or tag shares the short name, and would never match.
_worktree_gc_head_symref() {
  local common=$1 remote=$2 ref
  ref=$(_dr_git --git-dir="$common" symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null) ||
    return 0
  [[ $ref != refs/remotes/* ]] || printf '%s\n' "${ref#refs/remotes/}"
  return 0
}

# Succeed when the sweep selected any old checkout of repository COMMON.
_worktree_gc_selects() {
  local common=$1 i
  for ((i = 0; i < ${#_WORKTREE_GC_SEL_COMMON[@]}; i++)); do
    [[ ${_WORKTREE_GC_SEL_COMMON[$i]} != "$common" ]] || return 0
  done
  return 1
}

# Sweep one repository: delete its proven-merged branches and decide every
# selected old checkout it owns, in one git-tools run.
_worktree_gc_sweep_repo() {
  local common=$1 repo_dir base_ref remote i dir reg tip base_oid status heads
  local event subject code detail rec
  local -a args=(--no-update-base --porcelain --min-age "$_WORKTREE_GC_MIN_AGE_DAYS")
  local -a selections=() offline=()

  # Without a selected checkout, a repository holding no local branch, or
  # only the one its main checkout has out (which git-tools always keeps),
  # leaves nothing to decide: skip the provider and its network round trips,
  # which most idle clones would otherwise pay on every sweep. --git-dir
  # names the repository, so the base client reads the same way; the common
  # directory's HEAD is the main checkout's (the base client's own).
  if ! _worktree_gc_selects "$common" &&
    heads=$(_dr_git --git-dir="$common" for-each-ref --count=2 \
      --format='%(HEAD)%(refname)' refs/heads/ 2>/dev/null) &&
    [[ -z $heads || ($heads != *$'\n'* && $heads == '*'*) ]]; then
    return 0
  fi
  # A bare repository, or one whose main checkout is gone, has nowhere to run
  # cleanup from; its selected checkouts stay.
  if ! _worktree_gc_repo_dir "$common"; then
    _worktree_gc_skip_selected "$common" "repository has no main checkout"
    return 0
  fi
  repo_dir=$REPLY
  base_ref=
  _worktree_gc_base_ref "$repo_dir" "$common" && base_ref=$REPLY
  # Without a resolvable remote base there is nothing to prove against.
  if [[ -z $base_ref ]]; then
    _worktree_gc_skip_selected "$common" "no remote base branch"
    # A repository with remotes would otherwise be left alone silently:
    # several remotes, none named origin; a remote name with a slash; or no
    # origin/HEAD and a default other than main, master, or trunk. Without
    # remotes there is nothing to prove against, which needs no notice.
    if [[ -n $(_dr_git --git-dir="$common" remote 2>/dev/null) ]]; then
      _worktree_gc_err "$common: no remote base branch (wants origin/HEAD, origin/main, origin/master, origin/trunk, or a sole remote's HEAD); branch and checkout cleanup skipped"
    fi
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
  if [[ $(_worktree_gc_head_symref "$common" "$remote") != "$base_ref" ]]; then
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
    tip=$(_dr_git -C "$dir" rev-parse --verify -q HEAD 2>/dev/null) || tip=
    base_oid=$(_dr_git -C "$dir" rev-parse --verify -q "$base_ref^{commit}" 2>/dev/null) || base_oid=
    if [[ -n $tip && -n $base_oid ]] &&
      _dr_git -C "$dir" symbolic-ref -q HEAD >/dev/null 2>&1 &&
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
  _WORKTREE_GC_PR_UNKNOWN=0
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
  # Each branch kept as pr-unknown reads like any unproven one; note the
  # repository so the sweep can say once why merged-PR proofs were missing,
  # and a broken gh setup does not pass for repositories with nothing merged.
  ((_WORKTREE_GC_PR_UNKNOWN == 0)) || _WORKTREE_GC_PR_UNKNOWN_REPOS+=("$common")
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
# for their repository's git-tools run. Sets _WORKTREE_GC_OWNER to COMMON for
# selected and registered candidates (empty otherwise) so the caller can
# sweep that repository: a dedicated variable, since the record and plural
# helpers called on the way use REPLY.
_worktree_gc_classify() {
  local dir=$1 old=$2 common registered main_phys git_dir branch
  _WORKTREE_GC_OWNER=
  # List young broken pointers as orphans, as the doctor's row promises,
  # without permitting age to authorize cleanup.
  if ((old == 0)) && _dr_worktree_orphan "$dir"; then
    _worktree_gc_record skipped "$dir" "broken git pointer"
    return 0
  fi
  if ((old == 0)); then
    _worktree_gc_plural "$_WORKTREE_GC_AGE" day days
    _worktree_gc_record kept "$dir" "younger than $REPLY"
    [[ -e $dir/.git ]] || _WORKTREE_GC_N_KEPT_DIRS=$((_WORKTREE_GC_N_KEPT_DIRS + 1))
    # Only a checkout names its repository: Git would walk up from a plain
    # directory to whatever repository encloses it.
    if [[ -e $dir/.git ]] && common=$(_worktree_gc_common_dir "$dir"); then
      _WORKTREE_GC_OWNER=$common
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
    # A checkout moved without `git worktree repair` still points at a live
    # admin entry that names its old path: repairable, not orphaned (the
    # doctor's moved row says the same).
    if _dr_worktree_moved "$dir"; then
      _worktree_gc_record skipped "$dir" "moved worktree not repaired (registered at $REPLY): run 'git worktree repair' in it"
    else
      _worktree_gc_record skipped "$dir" "orphan (not in any worktree list)"
    fi
    return 0
  fi
  _WORKTREE_GC_OWNER=$common
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
  # The full ref, stripped by hand: `--short` answers heads/<name> when a tag
  # shares the branch name, which would never match git-tools' records.
  branch=$(_dr_git -C "$dir" symbolic-ref -q HEAD 2>/dev/null) || branch=
  [[ $branch == refs/heads/* ]] || branch=
  _WORKTREE_GC_SEL_BRANCH+=("${branch#refs/heads/}")
  _WORKTREE_GC_SEL_DONE+=(0)
  _WORKTREE_GC_SEL_PENDING+=(0)
  _WORKTREE_GC_SEL_ALIAS+=("")
}

# Drop grouping folders from the candidates in `cands` (the caller's array,
# by dynamic scope). A grouping folder (no .git of its own, holding other
# candidates) is enumerated only so the doctor can measure its bytes; it is
# neither a checkout nor a leftover, so it gets no record and no tally, as
# the doctor leaves it out of its counts. Once its checkouts are gone it is
# an empty leftover like any other. Every ancestor of every candidate is
# marked once, stopping at the first one already marked, so thousands of
# candidates stay linear instead of each scanning the whole list.
_worktree_gc_drop_groupings() {
  local dir parent
  local -A has_child=()
  local -a kept=()
  for dir in ${cands[@]+"${cands[@]}"}; do
    # A path without a slash has no parent here; stripping would leave the
    # path itself and mark it a grouping folder of its own.
    [[ $dir == */* ]] || continue
    parent=${dir%/*}
    while [[ -n $parent && -z ${has_child["$parent"]+x} ]]; do
      has_child["$parent"]=1
      parent=${parent%/*}
    done
  done
  for dir in ${cands[@]+"${cands[@]}"}; do
    [[ ! -e $dir/.git && -n ${has_child["$dir"]+x} ]] || kept+=("$dir")
  done
  cands=(${kept[@]+"${kept[@]}"})
}

# Unset the repository-selecting Git variables the sweep inherited. A Git
# alias or hook, or the dotfiles `git` launcher, can export one repository's
# GIT_DIR, GIT_WORK_TREE, GIT_INDEX_FILE, and the like; every probe here
# names its repository with -C or --git-dir, which those variables override,
# so the whole sweep would collapse onto that one repository. Git lists its
# repository-local variables itself (--local-env-vars); the injected
# configuration among them (GIT_CONFIG_PARAMETERS, and GIT_CONFIG_COUNT with
# its KEY_n/VALUE_n pairs, which Git does not list) stays. It selects no
# repository, and a host can
# inject settings the sweep needs that way, such as url.<base>.insteadOf
# rewrites without which git-tools cannot reach a remote. (git-tools clears
# the full list only around its per-worktree reads, never around fetching.)
# The base client's run sets its own GIT_DIR and GIT_WORK_TREE. The sweep is
# its own process, so nothing outside it loses them.
_worktree_gc_drop_local_env() {
  local name
  while IFS= read -r name; do
    case $name in
      # GIT_CONFIG (one config file for every repository) is dropped:
      # git-tools' own `git config --local` reads would fail under it.
      '' | GIT_CONFIG_PARAMETERS | GIT_CONFIG_COUNT) ;;
      *) unset "$name" ;;
    esac
  done < <(git rev-parse --local-env-vars 2>/dev/null)
  return 0
}

# Report via REPLY a short label for a kept branch's reason code, for the
# tally's breakdown (the records carry the full reason).
_worktree_gc_kept_label() {
  case $1 in
    merge-unproven) REPLY='merge unproven' ;;
    open-pr) REPLY='open PR' ;;
    closed-pr) REPLY='closed PR' ;;
    pr-unknown) REPLY='PR lookup failed' ;;
    too-new) REPLY='too new' ;;
    upstream-gone) REPLY='upstream gone' ;;
    requested) REPLY='Actions pin superseded' ;;
    symref) REPLY='alias' ;;
    unpublished) REPLY='unpublished' ;;
    unique-commits) REPLY='unique commits' ;;
    current-worktree | main-worktree | checked-out) REPLY='checked out' ;;
    *) REPLY=$(_worktree_gc_reason "$1" "") ;;
  esac
}

# Count one kept branch under its reason code's label.
_worktree_gc_count_kept() {
  local i
  _WORKTREE_GC_N_BRANCHES_KEPT=$((_WORKTREE_GC_N_BRANCHES_KEPT + 1))
  _worktree_gc_kept_label "$1"
  for ((i = 0; i < ${#_WORKTREE_GC_KEPT_LABELS[@]}; i++)); do
    if [[ ${_WORKTREE_GC_KEPT_LABELS[$i]} == "$REPLY" ]]; then
      _WORKTREE_GC_KEPT_COUNTS[i]=$((_WORKTREE_GC_KEPT_COUNTS[i] + 1))
      return 0
    fi
  done
  _WORKTREE_GC_KEPT_LABELS+=("$REPLY")
  _WORKTREE_GC_KEPT_COUNTS+=(1)
}

# Print the end-of-sweep notes and tally on stderr. Failed pull request
# lookups are one note listing every repository. The tally says what a dry
# run would do, counts checkouts (young ones kept for age; others skipped
# with a reason in their record) apart from branches, and breaks kept
# branches down by reason.
_worktree_gc_tally() {
  local removed deleted kept young breakdown='' i
  if ((${#_WORKTREE_GC_PR_UNKNOWN_REPOS[@]} == 1)); then
    _worktree_gc_err "${_WORKTREE_GC_PR_UNKNOWN_REPOS[0]}: pull request lookups failed (check 'gh auth status'); merged-PR evidence was not used"
  elif ((${#_WORKTREE_GC_PR_UNKNOWN_REPOS[@]} > 1)); then
    _worktree_gc_err "pull request lookups failed in ${#_WORKTREE_GC_PR_UNKNOWN_REPOS[@]} repositories (check 'gh auth status'); merged-PR evidence was not used: ${_WORKTREE_GC_PR_UNKNOWN_REPOS[*]}"
  fi
  for ((i = 0; i < ${#_WORKTREE_GC_KEPT_LABELS[@]}; i++)); do
    breakdown+="${breakdown:+, }${_WORKTREE_GC_KEPT_COUNTS[$i]} ${_WORKTREE_GC_KEPT_LABELS[$i]}"
  done
  _worktree_gc_plural "$((_WORKTREE_GC_N_REMOVED - _WORKTREE_GC_N_REMOVED_DIRS))" checkout checkouts
  removed=$REPLY
  if ((_WORKTREE_GC_N_REMOVED_DIRS > 0)); then
    _worktree_gc_plural "$_WORKTREE_GC_N_REMOVED_DIRS" 'empty directory' 'empty directories'
    removed+=", $REPLY,"
  fi
  _worktree_gc_plural "$_WORKTREE_GC_N_BRANCHES" branch branches
  deleted=$REPLY
  _worktree_gc_plural "$_WORKTREE_GC_N_BRANCHES_KEPT" branch branches
  kept=$REPLY${breakdown:+ ($breakdown)}
  _worktree_gc_plural "$((_WORKTREE_GC_N_KEPT - _WORKTREE_GC_N_KEPT_DIRS))" 'young checkout' 'young checkouts'
  young=$REPLY
  if ((_WORKTREE_GC_N_KEPT_DIRS > 0)); then
    _worktree_gc_plural "$_WORKTREE_GC_N_KEPT_DIRS" 'young directory' 'young directories'
    young+=" and $REPLY"
  fi
  if ((_WORKTREE_GC_APPLY == 0)); then
    _worktree_gc_err "done (dry run): would remove $removed and delete $deleted; kept $kept and $young; skipped $_WORKTREE_GC_N_SKIPPED; $_WORKTREE_GC_N_FAILED failed"
  else
    _worktree_gc_err "done: removed $removed and deleted $deleted; kept $kept and $young; skipped $_WORKTREE_GC_N_SKIPPED; $_WORKTREE_GC_N_FAILED failed"
  fi
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
  local age=$_DR_WORKTREE_STALE_DAYS
  local saw_dry=0 saw_apply=0
  local -a extra_roots=()
  local arg root old_list dir old common checkout
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
  _worktree_gc_drop_local_env
  # The sweep's own probes name every repository explicitly, so they skip
  # the dotfiles PATH launcher for the real Git behind it, as the doctor's
  # probes do (or DOT_DOCTOR_GIT): the launcher pays a shell startup per call,
  # and a sweep makes hundreds. git-tools still runs with PATH as it is.
  _dr_worktree_resolve_git

  # A mistyped --root is a usage error, not an empty sweep of nothing. So is
  # one holding a newline or tab: roots travel one per line, tab-separated,
  # and such a name would split into a directory nobody named (or lose a
  # trailing tab) and be swept in its place.
  local i
  for ((i = 0; i < ${#extra_roots[@]}; i++)); do
    root=${extra_roots[$i]}
    if [[ $root == *[$'\n\t']* ]]; then
      _worktree_gc_err "root holds a newline or tab, not supported: $(printf "%q" "$root")"
      return 1
    fi
    if [[ ! -d $root ]]; then
      _worktree_gc_err "no such root: $root"
      return 1
    fi
  done

  _WORKTREE_GC_AGE=$age
  _WORKTREE_GC_FETCHED=$'\n'
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
  _WORKTREE_GC_SEL_PENDING=()
  _WORKTREE_GC_SEL_ALIAS=()
  _WORKTREE_GC_PR_UNKNOWN_REPOS=()
  _WORKTREE_GC_KEPT_LABELS=()
  _WORKTREE_GC_KEPT_COUNTS=()
  _WORKTREE_GC_ROOT_COMMONS=()
  _WORKTREE_GC_ROOT_DIRS=()
  _DR_WORKTREE_BARE=$'\n'
  _DR_WORKTREE_BASE_KEYS=()
  _DR_WORKTREE_BASE_REFS=()
  _WORKTREE_GC_N_REMOVED=0
  _WORKTREE_GC_N_BRANCHES=0
  _WORKTREE_GC_N_BRANCHES_KEPT=0
  _WORKTREE_GC_N_KEPT=0
  _WORKTREE_GC_N_SKIPPED=0
  _WORKTREE_GC_N_FAILED=0
  _WORKTREE_GC_N_REMOVED_DIRS=0
  _WORKTREE_GC_N_KEPT_DIRS=0
  _worktree_gc_load_provider
  # Every admin scan of the sweep (one per empty or orphan candidate) reads
  # the same clone roots; resolve gitfile roots once.
  _dr_worktree_clone_roots_load
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

  # What the candidate list cannot carry is still reported: a failed orphan
  # cleanup's quarantine (never rediscovered as a candidate, but holding
  # files someone must look at), a name holding a newline, and a symlink
  # whose target path holds one.
  local kind path
  while IFS=$'\t' read -r kind path; do
    _worktree_gc_unescape "$path"
    case $kind in
      quarantine)
        _worktree_gc_record skipped "$REPLY" "quarantine left by a failed orphan cleanup: inspect it, recover any files, then remove it by hand"
        ;;
      newline) _worktree_gc_record skipped "$REPLY" "name holds a newline; not swept" ;;
      newline-target) _worktree_gc_record skipped "$REPLY" "symlink target holds a newline; not swept" ;;
    esac
  done < <(_dr_worktree_odd_entries ${extra_roots[@]+"${extra_roots[@]}"})

  # Every managed clone gets branch cleanup, whether or not it owns a
  # discovered checkout: most merged branches have no checkout left.
  _dr_worktree_base_gitdir
  if [[ -n $REPLY && -d $REPLY ]]; then
    common=$(_dr_worktree_physical "$REPLY")
    [[ -n $common ]] && repos+=("$common")
  fi
  while IFS=$'\t' read -r common checkout; do
    common=$(_dr_worktree_physical "$common")
    [[ -n $common ]] || continue
    repos+=("$common")
    # Remember every clone root as its repository's checkout. Git names a
    # main worktree by stripping /.git from the real Git directory, so a
    # --separate-git-dir clone, or one whose .git is a symlink to a Git
    # directory elsewhere, lists that directory instead; _worktree_gc_repo_dir
    # falls back to this root only when the listed main has no .git.
    _WORKTREE_GC_ROOT_COMMONS+=("$common")
    _WORKTREE_GC_ROOT_DIRS+=("$checkout")
  done < <(_dr_worktree_clone_roots)

  _worktree_gc_drop_groupings
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
      [[ -z $_WORKTREE_GC_OWNER ]] || repos+=("$_WORKTREE_GC_OWNER")
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
