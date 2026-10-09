# shellcheck shell=bash
# dot doctor: worktree disk and staleness hygiene.
#
# Warn-only by design: nothing here fails the doctor run and nothing touches
# the checkouts. Disk pressure and abandoned worktrees are owner decisions;
# this check only makes them visible.
#
# A checkout is stale when it shows no Git activity for the stale window and
# its branch is merged or its own-name upstream is gone; a stale checkout with
# uncommitted changes is reported as dirty instead, because dot-worktree-gc
# keeps it (unless all it holds untracked is a cache the gc may prune). Clone
# roots' worktree admin areas are read directly, so checkouts registered
# anywhere count, and prunable or locked admin entries are reported. A
# checkout whose `.git` pointer names a repository or admin entry that no
# longer exists is an orphan: Git cannot inspect it, so it is reported on its
# own row and never probed.
#
# The disk threshold defaults to 10 GiB and is overridable with
# DOT_WORKTREE_WARN_BYTES (plain integer bytes; anything else falls back to
# the default). Within it the disk row passes; above it the row is
# information, and warns only when stale and orphaned trees hold at least
# half the bytes or a filesystem holding them has under 5% and under
# 20 GiB free, the cases where the row names something to do. Dot config keys are
# engine-owned, so a DOT_* environment knob follows the codebase's existing
# pattern for client behavior switches.
# DOT_DOCTOR_GIT names the Git binary the probes use (an absolute path or a
# command name), for hosts whose PATH Git is a slow wrapper; an unusable
# value falls back to the PATH search below.

_DR_WORKTREE_WARN_BYTES_DEFAULT=10737418240
_DR_WORKTREE_STALE_DAYS=14
# The disk row warns above the limit only when stale and orphaned trees
# hold at least this share of the bytes, or when a filesystem holding a
# worktree root is low on space: under LOW_FREE_PERCENT of its usable space
# (used plus available, as df's capacity column counts it) and under
# LOW_FREE_BYTES as well, so a large disk with tens of GiB left is not
# called low (see _dr_worktree_report_disk).
_DR_WORKTREE_DOMINANT_PERCENT=50
_DR_WORKTREE_LOW_FREE_PERCENT=5
_DR_WORKTREE_LOW_FREE_BYTES=21474836480

# Every clean stale checkout of the last _dr_check_worktrees run, as
# "physical-path<TAB>reason", for callers that want each path and reason
# without parsing the row's display items.
_DR_WORKTREE_STALE_ENTRIES=()

# Git binary for every probe in this file; empty means plain `git` from PATH
# (dot-worktree-gc sources these helpers and never sets it).
_DR_WORKTREE_GIT=

_dr_git() {
  "${_DR_WORKTREE_GIT:-git}" "$@"
}

# Succeed when CANDIDATE is a Git binary the probes may run: executable, not
# a directory, and not the dotfiles PATH launcher. The launcher is skipped by
# identity and, for any other launcher copy, by its marker line.
_dr_worktree_git_usable() {
  local candidate=$1 launcher=$HOME/.local/bin/git line
  local marker='# Dotfiles-aware launcher for Git.'
  [[ -x $candidate && ! -d $candidate ]] || return 1
  ! [[ -e $launcher && $candidate -ef $launcher ]] || return 1
  line=
  # Bounded reads: a binary's first "line" can be arbitrarily long.
  {
    IFS= read -r -n 256 line && IFS= read -r -n 256 line
  } 2>/dev/null <"$candidate" || line=
  [[ $line != "$marker" ]]
}

