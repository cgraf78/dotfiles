# shellcheck shell=bash
# dot doctor: worktree disk and staleness hygiene.
#
# Warn-only by design: nothing here fails the doctor run and nothing touches
# the checkouts. Disk pressure and abandoned worktrees are owner decisions;
# this check only makes them visible.
#
# A checkout is stale when it shows no Git activity for the stale window and
# its branch is merged or its upstream is gone; a stale checkout with
# uncommitted changes is reported as dirty instead, because dot-worktree-gc
# will refuse it. Clone roots' worktree admin areas are read directly, so
# checkouts registered anywhere count, and prunable or locked admin entries
# are reported.
#
# The disk threshold defaults to 10 GiB and is overridable with
# DOT_WORKTREE_WARN_BYTES (plain integer bytes; anything else falls back to
# the default). Dot config keys are engine-owned, so a DOT_* environment knob
# follows the codebase's existing pattern for client behavior switches.

_DR_WORKTREE_WARN_BYTES_DEFAULT=10737418240
_DR_WORKTREE_STALE_DAYS=14
_DR_WORKTREE_STALE_LIST_LIMIT=5

# Git binary for every probe in this file; empty means plain `git` from PATH
# (dot-worktree-gc sources these helpers and never sets it).
_DR_WORKTREE_GIT=

_dr_git() {
  "${_DR_WORKTREE_GIT:-git}" "$@"
}

# Resolve the real Git behind the dotfiles PATH launcher into
# _DR_WORKTREE_GIT. The launcher pays a Bash startup plus shell-loader on
# every call (tens of ms each on a loaded host, dozens of calls per run) and
# routes non-repository HOME descendants to the base repository. Every probe
# here names its repository explicitly (`-C <checkout>`), so the routing buys
# nothing and a stray non-repository path must fail instead of answering for
# the base repository. Skips the launcher the way launcher-real.sh does: by
# identity and, for any other launcher copy, by its marker line. When nothing
# else qualifies it falls back to plain `git` (the launcher itself): slower,
# but every probe still passes an explicit repository. Read-only: unlike the
# launcher, it never publishes a resolution cache. Never fails.
_dr_worktree_resolve_git() {
  local launcher=$HOME/.local/bin/git marker='# Dotfiles-aware launcher for Git.'
  local search=${PATH:-} dir candidate line

  _DR_WORKTREE_GIT=
  while [[ -n $search ]]; do
    dir=${search%%:*}
    case $dir in
      '') dir=. ;;
      \~) dir=$HOME ;;
      \~/*) dir=$HOME/${dir#\~/} ;;
    esac
    candidate=$dir/git
    if [[ -x $candidate && ! -d $candidate ]] &&
      ! [[ -e $launcher && $candidate -ef $launcher ]]; then
      line=
      # Bounded reads: a binary's first "line" can be arbitrarily long.
      {
        IFS= read -r -n 256 line && IFS= read -r -n 256 line
      } 2>/dev/null <"$candidate" || line=
      if [[ $line != "$marker" ]]; then
        _DR_WORKTREE_GIT=$candidate
        return 0
      fi
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
  printf '%s\n' "$override"
}

# Format a byte count for display (10G, 800M, ...). Display only; the
# threshold comparison always uses exact integers.
_dr_worktree_human_bytes() {
  local bytes=$1

  awk -v bytes="$bytes" 'BEGIN {
    if (bytes >= 1073741824) printf "%.1fG", bytes / 1073741824
    else if (bytes >= 1048576) printf "%.0fM", bytes / 1048576
    else if (bytes >= 1024) printf "%.0fK", bytes / 1024
    else printf "%dB", bytes
  }'
}

# Print the physical path of a candidate checkout, or nothing when it cannot
# be resolved. Never fails.
_dr_worktree_physical() {
  (cd -- "$1" 2>/dev/null && pwd -P 2>/dev/null) || true
}

# Print the common Git directory of every clone root whose worktree admin
# area the scan reads: the base client's separate Git directory, every
# ~/git/* clone, and the ~/.dotfiles-* overlay clones. Never fails.
_dr_worktree_clone_commons() {
  local home=${HOME:-} common

  if [[ -n ${DOTFILES:-} && -d ${DOTFILES:-} ]]; then
    printf '%s\n' "$DOTFILES"
  fi
  for common in "$home"/git/*/.git "$home"/.dotfiles-*/.git; do
    [[ -d $common ]] && printf '%s\n' "$common"
  done
  return 0
}

