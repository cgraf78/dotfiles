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
#   3. repo-local .worktrees children under the default clone root.
# Callers dedupe and exclude the live checkout. Never fails.
_dr_worktree_candidates() {
  local home=${HOME:-} root dir child line path

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

  if [[ -d $home/git ]]; then
    for dir in "$home"/git/*/.worktrees/; do
      [[ -d $dir ]] || continue
      for child in "$dir"*/; do
        [[ -d $child ]] || continue
        _dr_worktree_physical "${child%/}"
      done
    done
  fi
  return 0
}

# Print why an old checkout counts as stale (its branch is merged into the
# upstream default or its upstream is gone), or nothing. The caller gates on
# age with a single find pass so young checkouts cost no git spawns here.
# Non-git checkouts, detached HEAD, repos without remotes, and missing tools
# all report nothing. Never fails; never touches the network.
_dr_worktree_stale_reason() {
  local dir=$1
  local branch upstream_info upstream_short upstream_track
  local head_info default_ref

  command -v git >/dev/null 2>&1 || return 0
  [[ -e $dir/.git ]] || return 0

  branch=$(git -C "$dir" branch --show-current 2>/dev/null) || return 0
  [[ -n $branch ]] || return 0

  # One ref query reports the configured upstream even after it is pruned.
  upstream_info=$(git -C "$dir" for-each-ref --format='%(upstream:short)%09%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || return 0
  IFS=$'\t' read -r upstream_short upstream_track <<<"$upstream_info"
  if [[ $upstream_track == "[gone]" ]]; then
    printf 'upstream %s is gone\n' "${upstream_short:-$branch}"
    return 0
  fi

  head_info=$(git -C "$dir" for-each-ref --format='%(symref)' 'refs/remotes/*/HEAD' 2>/dev/null) || return 0
  default_ref=${head_info%%$'\n'*}
  case $default_ref in
    refs/remotes/*) default_ref=${default_ref#refs/remotes/} ;;
    *) return 0 ;;
  esac
  if git -C "$dir" merge-base --is-ancestor HEAD "$default_ref" 2>/dev/null; then
    printf 'merged into %s\n' "$default_ref"
  fi
  return 0
}

_dr_check_worktrees() {
  _dr_section "Worktrees"

  local home=${HOME:-}
  local home_phys dotfiles_phys dir
  local -a dirs=()
  local -a stale_samples=()

  home_phys=$(cd -- "$home" 2>/dev/null && pwd -P 2>/dev/null) || home_phys=$home
  dotfiles_phys=
  if [[ -n ${DOTFILES:-} && -d ${DOTFILES:-} ]]; then
    dotfiles_phys=$(cd -- "$DOTFILES" 2>/dev/null && pwd -P 2>/dev/null) || dotfiles_phys=
  fi

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

  # One du pass over the top-level checkouts; no deep traversal beyond what
  # du -s already summarizes.
  local total_kib=0 du_out
  if command -v du >/dev/null 2>&1; then
    du_out=$(du -sk -- "${dirs[@]}" 2>/dev/null | awk '{sum += $1} END {print sum + 0}') || du_out=0
    case $du_out in
      "" | *[!0-9]*) total_kib=0 ;;
      *) total_kib=$du_out ;;
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
  # nothing beyond this.
  local -a old_dirs=()
  local old_list
  old_list=$(find "${dirs[@]}" -maxdepth 0 -mtime +"$_DR_WORKTREE_STALE_DAYS" 2>/dev/null) || old_list=
  while IFS= read -r dir || [[ -n $dir ]]; do
    [[ -n $dir ]] || continue
    old_dirs+=("$dir")
  done <<<"$old_list"

  local stale_count=0 reason sample detail
  for dir in ${old_dirs[@]+"${old_dirs[@]}"}; do
    reason=$(_dr_worktree_stale_reason "$dir") || reason=
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