# Resolve the Git binary for every probe into _DR_WORKTREE_GIT. An explicit
# DOT_DOCTOR_GIT wins when usable: the first PATH Git on some hosts is a
# wrapper that costs several times a plain Git per call, and only the host's
# own configuration (an overlay's environment) can name the plain one.
# Otherwise this takes the real Git behind the dotfiles PATH launcher. The
# launcher pays a Bash startup plus shell-loader on every call (tens of ms
# each on a loaded host, dozens of calls per run) and routes non-repository
# HOME descendants to the base repository. Every probe here names its
# repository explicitly (`-C <checkout>`), so the routing buys nothing and a
# stray non-repository path must fail instead of answering for the base
# repository. Skips the launcher the way launcher-real.sh does. When nothing
# else qualifies it falls back to plain `git` (the launcher itself): slower,
# but every probe still passes an explicit repository. Read-only: unlike the
# launcher, it never publishes a resolution cache. Never fails.
_dr_worktree_resolve_git() {
  local override=${DOT_DOCTOR_GIT:-} search=${PATH:-} dir candidate

  _DR_WORKTREE_GIT=
  case $override in
    '') ;;
    */*) _dr_worktree_git_usable "$override" && _DR_WORKTREE_GIT=$override ;;
    *)
      candidate=$(type -P -- "$override" 2>/dev/null) || candidate=
      [[ -n $candidate ]] && _dr_worktree_git_usable "$candidate" &&
        _DR_WORKTREE_GIT=$candidate
      ;;
  esac
  [[ -z $_DR_WORKTREE_GIT ]] || return 0
  while [[ -n $search ]]; do
    dir=${search%%:*}
    case $dir in
      '') dir=. ;;
      \~) dir=$HOME ;;
      \~/*) dir=$HOME/${dir#\~/} ;;
    esac
    candidate=$dir/git
    if _dr_worktree_git_usable "$candidate"; then
      _DR_WORKTREE_GIT=$candidate
      return 0
    fi
    case $search in
      *:*) search=${search#*:} ;;
      *) break ;;
    esac
  done
  return 0
}

# Per-run base-ref cache, keyed by repo identity (see
# _dr_worktree_repo_key). Checkouts of one repo share a single base
# resolution instead of each paying up to five git probes. Reset on
# every _dr_check_worktrees call.
_DR_WORKTREE_BASE_KEYS=()
_DR_WORKTREE_BASE_REFS=()

# Resolve the disk threshold in bytes. Invalid overrides fall back to the
# default so a typo can neither silence the check nor warn unconditionally.
_dr_worktree_warn_bytes() {
  local override=${DOT_WORKTREE_WARN_BYTES:-}

  case $override in
    "" | *[!0-9]*) override=$_DR_WORKTREE_WARN_BYTES_DEFAULT ;;
  esac
  if ((${#override} > 18)); then
    override=$_DR_WORKTREE_WARN_BYTES_DEFAULT
  fi
  # Decimal, whatever the leading zeros: later arithmetic would read 0-led
  # digits as octal.
  printf '%s\n' "$((10#$override))"
}

# Format a byte count for display (10G, 800M, ...), rounding to nearest.
# Display only; the threshold comparison always uses exact integers. Integer
# Bash arithmetic, so the disk row's several sizes cost no process; the
# remainder split keeps every step inside 64 bits for 18-digit inputs.
_dr_worktree_human_bytes() {
  local bytes=$1 whole tenths
  if ((bytes >= 1073741824)); then
    whole=$((bytes / 1073741824))
    tenths=$(((bytes % 1073741824 * 10 + 536870912) / 1073741824))
    if ((tenths == 10)); then
      whole=$((whole + 1))
      tenths=0
    fi
    printf '%d.%dG' "$whole" "$tenths"
  elif ((bytes >= 1048576)); then
    printf '%dM' $(((bytes + 524288) / 1048576))
  elif ((bytes >= 1024)); then
    printf '%dK' $(((bytes + 512) / 1024))
  else
    printf '%dB' "$bytes"
  fi
}

# Set _DR_WORKTREE_RESOLVED to the physical path of directory DIR, exactly,
# or fail when it cannot be resolved. Command substitution strips trailing
# newlines, which a path may end with (a symlink to "/ext/foo<NL>" would
# read as /ext/foo), so a sentinel follows pwd's output and only pwd's own
# newline is removed. A dedicated variable, not REPLY, since callers print
# paths in the middle of functions that use REPLY.
_DR_WORKTREE_RESOLVED=
_dr_worktree_resolve() {
  _DR_WORKTREE_RESOLVED=$(cd -- "$1" 2>/dev/null && pwd -P 2>/dev/null && printf x) || {
    _DR_WORKTREE_RESOLVED=
    return 1
  }
  _DR_WORKTREE_RESOLVED=${_DR_WORKTREE_RESOLVED%x}
  _DR_WORKTREE_RESOLVED=${_DR_WORKTREE_RESOLVED%$'\n'}
}

# Like _dr_worktree_resolve, but a path holding a newline anywhere counts
# as unresolvable: callers print paths one per line, and a symlink whose
# target name holds a newline would otherwise split into a path outside the
# roots and a relative tail, or (a trailing newline) pass for a different
# directory (_dr_worktree_odd_entries reports such links). Callers already
# inside a command substitution use this directly to save a fork.
_dr_worktree_resolve_line() {
  _dr_worktree_resolve "$1" || return 1
  [[ $_DR_WORKTREE_RESOLVED != *$'\n'* ]]
}

# Print the physical path of a candidate checkout, or nothing when it cannot
# be resolved (see _dr_worktree_resolve_line). Never fails.
_dr_worktree_physical() {
  _dr_worktree_resolve_line "$1" || return 0
  printf '%s\n' "$_DR_WORKTREE_RESOLVED"
}

# Report the base client's separate Git directory via REPLY: DOTFILES when
# the caller set it (the doctor's compat layer does), else the client
# default. The doctor and dot-worktree-gc must agree on it, or the gc would
# skip the base client's registered checkouts the doctor sends it.
_dr_worktree_base_gitdir() {
  REPLY=${DOTFILES:-${DOT_CLIENT_GIT_DIR:-${HOME:-}/.dotfiles}}
}

# The clone roots and parked linked worktrees of the current run (see
# _dr_worktree_clone_roots and _dr_worktree_parked_roots), cached by
# _dr_worktree_clone_roots_load so a gitfile root costs one Git process per
# run, not one per admin scan; subshells read the same cache. Keyed by
# the HOME it was computed for, so a later caller with another HOME (a test,
# a sourcing tool) never reads roots that are not its own.
_DR_WORKTREE_CLONE_ROOTS=
_DR_WORKTREE_PARKED_ROOTS=
_DR_WORKTREE_CLONE_ROOTS_HOME=
_DR_WORKTREE_CLONE_ROOTS_LOADED=0

# Print one tagged line per ~/git/* and ~/.dotfiles-* root with a .git:
# "C<TAB>common<TAB>root" for a clone root, which is its repository's main
# checkout, and "P<TAB>common<TAB>root" for a linked worktree parked among
# them. A root whose .git is a directory is a clone root with no process; a
# gitfile root asks Git where it points once, which answers both questions.
# A root Git cannot read is left out. Never fails.
_dr_worktree_scan_roots() {
  local home=${HOME:-} gitpath root out gitdir common
  for gitpath in "$home"/git/*/.git "$home"/.dotfiles-*/.git; do
    root=${gitpath%/.git}
    if [[ -d $gitpath ]]; then
      printf 'C\t%s\t%s\n' "$gitpath" "$root"
      continue
    fi
    [[ -f $gitpath ]] || continue
    out=$(_dr_git -C "$root" rev-parse --git-dir --git-common-dir 2>/dev/null) || continue
    gitdir=${out%%$'\n'*}
    common=${out#*$'\n'}
    [[ -n $gitdir && -n $common && $common != "$out" ]] || continue
    [[ $gitdir == /* ]] || gitdir=$root/$gitdir
    [[ $common == /* ]] || common=$root/$common
    [[ -d $common ]] || continue
    if [[ $gitdir -ef $common ]]; then
      printf 'C\t%s\t%s\n' "$common" "$root"
    else
      printf 'P\t%s\t%s\n' "$common" "$root"
    fi
  done
  return 0
}

# Print the TAG entries of _dr_worktree_scan_roots, untagged, from the run's
# cache once loaded for this HOME, else from a fresh scan.
_dr_worktree_roots_tagged() {
  local tag=$1 line
  if ((_DR_WORKTREE_CLONE_ROOTS_LOADED == 1)) &&
    [[ $_DR_WORKTREE_CLONE_ROOTS_HOME == "${HOME:-}" ]]; then
    if [[ $tag == C ]]; then
      [[ -z $_DR_WORKTREE_CLONE_ROOTS ]] || printf '%s' "$_DR_WORKTREE_CLONE_ROOTS"
    else
      [[ -z $_DR_WORKTREE_PARKED_ROOTS ]] || printf '%s' "$_DR_WORKTREE_PARKED_ROOTS"
    fi
    return 0
  fi
  while IFS= read -r line; do
    [[ $line == "$tag"$'\t'* ]] && printf '%s\n' "${line#?$'\t'}"
  done < <(_dr_worktree_scan_roots)
  return 0
}

# Print "common<TAB>checkout" for every ~/git/* and ~/.dotfiles-* clone
# root: its common Git directory and the root, its main checkout. A gitfile
# root counts only when it is that repository's main checkout (a clone made
# with --separate-git-dir). A linked worktree parked among the clones is not
# a clone root: its owner may live anywhere (another tool's workspace,
# /tmp), and parking a checkout under ~/git must not bring that repository's
# branches into the sweep or its admin area into the doctor; the owner is
# covered only if it is ~/.dotfiles or a clone root itself (see
# _dr_worktree_parked_roots). A ~/.dotfiles-* root that is a linked worktree
# is treated as parked too.
# Uses the run's cache once loaded. Never fails.
_dr_worktree_clone_roots() {
  _dr_worktree_roots_tagged C
}

# Print "common<TAB>root" for every linked worktree parked under ~/git or as
# a ~/.dotfiles-* root. Only one whose repository is ~/.dotfiles or a clone
# root lends its .worktrees to the sweep (_dr_worktree_candidates); parking
# alone never brings a repository in. Uses the run's cache once loaded.
# Never fails.
_dr_worktree_parked_roots() {
  _dr_worktree_roots_tagged P
}

# Scan the roots once for this run and cache both lists for every later
# _dr_worktree_clone_roots and _dr_worktree_parked_roots call, in this shell
# and its subshells: a gitfile root then costs one Git process per run, not
# one per admin scan. Callers (the doctor check, the gc sweep) load at the
# start of each run, so a new run always rescans. Must run in the main
# shell.
_dr_worktree_clone_roots_load() {
  local scan line
  _DR_WORKTREE_CLONE_ROOTS_LOADED=0
  _DR_WORKTREE_CLONE_ROOTS=
  _DR_WORKTREE_PARKED_ROOTS=
  scan=$(_dr_worktree_scan_roots)
  while IFS= read -r line; do
    case $line in
      C$'\t'*) _DR_WORKTREE_CLONE_ROOTS+=${line#C$'\t'}$'\n' ;;
      P$'\t'*) _DR_WORKTREE_PARKED_ROOTS+=${line#P$'\t'}$'\n' ;;
    esac
  done <<<"$scan"
  _DR_WORKTREE_CLONE_ROOTS_HOME=${HOME:-}
  _DR_WORKTREE_CLONE_ROOTS_LOADED=1
}

# Print the common Git directory of every clone root whose worktree admin
# area the scan reads: the base client's separate Git directory, then every
# ~/git/* and ~/.dotfiles-* clone (_dr_worktree_clone_roots). With `base`,
# only the base client's, which is the registered scope dot-worktree-gc
# sweeps. Never fails.
_dr_worktree_clone_commons() {
  local common checkout base seen
  local -a printed=() aliased=()

  _dr_worktree_base_gitdir
  base=$REPLY
  if [[ -n $base && -d $base ]]; then
    printf '%s\n' "$base"
    printed+=("$base")
  fi
  [[ ${1:-} != base ]] || return 0
  # Two entries can reach one repository through a symlink (~/git/alias ->
  # ~/git/repo, or a .git that is a symlink), and its admin entries would be
  # counted twice. Only an entry reached through a symlink can repeat
  # another, so only those are compared by identity, after the rest.
  while IFS=$'\t' read -r common checkout; do
    if [[ -L $checkout || -L $common || $common != "$checkout/.git" ]]; then
      aliased+=("$common")
    else
      printf '%s\n' "$common"
      printed+=("$common")
    fi
  done < <(_dr_worktree_clone_roots)
  for common in ${aliased[@]+"${aliased[@]}"}; do
    for seen in ${printed[@]+"${printed[@]}"}; do
      [[ ! $common -ef $seen ]] || continue 2
    done
    printf '%s\n' "$common"
    printed+=("$common")
  done
  return 0
}

# Read every clone root's `worktrees/<id>/gitdir` pointers directly, without
# a Git process, and sort the entries into global arrays:
#   _DR_WORKTREE_ADMIN_PATHS     all pointed-to checkout paths, including those
#                                whose .git files are missing
#   _DR_WORKTREE_ADMIN_LIVE      registered checkouts that still exist, as
#                                written (callers resolve physical paths)
#   _DR_WORKTREE_ADMIN_PRUNABLE  "repo<TAB>id" for entries `git worktree
#                                prune` would remove (missing or empty gitdir
#                                pointer, or a checkout that no longer exists)
#   _DR_WORKTREE_ADMIN_LOCKED    "path<TAB>" for locked live checkouts and
#                                "repo<TAB>id" for locked entries whose
#                                checkout is gone; prune never removes either
# Paths stay raw so dot-worktree-gc, which shares the enumeration but not the
# doctor display helpers, can call this too. Pass `base` to read only the
# base client's admin area (see _dr_worktree_clone_commons).
# This finds checkouts a repository registered anywhere (for example a
# shared ~/worktrees root no fixed folder scan covers) and the admin entries
# a fixed folder scan cannot see at all. Relative pointers
# (worktree.useRelativePaths) resolve against the admin entry. Must run in
# the main shell. Never fails.
_dr_worktree_admin_scan() {
  local common admin id target repo
  _DR_WORKTREE_ADMIN_PATHS=()
  _DR_WORKTREE_ADMIN_LIVE=()
  _DR_WORKTREE_ADMIN_PRUNABLE=()
  _DR_WORKTREE_ADMIN_LOCKED=()

  while IFS= read -r common; do
    repo=${common%/.git}
    for admin in "$common"/worktrees/*/; do
      admin=${admin%/}
      [[ -d $admin ]] || continue
      id=${admin##*/}
      target=
      if [[ -f $admin/gitdir ]]; then
        # The whole file minus Git's one trailing newline: a checkout path
        # may itself hold a newline, and its first line alone would name a
        # missing path and call a live checkout prunable.
        IFS= read -r -d '' target 2>/dev/null <"$admin/gitdir" || true
        target=${target%$'\n'}
      fi
      case $target in
        '' | /*) ;;
        *) target=$admin/$target ;;
      esac
      [[ -z $target ]] || _DR_WORKTREE_ADMIN_PATHS+=("${target%/.git}")
      if [[ -n $target && -e $target ]]; then
        # The pointer names the checkout's `.git` file; like Git, strip only
        # that suffix.
        _DR_WORKTREE_ADMIN_LIVE+=("${target%/.git}")
        if [[ -e $admin/locked ]]; then
          _DR_WORKTREE_ADMIN_LOCKED+=("${target%/.git}"$'\t')
        fi
      elif [[ -e $admin/locked ]]; then
        _DR_WORKTREE_ADMIN_LOCKED+=("$repo"$'\t'"$id")
      else
        _DR_WORKTREE_ADMIN_PRUNABLE+=("$repo"$'\t'"$id")
      fi
    done
  done < <(_dr_worktree_clone_commons "${1:-}")
  return 0
}

# The shared worktree roots under HOME, the one list the doctor's report and
# dot-worktree-gc's sweep both read. Their children are checkouts, and a
# child without a `.git` of its own is a grouping folder (a batch of
# checkouts made together), whose checkout children count too. A root under
# ~/git that is itself a checkout (a clone that happens to be named
# `worktrees`) is not one: its children are that repository's own files,
# and an empty one would read as a leftover directory to remove. A clone at
# ~/git/worktrees is still covered as a clone root; one at ~/git/.worktrees
# is not (the ~/git/* clone glob skips hidden names), and neither is swept
# as a worktree root.
_DR_WORKTREE_SHARED_ROOTS=(.worktrees git/worktrees worktrees git/.worktrees)

# Print the physical path of every child of ROOT. With `group`, a child that
# has no `.git` is a grouping folder: it is printed too (its loose bytes
# still count for disk), followed by each of its children that has a `.git`.
# One level only, so a checkout's own subfolders are never candidates.
# The root resolves once; a child that is not a symlink is its physical
# parent plus its name, so only symlinked children pay a resolving subshell
# (a fork each, and enumeration covers well over a hundred paths).
# _DR_WORKTREE_SKIP_SYMLINK_CANDIDATES suppresses symlinked children for callers
# that need direct-directory provenance; the normal doctor view follows them.
# Never fails.
_dr_worktree_root_children() {
  local root=$1 mode=${2:-} root_phys child phys nested
  [[ -d $root ]] || return 0
  root_phys=$(_dr_worktree_physical "$root")
  [[ -n $root_phys ]] || return 0
  for child in "$root"/*/; do
    child=${child%/}
    [[ -d $child ]] || continue
    # One path per line cannot hold a name with a newline;
    # _dr_worktree_odd_entries reports those instead.
    [[ $child != *$'\n'* ]] || continue
    if [[ -L $child ]]; then
      [[ ${_DR_WORKTREE_SKIP_SYMLINK_CANDIDATES:-0} != 1 ]] || continue
      phys=$(_dr_worktree_physical "$child")
      [[ -n $phys ]] || continue
    else
      phys=$root_phys/${child##*/}
    fi
    printf '%s\n' "$phys"
    [[ $mode == group && ! -e $child/.git ]] || continue
    for nested in "$child"/*/; do
      nested=${nested%/}
      [[ -e $nested/.git && $nested != *$'\n'* ]] || continue
      if [[ -L $nested ]]; then
        [[ ${_DR_WORKTREE_SKIP_SYMLINK_CANDIDATES:-0} != 1 ]] || continue
        _dr_worktree_physical "$nested"
      else
        printf '%s\n' "$phys/${nested##*/}"
      fi
    done
  done
  return 0
}

# Print one swept worktree checkout per line: the set dot-worktree-gc may
# remove from. Sources, in order:
#   1. linked checkouts registered by the base client repository, wherever
#      they live,
#   2. children of the shared worktree roots (every repo, plus orphaned
#      checkouts git no longer tracks), one grouping level deep,
#   3. repo-local .worktrees children under every clone root
#      (_dr_worktree_clone_roots): ~/git plus the ~/.dotfiles-* overlay
#      clones, which are repos like any other,
#   4. repo-local .worktrees children of every parked linked worktree
#      (_dr_worktree_parked_roots) whose repository is ~/.dotfiles or one of
#      those clone roots,
#   5. children of any extra roots passed as arguments (--root).
# Repo-local and extra roots take children only: they are a repository's or
# the caller's own layout, not a shared batch area. Checkouts other clones
# registered elsewhere (tool workspaces, agent worktrees inside a
# repository, anything under /tmp) are deliberately not swept: the doctor
# reports them through _dr_worktree_registered, and their owner removes
# them. Callers dedupe and exclude the live checkout. Never fails. Extra
# roots arrive from out-of-file callers (dot-worktree-gc); the in-file
# doctor call intentionally passes none.
# shellcheck disable=SC2120
_dr_worktree_candidates() {
  local home=${HOME:-} dir mode root

  [[ -n $home && -d $home ]] || return 0

  _dr_worktree_admin_scan base
  for dir in ${_DR_WORKTREE_ADMIN_LIVE[@]+"${_DR_WORKTREE_ADMIN_LIVE[@]}"}; do
    [[ -d $dir && $dir != *$'\n'* ]] || continue
    _dr_worktree_physical "$dir"
  done

  while IFS=$'\t' read -r mode root; do
    _dr_worktree_root_children "$root" "$mode"
  done < <(_dr_worktree_root_dirs "$@")
  return 0
}

# Print "mode<TAB>dir" for every root whose children _dr_worktree_candidates
# enumerates (sources 2-5 below): `group` for a shared root, whose grouping
# folders count one level deeper, and `plain` for every other. The one list
# the candidate enumeration and _dr_worktree_odd_entries walk. Never fails.
# shellcheck disable=SC2120 # extra roots come from dot-worktree-gc
_dr_worktree_root_dirs() {
  local home=${HOME:-} root dir extra common checkout
  local -a managed=()

  [[ -n $home && -d $home ]] || return 0

  _dr_worktree_base_gitdir
  [[ -z $REPLY || ! -d $REPLY ]] || managed+=("$REPLY")

  for root in "${_DR_WORKTREE_SHARED_ROOTS[@]}"; do
    # Only a root under ~/git can be a clone root itself; a stray .git in
    # ~/worktrees or ~/.worktrees (an old `git init`) must not hide the
    # checkouts parked there.
    [[ $root == git/* && -e $home/$root/.git ]] && continue
    printf 'group\t%s\n' "$home/$root"
  done

  # Only clone roots' own .worktrees: globbing every ~/git/* entry would
  # also read the .worktrees of a linked worktree parked there, whose
  # checkouts belong to a repository the sweep does not manage, and sweeping
  # one would bring that repository's branches in after all.
  while IFS=$'\t' read -r common checkout; do
    printf 'plain\t%s\n' "$checkout/.worktrees"
    managed+=("$common")
  done < <(_dr_worktree_clone_roots)
  # A linked worktree parked under ~/git whose repository is ~/.dotfiles or a
  # clone root is that repository's checkout like any other, so its own
  # .worktrees counts too; any other owner's stays out. Compared by identity:
  # Git may spell a common directory physically where HOME is a symlink.
  while IFS=$'\t' read -r common root; do
    for dir in ${managed[@]+"${managed[@]}"}; do
      if [[ $common -ef $dir ]]; then
        printf 'plain\t%s\n' "$root/.worktrees"
        break
      fi
    done
  done < <(_dr_worktree_parked_roots)

  for extra in "$@"; do
    printf 'plain\t%s\n' "$extra"
  done
  return 0
}

# Set _DR_WORKTREE_ESCAPED to FIELD with backslash, tab, and newline escaped
# as \\, \t, and \n (git-tools' porcelain escaping), for one-per-line
# output. A dedicated variable, not REPLY: callers print records in the
# middle of functions that return their own result through REPLY.
_DR_WORKTREE_ESCAPED=
_dr_worktree_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//$'\t'/\\t}
  _DR_WORKTREE_ESCAPED=${value//$'\n'/\\n}
}

# Print "kind<TAB>escaped-path" (see _dr_worktree_escape) for entries in the
# swept roots that the candidate list cannot carry: `quarantine` for a
# private container a failed orphan cleanup left behind (hidden, so never a
# candidate, yet holding files someone must inspect), `newline` for a child
# whose name holds a newline, and `newline-target` for a symlinked child
# whose target path holds one. Grouping folders of shared roots are searched
# too. Never fails.
# shellcheck disable=SC2120 # extra roots come from dot-worktree-gc
_dr_worktree_odd_entries() {
  local mode root dir child seen kind target
  local -a dirs=() printed=()
  while IFS=$'\t' read -r mode root; do
    [[ -d $root ]] || continue
    dirs=("$root")
    if [[ $mode == group ]]; then
      for child in "$root"/*/; do
        child=${child%/}
        [[ -d $child && ! -L $child && ! -e $child/.git ]] && dirs+=("$child")
      done
    fi
    for dir in "${dirs[@]}"; do
      for child in "$dir"/.dot-worktree-gc-quarantine-*/ "$dir"/*/; do
        child=${child%/}
        [[ -d $child ]] || continue
        case ${child##*/} in
          .dot-worktree-gc-quarantine-*) kind=quarantine ;;
          *$'\n'*) kind=newline ;;
          *)
            # A symlink whose target path holds a newline: the enumeration
            # refuses its physical path (_dr_worktree_physical), so it is
            # named here instead. Only links pay the resolving subshell.
            [[ -L $child ]] || continue
            _dr_worktree_resolve "$child" || continue
            target=$_DR_WORKTREE_RESOLVED
            [[ $target == *$'\n'* ]] || continue
            kind=newline-target
            ;;
        esac
        # A root reached twice (an aliased clone root, an overlapping
        # --root) must not list one entry twice.
        for seen in ${printed[@]+"${printed[@]}"}; do
          [[ ! $child -ef $seen ]] || continue 2
        done
        printed+=("$child")
        _dr_worktree_escape "$child"
        printf '%s\t%s\n' "$kind" "$_DR_WORKTREE_ESCAPED"
      done
    done
  done < <(_dr_worktree_root_dirs "$@")
  return 0
}

# Print every live checkout any clone root registered, physical, one per
# line: the doctor's report scope, wider than the swept one. Never fails.
_dr_worktree_registered() {
  local dir
  _dr_worktree_admin_scan
  for dir in ${_DR_WORKTREE_ADMIN_LIVE[@]+"${_DR_WORKTREE_ADMIN_LIVE[@]}"}; do
    [[ -d $dir && $dir != *$'\n'* ]] || continue
    _dr_worktree_physical "$dir"
  done
  return 0
}

# Print "S<TAB>path" for every swept candidate and "R<TAB>path" for every
# registered checkout, for the doctor to read in one pass. Never fails.
_dr_worktree_tagged_candidates() {
  local dir
  # shellcheck disable=SC2119 # the doctor passes no extra roots
  while IFS= read -r dir; do
    printf 'S\t%s\n' "$dir"
  done < <(_dr_worktree_candidates)
  while IFS= read -r dir; do
    printf 'R\t%s\n' "$dir"
  done < <(_dr_worktree_registered)
}

# Print the repo-identity key for a checkout, or fail. Same-repo
# checkouts must share one key while different repos must never
# collide, so the key derives from git storage identity without
# spawning git: the physical `.git` directory, or for linked
# checkouts the physical common dir above the `worktrees` admin area.
# Anything ambiguous (missing or unreadable pointer, relative gitdir
# that no longer resolves, non-worktree gitfile layouts outside the
# admin area) fails and the caller falls back to the checkout path
# itself, which shares with nothing and behaves exactly uncached.
_dr_worktree_repo_key() {
  local dir=$1 gitpath=$1/.git first target phys parent
  if [[ -d $gitpath ]]; then
    _dr_worktree_resolve_line "$gitpath" || return 1
    printf '%s\n' "$_DR_WORKTREE_RESOLVED"
    return 0
  fi
  [[ -f $gitpath ]] || return 1
  IFS= read -r first 2>/dev/null <"$gitpath" || return 1
  first=${first%$'\r'}
  case $first in
    'gitdir: '?*) target=${first#gitdir: } ;;
    *) return 1 ;;
  esac
  [[ -n $target ]] || return 1
  case $target in
    /*) _dr_worktree_resolve_line "$target" || return 1 ;;
    *) _dr_worktree_resolve_line "$dir/$target" || return 1 ;;
  esac
  phys=$_DR_WORKTREE_RESOLVED
  parent=${phys%/*}
  case $parent in
    */worktrees) printf '%s\n' "${parent%/*}" ;;
    *) printf '%s\n' "$phys" ;;
  esac
}