# Read every clone root's `worktrees/<id>/gitdir` pointers directly, without
# a Git process, and sort the entries into three global arrays:
#   _DR_WORKTREE_ADMIN_LIVE      registered checkouts that still exist, as
#                                written (callers resolve physical paths)
#   _DR_WORKTREE_ADMIN_PRUNABLE  "repo<TAB>id" for entries `git worktree
#                                prune` would remove (missing or empty gitdir
#                                pointer, or a checkout that no longer exists)
#   _DR_WORKTREE_ADMIN_LOCKED    "path<TAB>" for locked live checkouts and
#                                "repo<TAB>id" for locked entries whose
#                                checkout is gone; prune never removes either
# Paths stay raw so dot-worktree-gc, which shares the enumeration but not the
# doctor display helpers, can call this too.
# This finds checkouts a repository registered anywhere (for example a
# shared ~/worktrees root no fixed folder scan covers) and the admin entries
# a fixed folder scan cannot see at all. Relative pointers
# (worktree.useRelativePaths) resolve against the admin entry. Must run in
# the main shell. Never fails.
_dr_worktree_admin_scan() {
  local common admin id target repo
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
        IFS= read -r target 2>/dev/null <"$admin/gitdir" || true
      fi
      case $target in
        '' | /*) ;;
        *) target=$admin/$target ;;
      esac
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
  done < <(_dr_worktree_clone_commons)
  return 0
}

# Print one candidate worktree checkout per line. Sources, in order:
#   1. linked checkouts registered by any clone root (authoritative; catches
#      worktrees kept anywhere, including repo-local and shared roots),
#   2. children of the shared worktree roots (every repo, plus orphaned
#      checkouts git no longer tracks),
#   3. repo-local .worktrees children under every clone root: ~/git plus
#      the ~/.dotfiles-* overlay clones, which are repos like any other,
#   4. children of any extra roots passed as arguments.
# Callers dedupe and exclude the live checkout. Never fails.
# Extra roots arrive from out-of-file callers (dot-worktree-gc); the
# in-file doctor call intentionally passes none.
# shellcheck disable=SC2120
_dr_worktree_candidates() {
  local home=${HOME:-} root dir child extra

  [[ -n $home && -d $home ]] || return 0

  _dr_worktree_admin_scan
  for dir in ${_DR_WORKTREE_ADMIN_LIVE[@]+"${_DR_WORKTREE_ADMIN_LIVE[@]}"}; do
    [[ -d $dir ]] || continue
    _dr_worktree_physical "$dir"
  done

  for root in "$home/.worktrees" "$home/git/worktrees"; do
    [[ -d $root ]] || continue
    for child in "$root"/*/; do
      [[ -d $child ]] || continue
      _dr_worktree_physical "${child%/}"
    done
  done

  for dir in "$home"/git/*/.worktrees/ "$home"/.dotfiles-*/.worktrees/; do
    [[ -d $dir ]] || continue
    for child in "$dir"*/; do
      [[ -d $child ]] || continue
      _dr_worktree_physical "${child%/}"
    done
  done

  for extra in "$@"; do
    [[ -d $extra ]] || continue
    for child in "$extra"/*/; do
      [[ -d $child ]] || continue
      _dr_worktree_physical "${child%/}"
    done
  done
  return 0
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
    (cd -- "$gitpath" 2>/dev/null && pwd -P 2>/dev/null) || return 1
    return 0
  fi
  [[ -f $gitpath ]] || return 1
  IFS= read -r first 2>/dev/null <"$gitpath" || return 1
  case $first in
    'gitdir: '?*) target=${first#gitdir: } ;;
    *) return 1 ;;
  esac
  [[ -n $target ]] || return 1
  case $target in
    /*) phys=$(cd -- "$target" 2>/dev/null && pwd -P 2>/dev/null) || return 1 ;;
    *) phys=$(cd -- "$dir/$target" 2>/dev/null && pwd -P 2>/dev/null) || return 1 ;;
  esac
  parent=${phys%/*}
  case $parent in
    */worktrees) printf '%s\n' "${parent%/*}" ;;
    *) printf '%s\n' "$phys" ;;
  esac
}

