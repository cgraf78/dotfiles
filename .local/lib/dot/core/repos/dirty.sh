# shellcheck shell=bash
# Dirty-worktree detection and normalization.
#
# `dot update --cron` depends on these helpers staying conservative: only
# content-clean mtime/filter noise and out-of-band writes that exactly match
# origin/main are repaired automatically. Real local edits must continue to
# block cron updates.

# Returns 0 (true) if there are uncommitted changes in any repo.
_is_worktree_dirty() {
  if [[ -d "$DOTFILES" ]]; then
    if ! $GIT diff-index --quiet HEAD 2>/dev/null; then
      return 0
    fi
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path
    IFS='|' read -r _ path _ <<<"$entry"
    if [[ -d "$path/.git" ]]; then
      if ! git -C "$path" diff-index --quiet HEAD 2>/dev/null; then
        return 0
      fi
    fi
  done
  return 1
}

# Revert only the currently-dirty tracked files, one at a time. The caller has
# already verified (via _dirty_files_match_ref) that every dirty file matches the
# remote, so scope the checkout to exactly that set instead of `checkout -- .`,
# which would revert anything else that happens to differ from HEAD.
_checkout_dirty_files() {
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    "$@" checkout -- "$f" 2>/dev/null || true
  done < <("$@" diff-index --name-only HEAD 2>/dev/null)
}

# Attempt to resolve dirty worktrees caused by out-of-band writes that
# match what's on the remote. Returns 0 if all repos are clean after resolution.
_try_resolve_dirty() {
  local dirty=0
  if [[ -d "$DOTFILES" ]] && ! $GIT diff-index --quiet HEAD 2>/dev/null; then
    $GIT fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote; then
      # shellcheck disable=SC2086  # $GIT is intentionally word-split
      _checkout_dirty_files $GIT
    else
      dirty=1
    fi
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path
    IFS='|' read -r _ path _ <<<"$entry"
    if [[ -d "$path/.git" ]] && ! git -C "$path" diff-index --quiet HEAD 2>/dev/null; then
      git -C "$path" fetch --quiet origin 2>/dev/null || true
      if _dirty_files_match_ref "$path" git -C "$path"; then
        _checkout_dirty_files git -C "$path"
      else
        dirty=1
      fi
    fi
  done
  return "$dirty"
}

# Check if every dirty file in a repo matches content on origin/main.
_dirty_files_match_ref() {
  local worktree="$1" remote_ref="origin/main"
  shift
  local dirty_files
  dirty_files=$("$@" diff-index --name-only HEAD 2>/dev/null) || return 1
  "$@" rev-parse --verify "$remote_ref" &>/dev/null || return 1
  while IFS= read -r f; do
    local work_hash remote_hash
    work_hash=$("$@" hash-object "$worktree/$f" 2>/dev/null) || return 1
    remote_hash=$("$@" rev-parse "$remote_ref:$f" 2>/dev/null) || return 1
    [[ "$work_hash" == "$remote_hash" ]] || return 1
  done <<<"$dirty_files"
  return 0
}

# Check if base repo dirty files match origin/main.
# shellcheck disable=SC2086  # $GIT is intentionally word-split
_dirty_files_match_remote() {
  _dirty_files_match_ref "$HOME" $GIT
}

# Re-checkout the stat-dirty-but-content-clean (mtime-only) files in one repo.
# Only reverts files whose content matches HEAD, so real edits are left alone.
_normalize_dirty_files() {
  local dirty f
  dirty=$("$@" diff-files --name-only 2>/dev/null) || return 0
  [[ -n "$dirty" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if "$@" diff --quiet -- "$f" 2>/dev/null; then
      "$@" checkout -- "$f" 2>/dev/null || true
    fi
  done <<<"$dirty"
}

# Re-checkout files that are stat-dirty but content-clean across base + overlays.
_normalize_filtered() {
  if [[ -d "$DOTFILES" ]]; then
    # shellcheck disable=SC2086  # $GIT is intentionally word-split
    _normalize_dirty_files $GIT
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path
    IFS='|' read -r _ path _ <<<"$entry"
    if [[ -d "$path/.git" ]]; then
      _normalize_dirty_files git -C "$path"
    fi
  done
}
