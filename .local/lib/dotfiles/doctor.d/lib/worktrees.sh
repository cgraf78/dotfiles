# shellcheck shell=bash
# dot doctor: worktree disk and staleness hygiene.
#
# Warn-only by design: nothing here fails the doctor run and nothing touches
# the checkouts. Disk pressure and abandoned worktrees are owner decisions;
# this check only makes them visible.
#
# The disk threshold defaults to 10 GiB and is overridable with
# DOT_WORKTREE_WARN_BYTES (plain integer bytes; anything else falls back to
# the default). Dot config keys are engine-owned, so a DOT_* environment knob
# follows the codebase's existing pattern for client behavior switches.

_DR_WORKTREE_WARN_BYTES_DEFAULT=10737418240
_DR_WORKTREE_STALE_DAYS=14
_DR_WORKTREE_STALE_LIST_LIMIT=5

# Per-run base-ref cache, keyed by repo identity (see
# _dr_worktree_repo_key). Checkouts of one repo share a single base
# resolution instead of each paying up to five git probes. Reset on
# every _dr_check_worktrees call; parallel indexed arrays keep the file
# on its existing shell requirements.
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

# Print one candidate worktree checkout per line. Sources, in order:
#   1. base repository linked worktrees (authoritative; catches worktrees
#      kept anywhere, including repo-local and shared roots),
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
  local home=${HOME:-} root dir child line path extra

  [[ -n $home && -d $home ]] || return 0

  if command -v git >/dev/null 2>&1 && [[ -n ${DOTFILES:-} && -d ${DOTFILES:-} ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      case $line in
        "worktree "*) path=${line#worktree } ;;
        *) continue ;;
      esac
      [[ -n $path && -d $path ]] || continue
      _dr_worktree_physical "$path"
    done < <(git --git-dir="$DOTFILES" --work-tree="$home" worktree list --porcelain 2>/dev/null)
  fi

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
  IFS= read -r first <"$gitpath" 2>/dev/null || return 1
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

  branch=$(git -C "$dir" branch --show-current 2>/dev/null) || return 0
  [[ -n $branch ]] || return 0

  # One ref query reports the configured upstream even after it is pruned.
  upstream_info=$(git -C "$dir" for-each-ref --format='%(upstream:short)%09%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || return 0
  IFS=$'\t' read -r upstream_short upstream_track <<<"$upstream_info"
  if [[ $upstream_track == "[gone]" ]]; then
    REPLY="upstream ${upstream_short:-$branch} is gone"
    return 0
  fi

  _dr_worktree_base_ref_ensure "$dir" || return 0
  default_ref=$REPLY
  REPLY=
  if git -C "$dir" merge-base --is-ancestor HEAD "$default_ref" 2>/dev/null; then
    REPLY="merged into $default_ref"
  fi
  return 0
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

# Print the du total in KiB for the checkout roots, recomputing only
# when a checkout root changed. The cache key is each root's mtime plus
# the root set itself, so checkout add/remove and top-level entry
# changes recompute; nested-only growth reuses the last total until the
# next root change. That staleness is the documented cost of skipping
# the du pass: this check is warn-only and the total is advisory. A
# six-hour max age bounds the staleness so a never-touched root set
# cannot report a stale total indefinitely.
# Never fails: every cache problem falls back to a fresh du pass, and
# a failed store is silently skipped for the next run to retry.
_dr_worktree_cached_du_total() {
  local key cache stored_total stored_key fresh tmp now mtime
  if ! key=$(_dr_worktree_key_lines "$@"); then
    _dr_worktree_du_total "$@"
    return 0
  fi
  cache=$(_dr_worktree_du_cache_file)
  now=$(date +%s 2>/dev/null) || now=
  if [[ -n $now ]]; then
    mtime=$(stat -c %Y "$cache" 2>/dev/null) ||
      mtime=$(stat -f %m "$cache" 2>/dev/null) || mtime=
  else
    mtime=
  fi
  if [[ -n $mtime ]] && ((now - mtime > 21600)); then
    : # stale stamp: fall through to a fresh du pass below
  elif stored_total=$(head -n 1 "$cache" 2>/dev/null) &&
    [[ -n $stored_total && $stored_total != *[!0-9]* ]] &&
    stored_key=$(tail -n +2 "$cache" 2>/dev/null) &&
    [[ $stored_key == "$key" ]]; then
    printf '%s\n' "$stored_total"
    return 0
  fi
  fresh=$(_dr_worktree_du_total "$@")
  mkdir -p "${cache%/*}" 2>/dev/null || true
  if tmp=$(mktemp "${cache}.tmp.XXXXXX" 2>/dev/null) &&
    printf '%s\n%s\n' "$fresh" "$key" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$cache" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  printf '%s\n' "$fresh"
}

_dr_check_worktrees() {
  _dr_section "Worktrees"

  _DR_WORKTREE_BASE_KEYS=()
  _DR_WORKTREE_BASE_REFS=()

  local home=${HOME:-}
  local home_phys dotfiles_phys dir
  local -a dirs=()
  local -a stale_samples=()

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

  local count=${#dirs[@]}
  if ((count == 0)); then
    _dr_ok "no worktrees found"
    return 0
  fi

  # One du pass over the top-level checkouts, cached by root mtimes;
  # no deep traversal beyond what du -s already summarizes.
  local total_kib=0
  if command -v du >/dev/null 2>&1; then
    total_kib=$(_dr_worktree_cached_du_total "${dirs[@]}")
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

  # One find pass gates staleness probing to old checkouts; young ones cost
  # nothing beyond this. Partial results survive: discarding them when one
  # path vanishes mid-pass would silently mute every stale warning.
  local -a old_dirs=()
  local old_list
  old_list=$(find "${dirs[@]}" -maxdepth 0 -mtime +"$_DR_WORKTREE_STALE_DAYS" 2>/dev/null) || true
  while IFS= read -r dir || [[ -n $dir ]]; do
    [[ -n $dir ]] || continue
    old_dirs+=("$dir")
  done <<<"$old_list"

  local stale_count=0 reason sample detail
  for dir in ${old_dirs[@]+"${old_dirs[@]}"}; do
    _dr_worktree_stale_reason "$dir" || true
    reason=$REPLY
    if [[ -z $reason ]]; then
      continue
    fi
    stale_count=$((stale_count + 1))
    if ((${#stale_samples[@]} < _DR_WORKTREE_STALE_LIST_LIMIT)); then
      stale_samples+=("$(_dr_tilde "$dir") ($reason)")
    fi
  done

  if ((stale_count == 0)); then
    _dr_ok "no stale worktrees"
    return 0
  fi
  detail=
  for sample in ${stale_samples[@]+"${stale_samples[@]}"}; do
    if [[ -n $detail ]]; then
      detail+='; '
    fi
    detail+=$sample
  done
  if ((stale_count > ${#stale_samples[@]})); then
    detail+="; and $((stale_count - ${#stale_samples[@]})) more"
  fi
  if ((stale_count == 1)); then
    _dr_warn "1 stale worktree (older than $_DR_WORKTREE_STALE_DAYS days)" "$detail"
  else
    _dr_warn "$stale_count stale worktrees (older than $_DR_WORKTREE_STALE_DAYS days)" "$detail"
  fi
  return 0
}