# Print the local base ref (short remote form, e.g. origin/main) for a
# checkout, without touching the network, or fail. Mirrors the gc's
# origin-first resolution: the origin HEAD symref, then the sole
# remote's HEAD when there is exactly one remote, then conventional
# origin names. With several remotes a fork's HEAD must never win by
# enumeration order. Every candidate must resolve to a commit; stale
# symrefs fall through instead of failing closed wrong. Keep in sync
# with _worktree_gc_local_base_ref.
_dr_worktree_base_ref() {
  local dir=$1 ref head_info default_ref candidate
  local -a remotes=()
  ref=$(_dr_git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null) || ref=
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
# Keep in sync with _worktree_gc_base_ref_cached.
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

# Report why an old checkout counts as stale (its branch is merged into
# the upstream default or its upstream is gone) via REPLY, or "". The
# caller gates on age with a single find pass so young checkouts cost
# no git spawns here. Non-git checkouts, detached HEAD, repos without
# remotes, and missing tools all report "". Never fails; never touches
# the network. Must run in the main shell so the per-repo base cache
# survives across checkouts.
_dr_worktree_stale_reason() {
  local dir=$1
  local branch upstream_info upstream_short upstream_track
  local default_ref

  REPLY=
  command -v git >/dev/null 2>&1 || return 0
  [[ -e $dir/.git ]] || return 0

  branch=$(_dr_git -C "$dir" branch --show-current 2>/dev/null) || return 0
  [[ -n $branch ]] || return 0

  # One ref query reports the configured upstream even after it is pruned.
  upstream_info=$(_dr_git -C "$dir" for-each-ref --format='%(upstream:short)%09%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || return 0
  IFS=$'\t' read -r upstream_short upstream_track <<<"$upstream_info"
  if [[ $upstream_track == "[gone]" ]]; then
    REPLY="upstream ${upstream_short:-$branch} is gone"
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
  local i path ref phys reason entry name short track symref origin_head=''
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
    # The same query reads origin's HEAD symref, the first base-ref
    # candidate, so the common case resolves the base with no extra spawn.
    # for-each-ref omits a dangling symref, so a listed one names a ref
    # that exists; anything else takes the full resolution chain. Fields
    # carry a tag because TAB is IFS whitespace: `read` would collapse the
    # empty upstream fields of the symref row and shift its target.
    tracking=$(_dr_git -C "$dir" for-each-ref \
      --format='%(refname)%09u=%(upstream:short)%09t=%(upstream:track)%09s=%(symref)' \
      "${refs[@]}" refs/remotes/origin/HEAD 2>/dev/null) || return 1
    while IFS=$'\t' read -r name short track symref; do
      if [[ $name == refs/remotes/origin/HEAD ]]; then
        symref=${symref#s=}
        [[ $symref == refs/remotes/?*/?* ]] && origin_head=${symref#refs/remotes/}
        continue
      fi
      [[ -n $name && $track != "t=[gone]" ]] && need_base=1
    done <<<"$tracking"
    if ((need_base == 1)); then
      if [[ -n $origin_head ]]; then
        base=$origin_head
        [[ -z $key ]] || _dr_worktree_base_ref_seed "$key" "$base"
      elif _dr_worktree_base_ref_ensure "$dir"; then
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
      while IFS=$'\t' read -r name short track symref; do
        [[ $name == "$ref" ]] || continue
        short=${short#u=}
        if [[ $track == "t=[gone]" ]]; then
          reason="upstream ${short:-${ref#refs/heads/}} is gone"
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
  if ! command -v git >/dev/null 2>&1 || ! key=$(_dr_worktree_repo_key "$dir"); then
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

# Print the du total in KiB for the checkout roots, re-measuring only the
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
_dr_worktree_cached_du_total() {
  local key cache now header stamp='' line kib mtime path out total=0
  local fresh_entries='' full=0 i tmp
  local -a changed=() changed_mtimes=()
  # Associative lookups: substring searches over the joined entry text cost
  # quadratic time in Bash and took seconds with a hundred roots.
  local -A cached=() measured=()

  if ! key=$(_dr_worktree_key_lines "$@"); then
    _dr_worktree_du_total "$@"
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
  printf '%s\n' "$total"
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

# Succeed when the checkout is a linked worktree: its `.git` is a pointer
# into a repository's `worktrees/` admin area. Reads the pointer only.
_dr_worktree_is_linked() {
  local first
  [[ -f $1/.git ]] || return 1
  IFS= read -r first 2>/dev/null <"$1/.git" || return 1
  [[ $first == 'gitdir: '*/worktrees/?* ]]
}

# Succeed when a linked checkout is locked, whichever repository owns it:
# Git marks the lock in the admin entry its `.git` pointer names.
_dr_worktree_is_locked() {
  local first admin
  [[ -f $1/.git ]] || return 1
  IFS= read -r first 2>/dev/null <"$1/.git" || return 1
  case $first in
    'gitdir: '/*) admin=${first#gitdir: } ;;
    'gitdir: '?*) admin=$1/${first#gitdir: } ;;
    *) return 1 ;;
  esac
  [[ -e $admin/locked ]]
}

# Report a checkout's uncommitted state via REPLY: the number of changed
# or untracked entries ("0" when clean), or "?" when Git cannot inspect it.
# The same `status --porcelain` view dot-worktree-gc uses to refuse a dirty
# checkout, so doctor never suggests a sweep the gc will decline.
# --no-optional-locks keeps the probe from refreshing the index, which
# would both write into the checkout and reset its activity signal, and
# fsmonitor stays off so no watcher daemon starts per checkout.
_dr_worktree_dirty_count() {
  local out count=0 line
  REPLY='?'
  out=$(_dr_git --no-optional-locks -c core.fsmonitor=false \
    -C "$1" status --porcelain 2>/dev/null) || return 0
  while IFS= read -r line; do
    [[ -n $line ]] && count=$((count + 1))
  done <<<"$out"
  REPLY=$count
}

# Join "a; b; c" from up to _DR_WORKTREE_STALE_LIST_LIMIT samples plus an
# "and N more" tail for TOTAL entries, via REPLY.
_dr_worktree_join_samples() {
  local total=$1 sample
  shift
  REPLY=
  for sample in "$@"; do
    REPLY+=${REPLY:+; }$sample
  done
  if ((total > $#)); then
    REPLY+="; and $((total - $#)) more"
  fi
}

# Report registered admin entries that need an owner decision: prunable
# entries (warn, with the prune command) and locked entries (reported for
# visibility; a lock is deliberate, but a forgotten one hides a checkout
# from prune and from dot-worktree-gc forever).
_dr_worktree_report_admin() {
  local entry repo id label
  local -a samples=()

  for entry in ${_DR_WORKTREE_ADMIN_PRUNABLE[@]+"${_DR_WORKTREE_ADMIN_PRUNABLE[@]}"}; do
    ((${#samples[@]} < _DR_WORKTREE_STALE_LIST_LIMIT)) || break
    repo=${entry%%$'\t'*}
    id=${entry#*$'\t'}
    samples+=("$(_dr_tilde "$repo"): $id")
  done
  if ((${#_DR_WORKTREE_ADMIN_PRUNABLE[@]} > 0)); then
    _dr_worktree_join_samples "${#_DR_WORKTREE_ADMIN_PRUNABLE[@]}" "${samples[@]}"
    if ((${#_DR_WORKTREE_ADMIN_PRUNABLE[@]} == 1)); then
      label="1 prunable worktree entry"
    else
      label="${#_DR_WORKTREE_ADMIN_PRUNABLE[@]} prunable worktree entries"
    fi
    _dr_warn "$label" "$REPLY; their checkouts are gone: run 'git -C <repo> worktree prune'"
  fi

  samples=()
  for entry in ${_DR_WORKTREE_ADMIN_LOCKED[@]+"${_DR_WORKTREE_ADMIN_LOCKED[@]}"}; do
    ((${#samples[@]} < _DR_WORKTREE_STALE_LIST_LIMIT)) || break
    repo=${entry%%$'\t'*}
    id=${entry#*$'\t'}
    if [[ -n $id ]]; then
      samples+=("$(_dr_tilde "$repo"): $id (checkout missing)")
    else
      # Relative pointers arrive spelled through the admin entry.
      label=$(_dr_worktree_physical "$repo")
      samples+=("$(_dr_tilde "${label:-$repo}")")
    fi
  done
  if ((${#_DR_WORKTREE_ADMIN_LOCKED[@]} > 0)); then
    _dr_worktree_join_samples "${#_DR_WORKTREE_ADMIN_LOCKED[@]}" "${samples[@]}"
    if ((${#_DR_WORKTREE_ADMIN_LOCKED[@]} == 1)); then
      label="1 locked worktree"
    else
      label="${#_DR_WORKTREE_ADMIN_LOCKED[@]} locked worktrees"
    fi
    _dr_info "$label" "$REPLY; prune and dot-worktree-gc skip them until 'git worktree unlock'"
  fi
  return 0
}

_dr_check_worktrees() {
  _dr_section "Worktrees"

  _DR_WORKTREE_BASE_KEYS=()
  _DR_WORKTREE_BASE_REFS=()
  _DR_WORKTREE_FACT_KEYS=()
  _DR_WORKTREE_FACT_ROWS=()
  _dr_worktree_resolve_git

  local home=${HOME:-}
  local home_phys dotfiles_phys dir
  local -a dirs=()

  home_phys=$(cd -- "$home" 2>/dev/null && pwd -P 2>/dev/null) || home_phys=$home
  dotfiles_phys=
  if [[ -n ${DOTFILES:-} && -d ${DOTFILES:-} ]]; then
    dotfiles_phys=$(cd -- "$DOTFILES" 2>/dev/null && pwd -P 2>/dev/null) || dotfiles_phys=
  fi

  # shellcheck disable=SC2119 # the doctor call intentionally passes no extra roots
  while IFS= read -r dir || [[ -n $dir ]]; do
    if [[ -z $dir || ! -d $dir ]]; then
      continue
    fi
    if [[ $dir == "$home_phys" ]]; then
      continue
    fi
    if [[ -n $dotfiles_phys && $dir == "$dotfiles_phys" ]]; then
      continue
    fi
    dirs+=("$dir")
  done < <(_dr_worktree_candidates | LC_ALL=C sort -u)
  # The enumeration above ran in a subshell; rescan the admin areas here
  # (file reads only) so the prunable and locked lists reach the report.
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
    _dr_worktree_report_admin
    return 0
  fi

  # One du pass over the top-level checkouts, cached by root mtimes;
  # no deep traversal beyond what du -s already summarizes.
  local total_kib=0
  if command -v du >/dev/null 2>&1; then
    total_kib=$(_dr_worktree_cached_du_total "${du_roots[@]}")
    case $total_kib in
      "" | *[!0-9]*) total_kib=0 ;;
    esac
  fi
  local total_bytes=$((total_kib * 1024))
  local threshold total_human threshold_human
  threshold=$(_dr_worktree_warn_bytes)
  total_human=$(_dr_worktree_human_bytes "$total_bytes")
  threshold_human=$(_dr_worktree_human_bytes "$threshold")
  if [[ $total_bytes -gt $((10#$threshold)) ]]; then
    _dr_warn "worktree disk $total_human across $count worktrees" \
      "warn above $threshold_human (DOT_WORKTREE_WARN_BYTES)"
  else
    _dr_ok "worktree disk $total_human across $count worktrees"
  fi

  # Only checkouts with no recent Git activity reach the staleness probe;
  # young ones cost nothing beyond the single find pass.
  _dr_worktree_old_checkouts "$_DR_WORKTREE_STALE_DAYS" "${dirs[@]}"

  local stale_count=0 dirty_count=0 clone_count=0 reason changed i hint
  local -a stale_samples=() dirty_samples=() hit_dirs=() hit_reasons=()
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
    if [[ -n $reason ]]; then
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
    if [[ $changed == 0 ]]; then
      stale_count=$((stale_count + 1))
      # dot-worktree-gc removes only linked worktrees; a standalone clone
      # parked in a worktree root is a main checkout it always keeps.
      if ! _dr_worktree_is_linked "$dir"; then
        clone_count=$((clone_count + 1))
        reason+=", standalone clone"
      fi
      if ((${#stale_samples[@]} < _DR_WORKTREE_STALE_LIST_LIMIT)); then
        stale_samples+=("$(_dr_tilde "$dir") ($reason)")
      fi
    else
      dirty_count=$((dirty_count + 1))
      if [[ $changed == '?' ]]; then
        changed="git status failed"
      else
        changed="$changed uncommitted"
      fi
      if ((${#dirty_samples[@]} < _DR_WORKTREE_STALE_LIST_LIMIT)); then
        dirty_samples+=("$(_dr_tilde "$dir") ($changed; $reason)")
      fi
    fi
  done

  if ((stale_count == 0)); then
    _dr_ok "no stale worktrees"
  else
    if ((clone_count == 0)); then
      hint="review with 'dot-worktree-gc' (dry run by default)"
    elif ((clone_count == stale_count)); then
      hint="dot-worktree-gc never removes standalone clones: delete them by hand once reviewed"
    else
      hint="review linked worktrees with 'dot-worktree-gc' (dry run by default); delete standalone clones by hand"
    fi
    _dr_worktree_join_samples "$stale_count" "${stale_samples[@]}"
    if ((stale_count == 1)); then
      _dr_warn "1 stale worktree (older than $_DR_WORKTREE_STALE_DAYS days)" "$REPLY; $hint"
    else
      _dr_warn "$stale_count stale worktrees (older than $_DR_WORKTREE_STALE_DAYS days)" "$REPLY; $hint"
    fi
  fi
  if ((dirty_count > 0)); then
    _dr_worktree_join_samples "$dirty_count" "${dirty_samples[@]}"
    if ((dirty_count == 1)); then
      _dr_warn "1 inactive worktree has uncommitted changes" \
        "$REPLY; commit or discard them first: dot-worktree-gc skips dirty checkouts"
    else
      _dr_warn "$dirty_count inactive worktrees have uncommitted changes" \
        "$REPLY; commit or discard them first: dot-worktree-gc skips dirty checkouts"
    fi
  fi
  _dr_worktree_report_admin
  return 0
}