# Print the local base ref (short remote form, e.g. origin/main) for a
# checkout, without touching the network, or fail. Origin-first: the
# origin HEAD symref, then the sole remote's HEAD when there is exactly
# one remote, then conventional origin names. With several remotes a
# fork's HEAD must never win by enumeration order. Every candidate must
# resolve to a commit; stale symrefs fall through instead of failing
# closed wrong. dot-worktree-gc proves merges against this same base, so
# the doctor never calls a checkout merged against a different one; the
# batched probe (_dr_worktree_repo_stale_rows) mirrors its steps.
_dr_worktree_base_ref() {
  local dir=$1 ref head_info default_ref candidate
  local -a remotes=()
  # The full ref, stripped by hand: `--short` answers remotes/origin/<name>
  # when a local branch or tag shares the short name, which would then split
  # into a remote called `remotes`.
  ref=$(_dr_git -C "$dir" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || ref=
  case $ref in
    refs/remotes/*) ref=${ref#refs/remotes/} ;;
    *) ref= ;;
  esac
  if [[ $ref == */* ]] &&
    _dr_git -C "$dir" rev-parse --verify -q "$ref^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$ref"
    return 0
  fi
  mapfile -t remotes < <(_dr_git -C "$dir" remote 2>/dev/null)
  if ((${#remotes[@]} == 1)); then
    head_info=$(_dr_git -C "$dir" for-each-ref --format='%(symref)' 'refs/remotes/*/HEAD' 2>/dev/null) || head_info=
    default_ref=${head_info%%$'\n'*}
    case $default_ref in
      refs/remotes/*)
        default_ref=${default_ref#refs/remotes/}
        if _dr_git -C "$dir" rev-parse --verify -q "$default_ref^{commit}" >/dev/null 2>&1; then
          printf '%s\n' "$default_ref"
          return 0
        fi
        ;;
    esac
  fi
  for candidate in main master trunk; do
    if _dr_git -C "$dir" rev-parse --verify -q "origin/$candidate^{commit}" >/dev/null 2>&1; then
      printf 'origin/%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# Resolve the local base ref for a checkout once per repo per run and
# report it via REPLY, or fail. The repo key needs no git spawn, so
# unshared checkouts pay two cheap subshells at most while shared ones
# skip up to five git probes each. Failures cache too: the doctor never
# fetches, so nothing later in the run can grow a base ref. Must run in
# the main shell; callers under $() would discard the cache writes.
# dot-worktree-gc resolves through this too (it fetches only after
# resolving, so a cached failure stays right there as well).
_dr_worktree_base_ref_ensure() {
  local dir=$1 key=$1 i ref
  REPLY=
  # On key failure bypass the cache entirely (resolve uncached below):
  # falling back to `key=$dir` would share a namespace with real keys,
  # where a checkout path could theoretically equal another checkout's
  # physical gitdir and cross-share a base ref.
  if ! key=$(_dr_worktree_repo_key "$dir"); then
    if ref=$(_dr_worktree_base_ref "$dir"); then
      REPLY=$ref
      return 0
    fi
    return 1
  fi
  for ((i = 0; i < ${#_DR_WORKTREE_BASE_KEYS[@]}; i++)); do
    [[ ${_DR_WORKTREE_BASE_KEYS[$i]} == "$key" ]] || continue
    ref=${_DR_WORKTREE_BASE_REFS[$i]}
    if [[ -n $ref ]]; then
      REPLY=$ref
      return 0
    fi
    return 1
  done
  if ref=$(_dr_worktree_base_ref "$dir"); then
    _DR_WORKTREE_BASE_KEYS+=("$key")
    _DR_WORKTREE_BASE_REFS+=("$ref")
    REPLY=$ref
    return 0
  fi
  _DR_WORKTREE_BASE_KEYS+=("$key")
  _DR_WORKTREE_BASE_REFS+=("")
  return 1
}

# Succeed when a branch's upstream, given as its remote name and remote ref
# (`%(upstream:remotename)` and `%(upstream:remoteref)`), is BRANCH's own
# name on a real remote. Only then does a gone upstream suggest the branch
# was pushed and its remote branch deleted after landing: a branch tracking
# some other branch (a base it was cut from, or a local branch) proves
# nothing when that one goes, and may hold commits no remote ever saw. The
# structured fields keep remote names with slashes from blurring the split.
# A gone upstream that was a default branch (main, master, trunk, or what the
# remote's recorded HEAD, given as its full symref target, names) suggests a
# rename, not a landing, so it does not count either. git-tools applies the
# same rule (_gone_upstream_is_evidence) before dot-worktree-gc retires a
# checkout on a gone upstream alone, so the doctor never calls stale what
# the gc keeps. Git without these atoms fails the query, which reads as no
# upstream: never stale on that ground, never removed.
_dr_worktree_own_upstream() {
  local remote=$1 ref=$2 branch=$3 head=${4:-}
  [[ -n $remote && $remote != . && $ref == "refs/heads/$branch" ]] || return 1
  case $ref in
    refs/heads/main | refs/heads/master | refs/heads/trunk) return 1 ;;
  esac
  [[ -z $head || $ref != "refs/heads/${head#refs/remotes/"$remote"/}" ]]
}

# Report via REPLY the full target of REMOTE's recorded HEAD symref in the
# repository at DIR (refs/remotes/<remote>/<branch>), or "". Asked only for a
# gone upstream, where the answer matters; symbolic-ref reads a HEAD left
# dangling by that very deletion, which for-each-ref would omit. Cached per
# repository and remote for the run (_dr_check_worktrees resets it).
_DR_WORKTREE_REMOTE_HEADS=$'\n'
_dr_worktree_remote_head() {
  local dir=$1 remote=$2 key entry
  key=$dir$'\t'$remote$'\t'
  case $_DR_WORKTREE_REMOTE_HEADS in
    *$'\n'"$key"*)
      entry=${_DR_WORKTREE_REMOTE_HEADS#*$'\n'"$key"}
      REPLY=${entry%%$'\n'*}
      return 0
      ;;
  esac
  REPLY=$(_dr_git -C "$dir" symbolic-ref -q "refs/remotes/$remote/HEAD" 2>/dev/null) || REPLY=
  _DR_WORKTREE_REMOTE_HEADS+=$key$REPLY$'\n'
}

# Report why an old checkout counts as stale (its branch is merged into
# the upstream default or its own-name upstream is gone) via REPLY, or "". The
# caller gates on age with a single find pass so young checkouts cost
# no git spawns here. Non-git checkouts, detached HEAD, repos without
# remotes, and missing tools all report "". A checkout Git cannot inspect
# at all reports "?", so the caller can name it instead of calling it
# clean. Never fails; never touches the network. Must run in the main
# shell so the per-repo base cache survives across checkouts.
_dr_worktree_stale_reason() {
  local dir=$1
  local branch upstream_info upstream_short upstream_track remote_name remote_ref
  local default_ref

  REPLY=
  [[ -n $_DR_WORKTREE_GIT ]] || command -v git >/dev/null 2>&1 || return 0
  [[ -e $dir/.git ]] || return 0

  if ! branch=$(_dr_git -C "$dir" branch --show-current 2>/dev/null); then
    REPLY='?'
    return 0
  fi
  [[ -n $branch ]] || return 0

  # One ref query reports the configured upstream even after it is pruned.
  # Fields carry a tag: TAB is IFS whitespace, so `read` would collapse an
  # empty track field and shift the rest.
  upstream_info=$(_dr_git -C "$dir" for-each-ref \
    --format='u=%(upstream:short)%09t=%(upstream:track)%09r=%(upstream:remotename)%09f=%(upstream:remoteref)' \
    "refs/heads/$branch" 2>/dev/null) || return 0
  IFS=$'\t' read -r upstream_short upstream_track remote_name remote_ref <<<"$upstream_info"
  if [[ $upstream_track == "t=[gone]" ]] &&
    _dr_worktree_remote_head "$dir" "${remote_name#r=}" &&
    _dr_worktree_own_upstream "${remote_name#r=}" "${remote_ref#f=}" "$branch" "$REPLY"; then
    REPLY="upstream ${upstream_short#u=} is gone"
    return 0
  fi

  _dr_worktree_base_ref_ensure "$dir" || return 0
  default_ref=$REPLY
  REPLY=
  if _dr_git -C "$dir" merge-base --is-ancestor HEAD "$default_ref" 2>/dev/null; then
    REPLY="merged into $default_ref"
  fi
  return 0
}

# Parse `git worktree list --porcelain` text into parallel arrays holding each
# record's registered path and checked-out branch ref ("" when detached or
# bare), in listing order, so the main checkout comes first. The doctor stale
# probe and the gc indexer share this one reading of the porcelain grammar.
# Fills globals instead of printing so callers avoid a subshell per repo.
_dr_worktree_porcelain_records() {
  local line path='' ref='' have=0
  _DR_WORKTREE_REC_PATHS=()
  _DR_WORKTREE_REC_REFS=()
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      'worktree '*)
        if ((have == 1)); then
          _DR_WORKTREE_REC_PATHS+=("$path")
          _DR_WORKTREE_REC_REFS+=("$ref")
        fi
        path=${line#worktree }
        ref=
        have=1
        ;;
      'branch '*) ref=${line#branch } ;;
    esac
  done <<<"$1"
  if ((have == 1)); then
    _DR_WORKTREE_REC_PATHS+=("$path")
    _DR_WORKTREE_REC_REFS+=("$ref")
  fi
}

# Record REF as the cached base ref for repo KEY unless one is cached.
_dr_worktree_base_ref_seed() {
  local key=$1 ref=$2 i
  for ((i = 0; i < ${#_DR_WORKTREE_BASE_KEYS[@]}; i++)); do
    [[ ${_DR_WORKTREE_BASE_KEYS[$i]} == "$key" ]] && return 0
  done
  _DR_WORKTREE_BASE_KEYS+=("$key")
  _DR_WORKTREE_BASE_REFS+=("$ref")
}

# Fill the _DR_WORKTREE_REC_* arrays for the repository whose common Git
# directory is $1 straight from its files, as _dr_worktree_porcelain_records
# would from `git worktree list --porcelain`: the main checkout first, then
# every linked admin entry, with "" for a detached HEAD. Saves one Git spawn
# per repository. Fails, so the caller lists through Git, whenever the files
# cannot be read the way Git would: a bare or separate Git directory (its
# main checkout lives in config, not in the path), or the reftable backend
# (HEAD files are placeholders there).
_dr_worktree_admin_records() {
  local common=$1 admin head target
  _DR_WORKTREE_REC_PATHS=()
  _DR_WORKTREE_REC_REFS=()

  [[ $common == */.git && -f $common/HEAD && ! -e $common/reftable ]] || return 1
  IFS= read -r head 2>/dev/null <"$common/HEAD" || return 1
  _DR_WORKTREE_REC_PATHS+=("${common%/.git}")
  case $head in
    'ref: '?*) _DR_WORKTREE_REC_REFS+=("${head#ref: }") ;;
    *) _DR_WORKTREE_REC_REFS+=("") ;;
  esac
  for admin in "$common"/worktrees/*/; do
    admin=${admin%/}
    [[ -d $admin ]] || continue
    target=
    head=
    IFS= read -r target 2>/dev/null <"$admin/gitdir" || true
    IFS= read -r head 2>/dev/null <"$admin/HEAD" || true
    # Entries Git cannot read either (no pointer) list nothing useful.
    [[ -n $target ]] || continue
    case $target in
      /*) ;;
      *) target=$admin/$target ;;
    esac
    _DR_WORKTREE_REC_PATHS+=("${target%/.git}")
    case $head in
      'ref: '?*) _DR_WORKTREE_REC_REFS+=("${head#ref: }") ;;
      *) _DR_WORKTREE_REC_REFS+=("") ;;
    esac
  done
  return 0
}

# Build "physical-path<TAB>reason" rows, via REPLY, for every checkout git
# lists for the repo owning $1, or fail so each checkout falls back to the
# per-checkout probe. A handful of spawns cover the whole repo where the
# per-checkout probe costs three per checkout; on hosts whose git sits behind
# wrappers each spawn is tens of ms. Rows cover only checkouts in
# _DR_WORKTREE_PROBE_SET (the old checkouts being probed; unset means all),
# and both ref queries name only their branches: %(upstream:track) walks
# history per ref, so a never-pulled main clone or every local branch would
# cost far more than batching saves. Git forbids `foo` beside `foo/bar`, so a
# pattern cannot pull in another branch. Reasons and
# precedence match _dr_worktree_stale_reason: a gone upstream wins, then a tip
# reachable from the base ref (`merge-base --is-ancestor HEAD` for an attached
# HEAD); detached checkouts report "". The base ref resolves only when some
# branch could still be merged. Must run in the main shell (base-ref cache).
_dr_worktree_repo_stale_rows() {
  local dir=$1 key=${2:-} listing tracking='' merged='' base='' rows='' need_base=0
  local i path ref phys reason entry name short track symref otype ptype rname rref
  local origin_head='' other_head=0 conventional=' ' commit
  local -a refs=() probe_paths=() probe_refs=()
  REPLY=
  if [[ -z $key ]] || ! _dr_worktree_admin_records "$key"; then
    listing=$(_dr_git -C "$dir" worktree list --porcelain 2>/dev/null) || return 1
    _dr_worktree_porcelain_records "$listing"
  fi
  for ((i = 0; i < ${#_DR_WORKTREE_REC_PATHS[@]}; i++)); do
    path=${_DR_WORKTREE_REC_PATHS[$i]}
    # Candidates are physical, so a registered path already in the set skips
    # the resolving subshell; anything else resolves before the membership test.
    if [[ -n ${_DR_WORKTREE_PROBE_SET+x} &&
      $_DR_WORKTREE_PROBE_SET == *$'\n'"$path"$'\n'* ]]; then
      phys=$path
    else
      phys=$(_dr_worktree_physical "$path")
      [[ -n $phys ]] || continue
      [[ -z ${_DR_WORKTREE_PROBE_SET+x} ||
        $_DR_WORKTREE_PROBE_SET == *$'\n'"$phys"$'\n'* ]] || continue
    fi
    ref=${_DR_WORKTREE_REC_REFS[$i]}
    probe_paths+=("$phys")
    probe_refs+=("$ref")
    [[ -n $ref ]] && refs+=("$ref")
  done
  if ((${#refs[@]} > 0)); then
    # The same query reads every input of the base-ref chain
    # (_dr_worktree_base_ref) that needs no remote count: origin's HEAD
    # symref, any other remote's HEAD, and the conventional origin branches.
    # So a repository with origin/HEAD, or with no other remote HEAD at all,
    # resolves its base with no extra spawn; only a repository whose chain
    # could reach a lone non-origin remote's HEAD runs the full chain.
    # for-each-ref omits a dangling symref, so a listed one names a ref that
    # exists, and every base candidate must name a commit (or a tag that
    # peels to one), as the chain's `^{commit}` check requires. Fields carry
    # a tag because TAB is IFS whitespace: `read` would collapse the empty
    # upstream fields of the remote rows and shift their values.
    tracking=$(_dr_git -C "$dir" for-each-ref \
      --format='%(refname)%09u=%(upstream:short)%09t=%(upstream:track)%09s=%(symref)%09o=%(objecttype)%09p=%(*objecttype)%09r=%(upstream:remotename)%09f=%(upstream:remoteref)' \
      "${refs[@]}" 'refs/remotes/*/HEAD' refs/remotes/origin/main \
      refs/remotes/origin/master refs/remotes/origin/trunk 2>/dev/null) || return 1
    while IFS=$'\t' read -r name short track symref otype ptype rname rref; do
      commit=0
      [[ $otype == o=commit || $ptype == p=commit ]] && commit=1
      case $name in
        refs/remotes/origin/HEAD)
          symref=${symref#s=}
          if ((commit == 1)) && [[ $symref == refs/remotes/?*/?* ]]; then
            origin_head=${symref#refs/remotes/}
          fi
          ;;
        refs/remotes/*/HEAD) other_head=1 ;;
        refs/remotes/origin/main | refs/remotes/origin/master | refs/remotes/origin/trunk)
          ((commit == 0)) || conventional+=" ${name#refs/remotes/origin/} "
          ;;
        refs/remotes/*) ;;
        *)
          # A branch whose own-name upstream is gone needs no base.
          [[ -n $name ]] || continue
          if [[ $track != "t=[gone]" ]] ||
            ! _dr_worktree_remote_head "$dir" "${rname#r=}" ||
            ! _dr_worktree_own_upstream "${rname#r=}" "${rref#f=}" "${name#refs/heads/}" "$REPLY"; then
            need_base=1
          fi
          ;;
      esac
    done <<<"$tracking"
    if ((need_base == 1)); then
      if [[ -z $origin_head && $other_head == 0 ]]; then
        # The chain's first two steps cannot succeed; its last takes the
        # first conventional branch, in this order. When none exists the
        # chain fails, and that failure caches like the chain's own.
        for name in main master trunk; do
          if [[ $conventional == *" $name "* ]]; then
            origin_head=origin/$name
            break
          fi
        done
        [[ -n $origin_head || -z $key ]] || _dr_worktree_base_ref_seed "$key" ""
      fi
      if [[ -n $origin_head ]]; then
        base=$origin_head
        [[ -z $key ]] || _dr_worktree_base_ref_seed "$key" "$base"
      elif [[ $other_head == 1 ]] && _dr_worktree_base_ref_ensure "$dir"; then
        base=$REPLY
      fi
      if [[ -n $base ]]; then
        merged=$(_dr_git -C "$dir" for-each-ref --merged="$base" \
          --format='%(refname)' "${refs[@]}" 2>/dev/null) || return 1
      fi
    fi
  fi
  for ((i = 0; i < ${#probe_paths[@]}; i++)); do
    phys=${probe_paths[$i]}
    ref=${probe_refs[$i]}
    reason=
    if [[ -n $ref ]]; then
      while IFS=$'\t' read -r name short track symref otype ptype rname rref; do
        [[ $name == "$ref" ]] || continue
        short=${short#u=}
        if [[ $track == "t=[gone]" ]] &&
          _dr_worktree_remote_head "$dir" "${rname#r=}" &&
          _dr_worktree_own_upstream "${rname#r=}" "${rref#f=}" "${ref#refs/heads/}" "$REPLY"; then
          reason="upstream $short is gone"
        fi
        break
      done <<<"$tracking"
      if [[ -z $reason && -n $base ]]; then
        while IFS= read -r entry; do
          if [[ $entry == "$ref" ]]; then
            reason="merged into $base"
            break
          fi
        done <<<"$merged"
      fi
    fi
    rows+="$phys"$'\t'"$reason"$'\n'
  done
  REPLY=$rows
}

# Per-repo stale rows, parallel to their repo keys; a failed listing caches
# as the single row "-" so the repo is not re-listed for every checkout.
_DR_WORKTREE_FACT_KEYS=()
_DR_WORKTREE_FACT_ROWS=()

# Report a checkout's stale reason via REPLY like _dr_worktree_stale_reason,
# answering from the per-repo rows when git lists the checkout. Checkouts it
# cannot place (no repo key, orphaned admin dirs, paths the porcelain lines
# cannot frame) fall back to the per-checkout probe. Never fails; must run in
# the main shell so the per-repo rows survive across checkouts.
_dr_worktree_stale_reason_batched() {
  local dir=$1 key i rows='' found=0 row
  REPLY=
  if { [[ -z $_DR_WORKTREE_GIT ]] && ! command -v git >/dev/null 2>&1; } ||
    ! key=$(_dr_worktree_repo_key "$dir"); then
    _dr_worktree_stale_reason "$dir"
    return 0
  fi
  for ((i = 0; i < ${#_DR_WORKTREE_FACT_KEYS[@]}; i++)); do
    if [[ ${_DR_WORKTREE_FACT_KEYS[$i]} == "$key" ]]; then
      rows=${_DR_WORKTREE_FACT_ROWS[$i]}
      found=1
      break
    fi
  done
  if ((found == 0)); then
    if _dr_worktree_repo_stale_rows "$dir" "$key"; then
      rows=$REPLY
    else
      rows=-
    fi
    _DR_WORKTREE_FACT_KEYS+=("$key")
    _DR_WORKTREE_FACT_ROWS+=("$rows")
  fi
  # Match the whole path: a prefix match would let an unlisted checkout take
  # a TAB-extended sibling's row. Reasons never contain a TAB (ref names
  # cannot), so the path is everything before the last one.
  if [[ $rows != - ]]; then
    while IFS= read -r row; do
      [[ -n $row ]] || continue
      if [[ ${row%$'\t'*} == "$dir" ]]; then
        REPLY=${row##*$'\t'}
        return 0
      fi
    done <<<"$rows"
  fi
  _dr_worktree_stale_reason "$dir"
  return 0
}

# Concurrent probe jobs. Each probe is a short Git spawn whose cost on a
# loaded host is mostly process startup, so a few in flight cut the wall time
# of the long tail (dozens of old checkouts across many repositories) without
# adding work. DOT_DOCTOR_JOBS=1 keeps this extension strictly serial too.
_dr_worktree_jobs() {
  local jobs=${DOT_DOCTOR_JOBS:-}
  case $jobs in
    '' | *[!0-9]*) jobs=8 ;;
  esac
  # dot reads 0 as serial too.
  ((10#$jobs >= 1)) || jobs=1
  jobs=$((10#$jobs))
  ((jobs <= 8)) || jobs=8
  REPLY=$jobs
}

# Run "FUNC ARG" for every ARG with up to _dr_worktree_jobs calls in flight
# and fill _DR_WORKTREE_PAR_OUT, parallel to the arguments, with each call's
# REPLY, or "-" for a call that failed. Each call runs in its own subshell and
# writes only its own file under the worker's private TMPDIR, so calls share
# no mutable state; any cache a call fills dies with its subshell. Falls back
# to running the calls inline when no scratch directory is available. Must run
# in the main shell. Never fails.
_dr_worktree_parallel() {
  local fn=$1 tmp i jobs running=0 out
  shift
  _DR_WORKTREE_PAR_OUT=()
  (($# > 0)) || return 0
  _dr_worktree_jobs
  jobs=$REPLY
  if ((jobs == 1)) || ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-worktrees.XXXXXX" 2>/dev/null); then
    for ((i = 1; i <= $#; i++)); do
      if "$fn" "${!i}"; then
        _DR_WORKTREE_PAR_OUT+=("$REPLY")
      else
        _DR_WORKTREE_PAR_OUT+=(-)
      fi
    done
    return 0
  fi
  for ((i = 1; i <= $#; i++)); do
    (
      if "$fn" "${!i}"; then
        printf '%s' "$REPLY" >"$tmp/$i"
      fi
    ) &
    running=$((running + 1))
    if ((running >= jobs)); then
      # `wait -n` needs Bash 4.3; older shells drain the whole batch.
      if wait -n 2>/dev/null; then
        running=$((running - 1))
      else
        wait
        running=0
      fi
    fi
  done
  wait
  for ((i = 1; i <= $#; i++)); do
    if [[ -f $tmp/$i ]]; then
      out=
      IFS= read -r -d '' out <"$tmp/$i" || true
      _DR_WORKTREE_PAR_OUT+=("$out")
    else
      _DR_WORKTREE_PAR_OUT+=(-)
    fi
  done
  rm -rf "$tmp"
  return 0
}

# Parallel job body: stale rows for one "dir<TAB>key" repository.
_dr_worktree_rows_job() {
  _dr_worktree_repo_stale_rows "${1%%$'\t'*}" "${1#*$'\t'}"
}

# Fill the per-repo stale-row cache for every repository owning one of the
# given checkouts, one parallel job per repository, so the per-checkout
# lookups that follow are cache hits. Checkouts without a repo key are left
# to the per-checkout probe, as before. Must run in the main shell.
_dr_worktree_prefetch_rows() {
  local dir key i seen=$'\n'
  local -a keys=() jobs=()
  for dir in "$@"; do
    key=$(_dr_worktree_repo_key "$dir") || continue
    [[ $seen == *$'\n'"$key"$'\n'* ]] && continue
    seen+="$key"$'\n'
    keys+=("$key")
    jobs+=("$dir"$'\t'"$key")
  done
  ((${#jobs[@]} > 0)) || return 0
  _dr_worktree_parallel _dr_worktree_rows_job "${jobs[@]}"
  for ((i = 0; i < ${#keys[@]}; i++)); do
    _DR_WORKTREE_FACT_KEYS+=("${keys[$i]}")
    # A failed job caches "-", exactly like a failed inline listing.
    _DR_WORKTREE_FACT_ROWS+=("${_DR_WORKTREE_PAR_OUT[$i]}")
  done
}

# Print the du-total cache path: a recomputable performance record,
# so it lives under the cache base with the usual XDG fallback. A
# relative XDG_CACHE_HOME is ignored, like the termnav state precedent.
_dr_worktree_du_cache_file() {
  local base=${XDG_CACHE_HOME:-}
  case $base in
    /*) ;;
    *) base=$HOME/.cache ;;
  esac
  printf '%s\n' "$base/dot/doctor-worktrees-du.tsv"
}

# Print one `mtime path` line per checkout root, or fail. A single
# batched stat covers every root; GNU and BSD spellings are tried in
# turn so Linux, macOS, and BSD userlands all work. Any failure (a root
# vanishing mid-run, an unknown stat) fails the key and the caller
# recomputes, exactly as an uncached run would. Newline-containing
# paths fail for the same reason: line framing cannot hold them.
_dr_worktree_key_lines() {
  local dir out
  for dir in "$@"; do
    case $dir in *$'\n'*) return 1 ;; esac
  done
  out=$(stat -c '%Y %n' "$@" 2>/dev/null) ||
    out=$(stat -f '%m %N' "$@" 2>/dev/null) || return 1
  [[ -n $out ]] || return 1
  printf '%s\n' "$out"
}

# Print the summed `du -sk` total in KiB for the given roots. The
# single du pass from the original check, unchanged.
_dr_worktree_du_total() {
  local du_out=0
  du_out=$(du -sk -- "$@" 2>/dev/null | awk '{sum += $1} END {print sum + 0}') || du_out=0
  case $du_out in
    "" | *[!0-9]*) printf '0\n' ;;
    *) printf '%s\n' "$du_out" ;;
  esac
}

# Measure the du total in KiB for the checkout roots, re-measuring only the
# roots that changed. The cache keeps one `KiB<TAB>mtime<TAB>path` entry per
# root under a header holding the time of the last full pass; a root whose
# path and mtime match its entry reuses the stored size, and every other
# root (new, touched, or never measured) joins one `du -sk` pass. Root mtimes
# move on checkout add/remove and top-level changes, so with dozens of
# worktrees coming and going only the moved ones pay du; nested-only growth
# reuses a size until the root changes. That staleness is the documented
# cost: this check is warn-only and the total is advisory. A six-hour max age
# since the last full pass bounds it, so a never-touched root cannot report a
# stale size indefinitely. Roots measured in separate passes lose du's
# cross-root hard-link de-duplication, so hard-linked local clones may count
# twice; the total stays advisory.
# Never fails: every cache problem falls back to a fresh full pass, and a
# failed store is silently skipped for the next run to retry.
# Reports the total KiB via REPLY and each measured root as "KiB<TAB>path"
# in _DR_WORKTREE_DU_SIZES, so the disk row can name the largest roots at no
# extra cost. The sizes stay empty when the cache key cannot be built (the
# uncached fallback reads only a total). Must run in the main shell to keep
# the sizes.
_DR_WORKTREE_DU_SIZES=()
_dr_worktree_du_measure() {
  local key cache now header stamp='' line kib mtime path out total=0
  local fresh_entries='' full=0 i tmp
  local -a changed=() changed_mtimes=()
  # Associative lookups: substring searches over the joined entry text cost
  # quadratic time in Bash and took seconds with a hundred roots.
  local -A cached=() measured=()
  _DR_WORKTREE_DU_SIZES=()

  if ! key=$(_dr_worktree_key_lines "$@"); then
    REPLY=$(_dr_worktree_du_total "$@")
    return 0
  fi
  cache=$(_dr_worktree_du_cache_file)
  now=$(date +%s 2>/dev/null) || now=

  # Load reusable sizes keyed by "mtime path".
  if [[ -r $cache ]] && IFS= read -r header 2>/dev/null <"$cache" &&
    [[ $header =~ ^v2\ ([0-9]+)$ ]]; then
    stamp=${BASH_REMATCH[1]}
    if [[ -n $now ]] && ((now - stamp > 21600)); then
      stamp=
    else
      while IFS=$'\t' read -r kib mtime path; do
        [[ $kib =~ ^[0-9]+$ && $mtime =~ ^[0-9]+$ && -n $path ]] || continue
        cached["$mtime $path"]=$kib
      done < <(tail -n +2 "$cache" 2>/dev/null)
    fi
  fi
  if [[ -z $stamp ]]; then
    full=1
    stamp=${now:-0}
  fi

  while IFS= read -r line; do
    mtime=${line%% *}
    path=${line#* }
    if [[ $full == 0 && -n ${cached["$line"]+x} ]]; then
      kib=${cached["$line"]}
      total=$((total + kib))
      fresh_entries+="$kib"$'\t'"$mtime"$'\t'"$path"$'\n'
      _DR_WORKTREE_DU_SIZES+=("$kib"$'\t'"$path")
    else
      changed+=("$path")
      changed_mtimes+=("$mtime")
    fi
  done <<<"$key"

  if ((${#changed[@]} > 0)); then
    # du prints `KiB<TAB>path` per argument as spelled. A root du cannot
    # measure counts as 0, as before, and is not cached so it retries.
    out=$(du -sk -- "${changed[@]}" 2>/dev/null) || true
    while IFS=$'\t' read -r kib path; do
      [[ $kib =~ ^[0-9]+$ && -n $path ]] && measured["$path"]=$kib
    done <<<"$out"
    for ((i = 0; i < ${#changed[@]}; i++)); do
      path=${changed[$i]}
      kib=${measured["$path"]:-0}
      total=$((total + kib))
      _DR_WORKTREE_DU_SIZES+=("$kib"$'\t'"$path")
      [[ $kib == 0 ]] ||
        fresh_entries+="$kib"$'\t'"${changed_mtimes[$i]}"$'\t'"$path"$'\n'
    done
  fi

  mkdir -p "${cache%/*}" 2>/dev/null || true
  if tmp=$(mktemp "${cache}.tmp.XXXXXX" 2>/dev/null) &&
    printf 'v2 %s\n%s' "$stamp" "$fresh_entries" 2>/dev/null >"$tmp" &&
    mv -f "$tmp" "$cache" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  REPLY=$total
}

# Report the activity-signal paths for one checkout via REPLY, one per
# line: the checkout root plus its Git directory's HEAD and index when they
# exist. The root's mtime moves only when top-level entries come and go, so a
# checkout with fresh commits, checkouts, resets, or staging could look weeks
# old by folder mtime alone; HEAD and the index move on exactly that activity.
# The HEAD reflog is deliberately not a signal: `git gc` (and the automatic gc
# that fetch and commit trigger) rewrites every worktree's reflog file in the
# owning clone, which would make all of them look active. Locating the Git
# directory reads the `.git` pointer without a Git process, and REPLY avoids a
# subshell per checkout. Paths with a newline are never signals (line framing
# cannot hold them), which leaves the checkout looking young. Never fails.
_dr_worktree_age_signals() {
  local dir=$1 gitdir='' first signal

  REPLY=$dir
  if [[ -d $dir/.git ]]; then
    gitdir=$dir/.git
  elif [[ -f $dir/.git ]] && IFS= read -r first 2>/dev/null <"$dir/.git"; then
    first=${first%$'\r'}
    case $first in
      'gitdir: '/*) gitdir=${first#gitdir: } ;;
      'gitdir: '?*) gitdir=$dir/${first#gitdir: } ;;
    esac
  fi
  [[ -n $gitdir ]] || return 0
  # A reftable repository keeps HEAD as a placeholder; its table directory
  # moves on every ref update instead.
  for signal in "$gitdir/HEAD" "$gitdir/index" "$gitdir/reftable"; do
    if [[ -e $signal && $signal != *$'\n'* ]]; then
      REPLY+=$'\n'$signal
    fi
  done
  return 0
}

# Fill _DR_WORKTREE_OLD with the checkouts (after DAYS) whose every
# activity signal is older than DAYS days (find's `-mtime +DAYS`). One find
# pass covers all signals; a signal that vanishes mid-pass (or any find
# failure) simply goes unprinted, which leaves its checkout looking young:
# both the doctor's stale warnings and dot-worktree-gc's removals err toward
# keeping. Must run in the main shell.
_dr_worktree_old_checkouts() {
  local days=$1 dir signals signal
  local -a all_signals=() checkout_signals=()
  local -A old_set=()
  _DR_WORKTREE_OLD=()
  shift

  (($# > 0)) || return 0
  for dir in "$@"; do
    _dr_worktree_age_signals "$dir"
    signals=$REPLY
    checkout_signals+=("$signals")
    while IFS= read -r signal; do
      all_signals+=("$signal")
    done <<<"$signals"
  done
  while IFS= read -r signal; do
    [[ -n $signal ]] && old_set["$signal"]=1
  done < <(find "${all_signals[@]}" -maxdepth 0 -mtime +"$days" 2>/dev/null || true)

  local i old
  for ((i = 0; i < $#; i++)); do
    old=1
    while IFS= read -r signal; do
      if [[ -z ${old_set["$signal"]+x} ]]; then
        old=0
        break
      fi
    done <<<"${checkout_signals[$i]}"
    if ((old == 1)); then
      dir=${*:i+1:1}
      _DR_WORKTREE_OLD+=("$dir")
    fi
  done
}

# Succeed when the checkout is an orphan: its `.git` is a pointer file whose
# target (a repository's `worktrees/<id>` admin entry, or a Git directory)
# no longer exists, because the repository was deleted or moved or the entry
# was pruned. Reports the missing target via REPLY. Reads the pointer only,
# so orphans cost no process and never reach a Git probe that would fail.
# A pointer that cannot be read or parsed is not called an orphan: nothing
# names what is missing.
_dr_worktree_orphan() {
  _dr_worktree_pointer "$1" || return 1
  [[ ! -e $REPLY ]] || return 1
}

# Report the target of a checkout's `.git` pointer file via REPLY (a
# relative target joined to the checkout), or fail when `.git` is not a
# readable `gitdir:` pointer. File read only.
_dr_worktree_pointer() {
  local dir=$1 first=''
  REPLY=
  [[ -f $dir/.git ]] || return 1
  { IFS= read -r first || [[ -n $first ]]; } 2>/dev/null <"$dir/.git" || return 1
  # Git strips a trailing CR (a pointer written on Windows); so must this.
  first=${first%$'\r'}
  case $first in
    'gitdir: '/*) REPLY=${first#gitdir: } ;;
    'gitdir: '?*) REPLY=$dir/${first#gitdir: } ;;
    *) return 1 ;;
  esac
}

# Describe an orphan's missing pointer target for display, via REPLY: the
# repository that is gone, or the repository whose admin entry is gone.
_dr_worktree_orphan_cause() {
  local target=$1 common=$1 repo
  # Only a target directly inside a `worktrees` folder is an admin entry.
  if [[ ${target%/*} == ?*/worktrees ]]; then
    common=${target%/worktrees/*}
  fi
  repo=${common%/.git}
  _dr_worktree_label "$repo"
  if [[ $common != "$target" && -d $common ]]; then
    REPLY="admin entry gone from $REPLY"
  else
    REPLY+=" is gone"
  fi
}

# Succeed when the checkout is a linked worktree: its `.git` is a pointer
# into a repository's `worktrees/` admin area. Reads the pointer only.
_dr_worktree_is_linked() {
  local first
  [[ -f $1/.git ]] || return 1
  IFS= read -r first 2>/dev/null <"$1/.git" || return 1
  first=${first%$'\r'}
  [[ $first == 'gitdir: '*/worktrees/?* ]]
}

# Succeed when a linked checkout was moved without `git worktree repair`: its
# `.git` names an admin entry that exists but points back at another path,
# and that path's .git is gone. Git cannot speak for it from either side, so
# dot-worktree-gc keeps it (and labels it so) and a prune would orphan it.
# A copy (the registered path's .git still exists) is not moved: repairing
# from the copy would steal the original's registration. Reports the
# registered path via REPLY. File reads only.
_dr_worktree_moved() {
  local dir=$1 admin target
  _dr_worktree_pointer "$dir" || return 1
  admin=$REPLY
  REPLY=
  [[ -f $admin/gitdir ]] || return 1
  IFS= read -r -d '' target 2>/dev/null <"$admin/gitdir" || true
  target=${target%$'\n'}
  [[ -n $target ]] || return 1
  case $target in
    /*) ;;
    *) target=$admin/$target ;;
  esac
  # The registered path's .git file, as Git and the admin scan judge it: a
  # plain directory recreated at the old path does not make the registration
  # live, while a copy (whose .git came along) still exists and is no move.
  [[ ! -e $target ]] || return 1
  REPLY=${target%/.git}
}

# Succeed when the repository with common Git directory COMMON is bare.
# Asked once per repository per run and cached (_dr_check_worktrees and
# worktree_gc_main reset it), since several stale checkouts usually share
# one repository. The name proves nothing: `git clone --bare repo foo/.git`
# makes a bare repository called .git.
_DR_WORKTREE_BARE=$'\n'
_dr_worktree_bare() {
  local common=$1 answer
  case $_DR_WORKTREE_BARE in
    *$'\n'"$common"$'\t'true$'\n'*) return 0 ;;
    *$'\n'"$common"$'\t'false$'\n'*) return 1 ;;
  esac
  answer=$(_dr_git --git-dir="$common" rev-parse --is-bare-repository 2>/dev/null) || answer=
  [[ $answer == true ]] || answer=false
  _DR_WORKTREE_BARE+=$common$'\t'$answer$'\n'
  [[ $answer == true ]]
}

# Succeed when some clone root (_dr_worktree_clone_roots) has COMMON as its
# common Git directory.
_dr_worktree_clone_root_of() {
  local want=$1 common checkout
  while IFS=$'\t' read -r common checkout; do
    [[ ! $common -ef $want ]] || return 0
  done < <(_dr_worktree_clone_roots)
  return 1
}

# Report via REPLY why dot-worktree-gc keeps a clean stale linked checkout
# in its swept roots that the stale row would otherwise offer for the sweep
# (", <why>"), or "": its repository is bare or lost its main checkout (no
# checkout to run git-tools from), keeps its HEAD reflog, with entries, in
# reftable (git-tools cannot inspect it), it was moved without repair, it
# holds a
# submodule directory with content (populated, which Git refuses to remove,
# or holding files status does not show, which git-tools keeps), its branch
# is merged by ancestry and was never logged (git-tools cannot date it, so
# keeps it), or its repository has no resolvable remote base (only an
# upstream-gone reason can show that). These approximate the gc's and
# git-tools' gates from cheap signals (the submodule check reads only
# gitlinks of a checkout with a .gitmodules, not the admin modules/ area),
# so a checkout they miss is still kept by the gc, never removed wrongly.
# Must run in the main shell (base-ref cache).
_dr_worktree_gc_keeps() {
  local dir=$1 reason=$2 common base line mode path
  REPLY=
  if _dr_worktree_moved "$dir"; then
    REPLY=", moved without repair"
    return 0
  fi
  _dr_worktree_pointer "$dir" || return 0
  common=${REPLY%/worktrees/*}
  REPLY=
  _dr_worktree_base_gitdir
  base=$REPLY
  REPLY=
  if [[ -z $base || ! $common -ef $base ]]; then
    if _dr_worktree_bare "$common"; then
      REPLY=", its repository is bare"
      return 0
    fi
    # A repository whose Git directory is not inside its checkout (made
    # with --separate-git-dir) has a main checkout only Git's clone-root
    # discovery can name; with that root gone, the gc has nowhere to run.
    if [[ $common != */.git ]] && ! _dr_worktree_clone_root_of "$common"; then
      REPLY=", its main checkout is gone"
      return 0
    fi
  fi
  # git-tools reads a worktree's HEAD reflog from its file to find commits
  # only that history holds. Reftable keeps no such file, so git-tools keeps
  # a worktree whose HEAD reflog still has entries (uninspectable), which is
  # most linked worktrees; one whose reflog expired or was never written
  # can go. The same query git-tools makes decides, asked only of reftable
  # repositories (after the bare check, which names the likelier cause).
  if [[ -e $common/reftable && -n $(_dr_git -C "$dir" log -g -n 1 \
    --no-show-signature --format=%H HEAD -- 2>/dev/null) ]]; then
    REPLY=", its reflogs are in reftable, which git-tools cannot inspect"
    return 0
  fi
  if [[ -f $dir/.gitmodules ]]; then
    while IFS= read -r line; do
      mode=${line%% *}
      path=${line#*$'\t'}
      if [[ $mode == 160000 ]] && _dr_worktree_has_entries "$dir/$path"; then
        REPLY=", holds a submodule directory with content"
        return 0
      fi
    done < <(_dr_git -C "$dir" ls-files -s 2>/dev/null)
  fi
  if [[ $reason == upstream\ * ]] && ! _dr_worktree_base_ref_ensure "$dir"; then
    REPLY=", no remote base branch"
    return 0
  fi
  # git-tools tries the ancestry proof first, so a branch the base contains
  # is held to the age rule even when the row's reason is its gone upstream
  # (the doctor checks that before ancestry); the file check comes first so
  # only a never-logged branch costs the ancestry probe.
  if _dr_worktree_never_logged "$dir" &&
    { [[ $reason == merged\ * ]] ||
      { [[ $reason == upstream\ * ]] && _dr_worktree_base_ref_ensure "$dir" &&
        _dr_git -C "$dir" merge-base --is-ancestor HEAD "$REPLY" 2>/dev/null; }; }; then
    REPLY=", its branch was never logged, so git-tools cannot date it"
    return 0
  fi
  REPLY=
}

# Succeed when DIR is a directory holding anything, hidden entries included.
# The subshell keeps the glob options from leaking.
_dr_worktree_has_entries() (
  shopt -s nullglob dotglob
  local entries=("$1"/*)
  ((${#entries[@]} > 0))
)

# Succeed when a linked checkout's branch has no reflog at all. A branch
# proven merged only by ancestry must be a day old before git-tools deletes
# it, dated by its newest reflog entry or, once the reflog expired (an
# emptied log), by its tip commit; a branch never logged (created while
# core.logAllRefUpdates was false, the default in a bare repository) has an
# unknown age and git-tools keeps it with its checkout. File reads only, so
# a reftable repository (reflogs inside its tables) or a detached HEAD never
# matches.
_dr_worktree_never_logged() {
  local dir=$1 admin head common
  _dr_worktree_pointer "$dir" || return 1
  admin=$REPLY
  common=${admin%/worktrees/*}
  [[ -f $admin/HEAD && ! -e $common/reftable ]] || return 1
  IFS= read -r head 2>/dev/null <"$admin/HEAD" || return 1
  [[ $head == 'ref: refs/heads/'?* ]] || return 1
  [[ ! -e $common/logs/${head#ref: } ]]
}

# Succeed when a linked checkout is locked, whichever repository owns it:
# Git marks the lock in the admin entry its `.git` pointer names.
_dr_worktree_is_locked() {
  local first admin
  [[ -f $1/.git ]] || return 1
  IFS= read -r first 2>/dev/null <"$1/.git" || return 1
  first=${first%$'\r'}
  case $first in
    'gitdir: '/*) admin=${first#gitdir: } ;;
    'gitdir: '?*) admin=$1/${first#gitdir: } ;;
    *) return 1 ;;
  esac
  [[ -e $admin/locked ]]
}

# Report a checkout's uncommitted state via REPLY: the number of changed
# or untracked entries ("0" when clean), or "?" when Git cannot inspect it.
# Untracked files are listed explicitly: a repository (the base client,
# for one) may set status.showUntrackedFiles=no, which every worktree
# inherits and which would hide new files from the porcelain output.
# `normal` lists an untracked directory as one entry, which is all a
# clean-or-dirty verdict needs.
# This is not the view dot-worktree-gc's removal gate uses: git-tools reads
# `--ignored=matching --untracked-files=all` and first prunes cache-tagged
# (CACHEDIR.TAG) directories and cleanupRepo.worktreePrunePath entries. So
# the gc can still keep a checkout counted clean here for its ignored files,
# and remove one counted dirty here only for a disposable cache; the dirty
# row's hint says what the gc keeps rather than promising the same verdict.
# --no-optional-locks keeps the probe from refreshing the index, which
# would both write into the checkout and reset its activity signal, and
# fsmonitor stays off so no watcher daemon starts per checkout.
_dr_worktree_dirty_count() {
  local out count=0 line
  REPLY='?'
  out=$(_dr_git --no-optional-locks -c core.fsmonitor=false \
    -C "$1" status --porcelain --untracked-files=normal 2>/dev/null) || return 0
  while IFS= read -r line; do
    [[ -n $line ]] && count=$((count + 1))
  done <<<"$out"
  REPLY=$count
}

# Physical spelling of HOME for the current check; set by
# _dr_check_worktrees.
_DR_WORKTREE_HOME_PHYS=

# Report a path for a record via REPLY. Checkout paths here are physical
# (the enumeration resolves them, and Git records them that way in its
# gitdir files), while HOME may be spelled through a symlink: macOS keeps it
# and TMPDIR under /var -> /private/var. Shortening only against the logical
# HOME would print a physical home path in full, so map the physical HOME
# prefix back to HOME first. HOME then abbreviates to `~` as
# dot_doctor_display_path does, and a TAB or line break becomes a space, as
# _dr_tilde does, but without a subshell: the rows list every checkout
# they name, and a fork per item adds up across a hundred worktrees.
_dr_worktree_label() {
  local path=$1 phys=${_DR_WORKTREE_HOME_PHYS:-}
  if [[ -n $phys && $phys != "$HOME" ]]; then
    case $path in
      "$phys") path=$HOME ;;
      "$phys"/*) path=$HOME/${path#"$phys"/} ;;
    esac
  fi
  # shellcheck disable=SC2088 # Tilde is display text, not expansion.
  if [[ $HOME == / ]]; then
    case $path in
      /) path='~' ;;
      /*) path="~/${path#/}" ;;
    esac
  elif [[ -n $HOME ]]; then
    case $path in
      "$HOME") path='~' ;;
      "$HOME"/*) path="~/${path#"$HOME"/}" ;;
    esac
  fi
  REPLY=${path//[$'\t\r\n']/ }
}

# Report registered admin entries that need an owner decision: prunable
# entries (warn, with the prune command) and locked entries (reported for
# visibility; a lock is deliberate, but a forgotten one hides a checkout
# from prune and from dot-worktree-gc forever).
#
# An entry whose checkout was moved (a candidate's `.git` still points at
# it) is not prunable: pruning would orphan a live checkout. Those get their
# own row with the repair command; the candidates (the checkouts the check
# found, passed as arguments) are read only when some entry looks prunable.
_dr_worktree_report_admin() {
  local entry repo id label common admin dir moved_to i hint why
  local -a items=() prunable=() moved=() moved_dirs=() pointers=() pointer_dirs=()
  local -A prune_repos=() moved_by_repo=()

  if ((${#_DR_WORKTREE_ADMIN_PRUNABLE[@]} > 0)); then
    for dir in "$@"; do
      _dr_worktree_pointer "$dir" || continue
      pointers+=("$REPLY")
      pointer_dirs+=("$dir")
    done
  fi
  for entry in ${_DR_WORKTREE_ADMIN_PRUNABLE[@]+"${_DR_WORKTREE_ADMIN_PRUNABLE[@]}"}; do
    repo=${entry%%$'\t'*}
    id=${entry#*$'\t'}
    common=$repo
    [[ -d $repo/.git ]] && common=$repo/.git
    admin=$common/worktrees/$id
    moved_to=
    for ((i = 0; i < ${#pointers[@]}; i++)); do
      if [[ -d $admin && ${pointers[$i]} -ef $admin ]]; then
        moved_to=${pointer_dirs[$i]}
        break
      fi
    done
    if [[ -n $moved_to ]]; then
      _dr_worktree_label "$repo"
      label=$REPLY
      _dr_worktree_label "$moved_to"
      moved+=("$REPLY (entry $id of $label)")
      moved_dirs+=("$REPLY")
      # Every moved checkout of the repository, one per line: a prune there
      # would orphan each of them.
      moved_by_repo["$label"]+=${moved_by_repo["$label"]:+$'\n'}$REPLY
    else
      prunable+=("$entry")
    fi
  done
  for entry in ${prunable[@]+"${prunable[@]}"}; do
    repo=${entry%%$'\t'*}
    id=${entry#*$'\t'}
    _dr_worktree_label "$repo"
    items+=("$REPLY: $id")
    prune_repos["$REPLY"]=1
  done
  if ((${#prunable[@]} > 0)); then
    if ((${#prunable[@]} == 1)); then
      label="1 prunable worktree entry"
    else
      label="${#prunable[@]} prunable worktree entries"
    fi
    # Name the repository when there is only one, so the command runs as
    # printed. A prune there would also drop the admin entry of a moved,
    # unrepaired checkout in that repository and orphan it, so then the
    # repair comes first and no prune is offered on its own.
    if ((${#prune_repos[@]} == 1)); then
      repo=${!prune_repos[*]}
      _dr_worktree_cmd_path "$repo" '<repo>'
      if [[ $REPLY != '<repo>' && -n ${moved_by_repo["$repo"]+x} ]]; then
        _dr_worktree_repair_first "$REPLY" "${moved_by_repo["$repo"]}"
        hint=$REPLY
      elif [[ -n ${moved_by_repo["$repo"]+x} ]]; then
        hint="their checkouts are gone, but pruning now would orphan the moved worktrees below: repair those first, then prune"
      else
        hint="their checkouts are gone: run 'git -C $REPLY worktree prune'"
      fi
    elif ((${#moved[@]} > 0)); then
      hint="their checkouts are gone, but pruning now would orphan the moved worktrees below: repair those first, then run 'git -C <repo> worktree prune' for each repository"
    else
      hint="their checkouts are gone: run 'git -C <repo> worktree prune' for each repository"
    fi
    _dr_list_row warn "$label" "$hint" "${items[@]}"
  fi
  if ((${#moved[@]} > 0)); then
    if ((${#moved[@]} == 1)); then
      label="1 moved worktree is not repaired"
      _dr_worktree_cmd_path "${moved_dirs[0]}" '<path>'
      hint="run 'git -C $REPLY worktree repair' (pruning would orphan it)"
    else
      label="${#moved[@]} moved worktrees are not repaired"
      hint="run 'git -C <path> worktree repair' in each (pruning would orphan them)"
    fi
    _dr_list_row warn "$label" "$hint" "${moved[@]}"
  fi

  items=()
  for entry in ${_DR_WORKTREE_ADMIN_LOCKED[@]+"${_DR_WORKTREE_ADMIN_LOCKED[@]}"}; do
    repo=${entry%%$'\t'*}
    id=${entry#*$'\t'}
    if [[ -n $id ]]; then
      _dr_worktree_label "$repo"
      items+=("$REPLY: $id (checkout missing)")
    else
      # Relative pointers arrive spelled through the admin entry; only those
      # need resolving (a subshell each).
      label=$repo
      case $repo in
        */../* | */./*) label=$(_dr_worktree_physical "$repo") ;;
      esac
      _dr_worktree_label "${label:-$repo}"
      items+=("$REPLY")
    fi
  done
  if ((${#items[@]} > 0)); then
    if ((${#items[@]} == 1)); then
      label="1 locked worktree"
      why="prune and dot-worktree-gc skip it until 'git worktree unlock'"
    else
      label="${#items[@]} locked worktrees"
      why="prune and dot-worktree-gc skip them until 'git worktree unlock'"
    fi
    # Information, not a step: a lock is usually deliberate.
    _dr_row info "$label" "$why" 0 "${items[@]}"
  fi
  return 0
}

# Fill _DR_WORKTREE_TOP with the largest measured du roots, up to three, as
# "path size" display items, largest first, from the sizes the disk pass
# already measured. With arguments, only those roots are ranked. One pass in
# Bash, no sort.
_DR_WORKTREE_TOP=()
_dr_worktree_top_roots() {
  local entry kib path i j
  local -a top_kib=() top_path=()
  local -A only=()
  for path; do
    only["$path"]=1
  done
  _DR_WORKTREE_TOP=()
  for entry in ${_DR_WORKTREE_DU_SIZES[@]+"${_DR_WORKTREE_DU_SIZES[@]}"}; do
    kib=${entry%%$'\t'*}
    path=${entry#*$'\t'}
    [[ $kib =~ ^[1-9][0-9]*$ ]] || continue
    (($# == 0)) || [[ -n ${only["$path"]+x} ]] || continue
    # Insert in descending order, keeping three.
    for ((i = 0; i < ${#top_kib[@]}; i++)); do
      ((kib > top_kib[i])) && break
    done
    ((i < 3)) || continue
    for ((j = ${#top_kib[@]}; j > i; j--)); do
      top_kib[j]=${top_kib[j - 1]}
      top_path[j]=${top_path[j - 1]}
    done
    top_kib[i]=$kib
    top_path[i]=$path
    if ((${#top_kib[@]} > 3)); then
      unset 'top_kib[3]' 'top_path[3]'
    fi
  done
  for ((i = 0; i < ${#top_kib[@]}; i++)); do
    _dr_worktree_label "${top_path[$i]}"
    _DR_WORKTREE_TOP+=("$REPLY $(_dr_worktree_human_bytes $((top_kib[i] * 1024)))")
  done
}

# Fill _DR_WORKTREE_FS with one "AVAILABLE-KiB<TAB>USED-KiB<TAB>mount point"
# entry per filesystem holding any of the given roots, or fail when df
# cannot tell. One bounded `df -Pk` covers every root: POSIX output keeps
# each filesystem on one line, so the fields split on blanks (the mount
# point, last, may itself contain blanks). A device name with blanks breaks
# that split, and that line is skipped as unknown.
_DR_WORKTREE_FS=()
_dr_worktree_free_space() {
  local out size used avail cap mount
  local -A seen=()
  _DR_WORKTREE_FS=()
  if declare -F _dr_run_bounded >/dev/null 2>&1; then
    out=$(_dr_run_bounded 5 df -Pk -- "$@" 2>/dev/null </dev/null) || [[ -n ${out:-} ]] || return 1
  else
    out=$(df -Pk -- "$@" 2>/dev/null </dev/null) || [[ -n ${out:-} ]] || return 1
  fi
  # The header line fails the numeric checks.
  # A full filesystem whose reserved blocks are in use reports a negative
  # Available (GNU and BSD alike): that is no space at all. A zero size
  # (some FUSE mounts) says nothing about space and is skipped.
  while read -r _ size used avail cap mount; do
    [[ $size =~ ^[0-9]+$ && $used =~ ^[0-9]+$ && $avail =~ ^-?[0-9]+$ &&
      $cap == *% && -n $mount ]] || continue
    ((size > 0)) || continue
    ((avail >= 0)) || avail=0
    [[ -z ${seen["$mount"]+x} ]] || continue
    seen["$mount"]=1
    _DR_WORKTREE_FS+=("$avail"$'\t'"$used"$'\t'"$mount")
  done <<<"$out"
  ((${#_DR_WORKTREE_FS[@]} > 0))
}

# Succeed when a filesystem with AVAILABLE and USED KiB is low on space:
# under _DR_WORKTREE_LOW_FREE_PERCENT of used plus available (root-reserved
# blocks are neither, as in df's capacity column) and under
# _DR_WORKTREE_LOW_FREE_BYTES.
_dr_worktree_fs_low() {
  local avail=$1 used=$2
  ((avail * 1024 < _DR_WORKTREE_LOW_FREE_BYTES)) &&
    ((avail * 100 < (used + avail) * _DR_WORKTREE_LOW_FREE_PERCENT))
}

# The disk row's inputs beyond COUNT and TOTAL, set by _dr_check_worktrees:
# the du roots, every checkout counted, and the clean stale or orphaned
# checkouts (dirty ones hold uncommitted work, so they are never culprits).
_DR_WORKTREE_DISK_ROOTS=()
_DR_WORKTREE_DISK_CHECKOUTS=()
_DR_WORKTREE_DISK_CULPRITS=()

# File the disk row for COUNT worktrees totalling TOTAL KiB. Within the size
# limit the row passes. Above it, the size alone is information: a busy
# development host keeps several large active trees (build output runs to
# gigabytes each), and a permanent warning about them would train the reader
# to skip the section's real warnings. It warns only when the clean stale
# and orphaned trees make up at least _DR_WORKTREE_DOMINANT_PERCENT of the
# bytes, so removing them is the fix, or when the emptiest filesystem holding
# a root is low on space (see _DR_WORKTREE_LOW_FREE_*). Sizes are per du
# root: a culprit root, or a grouping folder (a root with no `.git`), counts
# whole when every checkout under it is a culprit too; a culprit nested in
# an active checkout has no size of its own and counts as active. Without
# per-root sizes (the uncached du fallback) the share cannot be judged and
# the row says nothing about it. The df probe runs only above the limit.
_dr_worktree_report_disk() {
  local count=$1 total_kib=$2 entry kib path threshold total_human limit_human
  local reclaim_kib=0 free='' avail_kib mount='' hint reason root dir
  local dominant=0 low=0 any all
  local -a culprit_roots=()
  local -A culprits=() culprit_root=()

  threshold=$(_dr_worktree_warn_bytes)
  total_human=$(_dr_worktree_human_bytes $((total_kib * 1024)))
  local label="worktree disk $total_human across $count worktree"
  ((count == 1)) || label+="s"
  if ((total_kib * 1024 <= 10#$threshold)); then
    _dr_ok "$label"
    return 0
  fi
  limit_human=$(_dr_worktree_human_bytes "$threshold")

  for path in ${_DR_WORKTREE_DISK_CULPRITS[@]+"${_DR_WORKTREE_DISK_CULPRITS[@]}"}; do
    culprits["$path"]=1
  done
  for root in ${_DR_WORKTREE_DISK_ROOTS[@]+"${_DR_WORKTREE_DISK_ROOTS[@]}"}; do
    # A root counts whole only when nothing under it is active: a stale
    # root holding an active checkout, or a grouping folder (no `.git`)
    # holding one, is not reclaimable by removing it.
    any=0 all=1
    if [[ -n ${culprits["$root"]+x} ]]; then
      any=1
    elif [[ -e $root/.git ]]; then
      continue
    fi
    for dir in ${_DR_WORKTREE_DISK_CHECKOUTS[@]+"${_DR_WORKTREE_DISK_CHECKOUTS[@]}"}; do
      [[ $dir == "$root"/* ]] || continue
      any=1
      if [[ -z ${culprits["$dir"]+x} ]]; then
        all=0
        break
      fi
    done
    ((any == 0 || all == 0)) || culprit_root["$root"]=1
  done
  for entry in ${_DR_WORKTREE_DU_SIZES[@]+"${_DR_WORKTREE_DU_SIZES[@]}"}; do
    kib=${entry%%$'\t'*}
    path=${entry#*$'\t'}
    [[ $kib =~ ^[0-9]+$ && -n ${culprit_root["$path"]+x} ]] || continue
    reclaim_kib=$((reclaim_kib + kib))
    culprit_roots+=("$path")
  done
  if ((reclaim_kib > 0 && reclaim_kib * 100 >= total_kib * _DR_WORKTREE_DOMINANT_PERCENT)); then
    dominant=1
  fi
  # Every filesystem holding a root is judged; the row names the emptiest
  # low one, or the emptiest one when none is low.
  local best_avail=-1 low_avail=-1 used
  if ((${#_DR_WORKTREE_DISK_ROOTS[@]} > 0)) &&
    _dr_worktree_free_space "${_DR_WORKTREE_DISK_ROOTS[@]}"; then
    for entry in "${_DR_WORKTREE_FS[@]}"; do
      avail_kib=${entry%%$'\t'*}
      used=${entry#*$'\t'}
      path=${used#*$'\t'}
      used=${used%%$'\t'*}
      if _dr_worktree_fs_low "$avail_kib" "$used"; then
        if ((low_avail < 0 || avail_kib < low_avail)); then
          low_avail=$avail_kib
          low=1
          _dr_worktree_label "$path"
          free="$(_dr_worktree_human_bytes $((avail_kib * 1024))) free on $REPLY"
          mount=$REPLY
        fi
      elif ((low == 0 && (best_avail < 0 || avail_kib < best_avail))); then
        best_avail=$avail_kib
        _dr_worktree_label "$path"
        free="$(_dr_worktree_human_bytes $((avail_kib * 1024))) is free on $REPLY"
        mount=$REPLY
      fi
    done
  fi

  # Nothing needs doing here, so the reason is the row's detail, not a
  # next step: a next-step line always names something to do.
  if ((dominant == 0 && low == 0)); then
    _dr_worktree_top_roots
    # The detail renders inside the row's parentheses: keep it short.
    reason="above the $limit_human DOT_WORKTREE_WARN_BYTES limit, but"
    if ((${#_DR_WORKTREE_DU_SIZES[@]} > 0)); then
      reason+=" stale and orphaned trees hold under half of it"
      [[ -z $free ]] || reason+=" and"
    fi
    [[ -z $free ]] || reason+=" $free"
    [[ $reason != *', but' ]] || reason=${reason%, but}
    _dr_worktree_label_largest
    _dr_row info "$label" "$reason" 0 ${_DR_WORKTREE_TOP[@]+"${_DR_WORKTREE_TOP[@]}"}
    return 0
  fi
  if ((dominant == 1)); then
    label+=", $(_dr_worktree_human_bytes $((reclaim_kib * 1024))) of it stale or orphaned"
    _dr_worktree_top_roots "${culprit_roots[@]}"
    hint="remove those trees as the stale and orphan rows below say"
  else
    _dr_worktree_top_roots
    hint="remove finished worktrees ('dot-worktree-gc' lists stale ones) or other large files there"
  fi
  # Raising the limit would silence a real low-space warning, so it is
  # offered only when space is fine.
  if ((low == 1)); then
    label+="; only $free"
    hint="free space on $mount: $hint"
  else
    hint+=", or raise the $limit_human DOT_WORKTREE_WARN_BYTES limit"
  fi
  _dr_worktree_label_largest
  _dr_list_row warn "$label" "$hint" ${_DR_WORKTREE_TOP[@]+"${_DR_WORKTREE_TOP[@]}"}
}

# Mark the first _DR_WORKTREE_TOP item "largest: ", so the list says what
# it is both as items and when an older Dot joins it into one detail.
_dr_worktree_label_largest() {
  ((${#_DR_WORKTREE_TOP[@]} == 0)) || _DR_WORKTREE_TOP[0]="largest: ${_DR_WORKTREE_TOP[0]}"
}

# Report via REPLY the prune hint for REPO (a command-safe display path)
# when it also has moved, unrepaired checkouts (MOVED: display paths, one
# per line). Pruning first would orphan them, so the repair comes first:
# for one, from inside the checkout; for several, one command from the
# repository naming each new path (Git repairs them all). A path that
# cannot go into a command leaves only the instruction to repair them.
_dr_worktree_repair_first() {
  local repo=$1 listed=$2 path paths='' count=0 safe=1
  while IFS= read -r path; do
    count=$((count + 1))
    _dr_worktree_cmd_path "$path" ''
    [[ -n $REPLY ]] || safe=0
    paths+=" $REPLY"
  done <<<"$listed"
  if ((safe == 0)); then
    REPLY="their checkouts are gone, but pruning now would orphan the moved worktrees below: repair those first, then run 'git -C $repo worktree prune'"
  elif ((count == 1)); then
    REPLY="their checkouts are gone, but pruning now would orphan the moved worktree below: first run 'git -C${paths} worktree repair', then 'git -C $repo worktree prune'"
  else
    REPLY="their checkouts are gone, but pruning now would orphan the moved worktrees below: first run 'git -C $repo worktree repair${paths}', then 'git -C $repo worktree prune'"
  fi
}

# Report LABEL via REPLY when it can go into a printed command as is (no
# blank, quote, or other shell metacharacter; a leading `~/` expands), else
# PLACEHOLDER, so a hint never prints a command that does not run.
_dr_worktree_cmd_path() {
  if [[ $1 =~ ^[A-Za-z0-9_./~+@%:,=-]+$ ]]; then
    REPLY=$1
  else
    REPLY=$2
  fi
}

# Orphans _dr_check_worktrees found outside dot-worktree-gc's swept roots
# (a moved repository still lists them), which the gc never visits.
_DR_WORKTREE_ORPHANS_UNSWEPT=()

# Report orphaned checkouts (see _dr_worktree_orphan): their files are still
# on disk, but Git cannot reach them, so uncommitted work there is invisible
# to every other check. Every orphan is an item; Dot folds a long list to
# its first few, so the hint gives a command that lists them: the
# dot-worktree-gc dry run (without fetching) reports each one in its swept
# roots with either a preserved-pointer reason or a merged snapshot proof.
# The others are marked, so the hint's
# promise holds for every unmarked item.
_dr_worktree_report_orphans() {
  local dir label cause
  local -a items=()
  local -A unswept=()
  (($# > 0)) || return 0
  for dir in ${_DR_WORKTREE_ORPHANS_UNSWEPT[@]+"${_DR_WORKTREE_ORPHANS_UNSWEPT[@]}"}; do
    unswept["$dir"]=1
  done
  for dir in "$@"; do
    _dr_worktree_label "$dir"
    label=$REPLY
    cause=
    if _dr_worktree_orphan "$dir"; then
      _dr_worktree_orphan_cause "$REPLY"
      cause=$REPLY
    fi
    [[ -z ${unswept["$dir"]+x} ]] || cause+="${cause:+, }outside the swept roots"
    items+=("$label${cause:+ ($cause)}")
  done
  if (($# == 1)); then
    label="1 orphaned worktree (its Git metadata is gone)"
  else
    label="$# orphaned worktrees (their Git metadata is gone)"
  fi
  # Two steps, each on its own line on a newer Dot, so the listing command
  # ends its line and copies cleanly.
  if ((${#unswept[@]} == 0)); then
    cause="list every one with: dot-worktree-gc --no-fetch"
  else
    cause="list all but those marked 'outside the swept roots' with: dot-worktree-gc --no-fetch"
  fi
  _dr_row warn "$label" '' 2 "$cause" \
    "if the repository moved, run 'git -C <repo> worktree repair <path>', otherwise review the dry run and apply proven cleanup with --apply, or copy out any work before manual removal" \
    "${items[@]}"
}

# Report what the swept roots hold that no other row can name
# (_dr_worktree_odd_entries): quarantines a failed orphan cleanup left
# behind, whose files are otherwise never mentioned again, and checkouts
# whose path holds a newline, which the one-path-per-line enumeration skips
# (registered ones too, from the admin scan of this run).
_dr_worktree_report_odd() {
  local kind path dir label seen
  local -a quarantines=() newlines=()
  local -a listed=()
  # Paths are displayed in their escaped form (a newline shows as \n), the
  # same spelling the gc's records use.
  while IFS=$'\t' read -r kind path; do
    case $kind in
      quarantine) _dr_worktree_label "$path" && quarantines+=("$REPLY") ;;
      newline | newline-target)
        _dr_worktree_label "$path" && newlines+=("$REPLY")
        listed+=("$path")
        ;;
    esac
  done < <(_dr_worktree_odd_entries)
  # Registered checkouts anywhere, unless the swept-root scan above already
  # named the same one.
  for dir in ${_DR_WORKTREE_ADMIN_LIVE[@]+"${_DR_WORKTREE_ADMIN_LIVE[@]}"}; do
    [[ $dir == *$'\n'* ]] || continue
    _dr_worktree_escape "$dir"
    path=$_DR_WORKTREE_ESCAPED
    for seen in ${listed[@]+"${listed[@]}"}; do
      [[ $seen != "$path" ]] || continue 2
    done
    _dr_worktree_label "$path"
    newlines+=("$REPLY")
  done
  if ((${#quarantines[@]} > 0)); then
    label="${#quarantines[@]} quarantine"
    ((${#quarantines[@]} == 1)) || label+="s"
    label+=" left by a failed orphan cleanup"
    _dr_list_row warn "$label" \
      "inspect each, recover any files you need, then remove it by hand" \
      "${quarantines[@]}"
  fi
  if ((${#newlines[@]} > 0)); then
    label="${#newlines[@]} worktree path"
    ((${#newlines[@]} == 1)) || label+="s"
    label+=" with a newline (not checked)"
    _dr_list_row warn "$label" "rename it so the path holds no newline" \
      "${newlines[@]}"
  fi
  return 0
}

_dr_check_worktrees() {
  _dr_section "Worktrees"

  _DR_WORKTREE_BASE_KEYS=()
  _DR_WORKTREE_BASE_REFS=()
  _DR_WORKTREE_FACT_KEYS=()
  _DR_WORKTREE_FACT_ROWS=()
  _DR_WORKTREE_STALE_ENTRIES=()
  _DR_WORKTREE_REMOTE_HEADS=$'\n'
  _DR_WORKTREE_BARE=$'\n'
  _dr_worktree_resolve_git
  _dr_worktree_clone_roots_load

  local home=${HOME:-}
  local home_phys dotfiles_phys dotfiles dir
  local -a dirs=()

  home_phys=$(_dr_worktree_physical "$home")
  [[ -n $home_phys ]] || home_phys=$home
  _DR_WORKTREE_HOME_PHYS=$home_phys
  dotfiles_phys=
  _dr_worktree_base_gitdir
  dotfiles=$REPLY
  if [[ -n $dotfiles && -d $dotfiles ]]; then
    dotfiles_phys=$(_dr_worktree_physical "$dotfiles")
  fi

  # Swept candidates plus every checkout a clone registered; only the swept
  # ones are dot-worktree-gc's to remove, which the stale hint reflects.
  local tag
  local -A seen=() swept=()
  while IFS=$'\t' read -r tag dir; do
    [[ -n $dir && -d $dir && $dir != "$home_phys" ]] || continue
    [[ -z $dotfiles_phys || $dir != "$dotfiles_phys" ]] || continue
    seen["$dir"]=1
    [[ $tag != S ]] || swept["$dir"]=1
  done < <(_dr_worktree_tagged_candidates)
  if ((${#seen[@]} > 0)); then
    mapfile -t dirs < <(printf '%s\n' "${!seen[@]}" | LC_ALL=C sort)
  fi
  # The enumeration above ran in a subshell; rescan the admin areas here
  # (file reads plus the clone roots cached at the start of this run) so the
  # prunable and locked lists reach the report.
  _dr_worktree_admin_scan

  # A checkout nested inside another candidate is measured through that
  # parent, so du never counts the same bytes twice. A folder in a shared
  # root that only groups checkouts (no `.git` of its own) still carries the
  # bytes of anything nested in it, so it stays a du root, but it is not a
  # worktree: the count and the staleness probe skip it.
  local all=$'\n' parent
  local -a du_roots=() kept=()
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    all+="$dir"$'\n'
  done
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    parent=${dir%/*}
    while [[ -n $parent && $parent != "$home_phys" ]]; do
      [[ $all == *$'\n'"$parent"$'\n'* ]] && break
      parent=${parent%/*}
    done
    [[ -n $parent && $parent != "$home_phys" ]] || du_roots+=("$dir")
    [[ ! -e $dir/.git && $all == *$'\n'"$dir"/* ]] || kept+=("$dir")
  done
  dirs=(${kept[@]+"${kept[@]}"})

  local count=${#dirs[@]}
  if ((count == 0)); then
    _dr_ok "no worktrees found"
    _dr_worktree_report_odd
    _dr_worktree_report_admin
    return 0
  fi

  # Orphans count as worktrees (their bytes are real) but stay out of every
  # Git probe: each would only fail.
  local -a live=() orphans=()
  for dir in "${dirs[@]}"; do
    if _dr_worktree_orphan "$dir"; then
      orphans+=("$dir")
    else
      live+=("$dir")
    fi
  done

  # One du pass over the top-level checkouts, cached by root mtimes;
  # no deep traversal beyond what du -s already summarizes.
  local total_kib=0
  _DR_WORKTREE_DU_SIZES=()
  if command -v du >/dev/null 2>&1; then
    _dr_worktree_du_measure "${du_roots[@]}"
    total_kib=$REPLY
    case $total_kib in
      "" | *[!0-9]*) total_kib=0 ;;
    esac
  fi

  # Only checkouts with no recent Git activity reach the staleness probe;
  # young ones cost nothing beyond the single find pass.
  _dr_worktree_old_checkouts "$_DR_WORKTREE_STALE_DAYS" ${live[@]+"${live[@]}"}

  local stale_count=0 dirty_count=0 manual_count=0 repair_count=0 reason changed i hint
  local merged_count=0 gone_count=0 entry manual label
  local -a dirty_items=() hit_dirs=() hit_reasons=()
  local -a manual_items=() auto_items=() opaque=() opaque_items=() stale_dirs=()
  _DR_WORKTREE_PROBE_SET=$'\n'
  for dir in ${_DR_WORKTREE_OLD[@]+"${_DR_WORKTREE_OLD[@]}"}; do
    _DR_WORKTREE_PROBE_SET+="$dir"$'\n'
  done
  _dr_worktree_prefetch_rows ${_DR_WORKTREE_OLD[@]+"${_DR_WORKTREE_OLD[@]}"}
  for dir in ${_DR_WORKTREE_OLD[@]+"${_DR_WORKTREE_OLD[@]}"}; do
    # Locked checkouts are never swept and have their own row (for clone
    # roots); keep every locked one out of the stale and dirty lists.
    _dr_worktree_is_locked "$dir" && continue
    _dr_worktree_stale_reason_batched "$dir" || true
    reason=$REPLY
    if [[ $reason == '?' ]]; then
      opaque+=("$dir")
      _dr_worktree_label "$dir"
      opaque_items+=("$REPLY")
    elif [[ -n $reason ]]; then
      hit_dirs+=("$dir")
      hit_reasons+=("$reason")
    fi
  done
  unset _DR_WORKTREE_PROBE_SET

  # A merged or abandoned branch with uncommitted work is not garbage: name
  # it as dirty so nobody deletes it on the strength of "merged".
  _dr_worktree_parallel _dr_worktree_dirty_count ${hit_dirs[@]+"${hit_dirs[@]}"}
  for ((i = 0; i < ${#hit_dirs[@]}; i++)); do
    dir=${hit_dirs[$i]}
    reason=${hit_reasons[$i]}
    changed=${_DR_WORKTREE_PAR_OUT[$i]}
    _dr_worktree_label "$dir"
    label=$REPLY
    if [[ $changed == 0 ]]; then
      stale_count=$((stale_count + 1))
      case $reason in
        merged\ *) merged_count=$((merged_count + 1)) ;;
        *) gone_count=$((gone_count + 1)) ;;
      esac
      # dot-worktree-gc removes only linked worktrees in its swept roots: a
      # standalone clone parked in a worktree root is a main checkout it
      # always keeps, and a worktree another clone registered elsewhere
      # belongs to whatever tool made it. Those are marked for removal by
      # hand and listed first, since the gc's dry run never offers them.
      # A checkout holding another one is kept too: removing it would
      # delete the nested checkout with it.
      entry=
      if ! _dr_worktree_is_linked "$dir"; then
        entry=", standalone clone"
      elif [[ -z ${swept["$dir"]+x} ]]; then
        entry=", outside the swept roots"
      elif [[ $all == *$'\n'"$dir"/* ]]; then
        entry=", contains another checkout"
      else
        # Checkouts the gc's own gates keep, so its dry run never offers
        # them either.
        _dr_worktree_gc_keeps "$dir" "$reason"
        entry=$REPLY
      fi
      manual=$entry
      stale_dirs+=("$dir")
      _DR_WORKTREE_STALE_ENTRIES+=("$dir"$'\t'"$reason$manual")
      if [[ -n $manual ]]; then
        manual_count=$((manual_count + 1))
        # A moved checkout needs repairing, not deleting.
        if [[ $manual == ", moved without repair" ]]; then
          repair_count=$((repair_count + 1))
          manual_items+=("$label ($reason$manual, run 'git worktree repair' in it)")
        else
          manual_items+=("$label ($reason$manual, delete by hand)")
        fi
      else
        auto_items+=("$label ($reason)")
      fi
    else
      dirty_count=$((dirty_count + 1))
      if [[ $changed == '?' ]]; then
        changed="git status failed"
      else
        changed="$changed uncommitted"
      fi
      # No "; " inside an item: an older Dot joins items with it.
      dirty_items+=("$label ($changed, $reason)")
    fi
  done

  # The disk row comes first but needs the stale and orphan lists to
  # judge its severity.
  _DR_WORKTREE_DISK_ROOTS=(${du_roots[@]+"${du_roots[@]}"})
  _DR_WORKTREE_DISK_CHECKOUTS=("${dirs[@]}")
  _DR_WORKTREE_DISK_CULPRITS=(${stale_dirs[@]+"${stale_dirs[@]}"} ${orphans[@]+"${orphans[@]}"})
  _dr_worktree_report_disk "$count" "$total_kib"

  if ((stale_count == 0)); then
    _dr_ok "no stale worktrees"
  else
    label="$stale_count stale worktree"
    ((stale_count == 1)) || label+="s"
    label+=" (older than $_DR_WORKTREE_STALE_DAYS days)"
    hint=
    ((merged_count == 0)) || hint="$merged_count merged"
    ((gone_count == 0)) || hint+="${hint:+, }$gone_count with upstream gone"
    label+=": $hint"
    hint=
    if ((repair_count > 0 && manual_count == stale_count)); then
      hint="handle them by hand as each entry says: dot-worktree-gc keeps them"
      ((stale_count > 1)) || hint="handle it by hand as its entry says: dot-worktree-gc keeps it"
    elif ((manual_count == 1 && stale_count == 1)); then
      hint="delete it by hand once reviewed: dot-worktree-gc keeps it"
    elif ((manual_count == stale_count)); then
      hint="delete them by hand once reviewed: dot-worktree-gc keeps them"
    else
      hint="run 'dot-worktree-gc' (dry run; also lists merged branches across clones), then 'dot-worktree-gc --apply' (deletes those branches too; untracked or ignored content other than tagged caches and cleanupRepo.worktreePrunePath entries keeps a checkout)"
      ((manual_count == repair_count)) ||
        hint+="; delete those marked 'delete by hand' yourself"
      ((repair_count == 0)) ||
        hint+="; repair those marked for 'git worktree repair' first"
    fi
    _dr_list_row warn "$label" "$hint" \
      ${manual_items[@]+"${manual_items[@]}"} ${auto_items[@]+"${auto_items[@]}"}
  fi
  if ((dirty_count > 0)); then
    if ((dirty_count == 1)); then
      label="1 inactive worktree has uncommitted changes"
    else
      label="$dirty_count inactive worktrees have uncommitted changes"
    fi
    _dr_list_row warn "$label" \
      "commit or discard them first: dot-worktree-gc keeps them (it prunes only tagged caches and cleanupRepo.worktreePrunePath entries)" "${dirty_items[@]}"
  fi
  if ((${#opaque[@]} > 0)); then
    if ((${#opaque[@]} == 1)); then
      label="1 inactive worktree Git cannot inspect"
      _dr_worktree_cmd_path "${opaque_items[0]}" '<path>'
      hint="run 'git -C $REPLY status' to see why"
    else
      label="${#opaque[@]} inactive worktrees Git cannot inspect"
      hint="run 'git -C <path> status' in each to see why"
    fi
    _dr_list_row warn "$label" "$hint" "${opaque_items[@]}"
  fi
  _DR_WORKTREE_ORPHANS_UNSWEPT=()
  for dir in ${orphans[@]+"${orphans[@]}"}; do
    [[ -n ${swept["$dir"]+x} ]] || _DR_WORKTREE_ORPHANS_UNSWEPT+=("$dir")
  done
  _dr_worktree_report_orphans ${orphans[@]+"${orphans[@]}"}
  _dr_worktree_report_odd
  _dr_worktree_report_admin ${live[@]+"${live[@]}"}
  return 0
}
