# shellcheck shell=bash
# Repository management: backup, pull, push, link, and dirty-check
# for both personal (bare) and work dotfiles repos.

_backup_dir() {
  local root="$HOME/.dotfiles-backup"
  mkdir -p "$root"
  local backup=""
  if ! backup=$(mktemp -d "$root/backup.XXXXXXXX" 2>/dev/null); then
    REPLY=""
    return 1
  fi
  REPLY="$backup"
}

_pull_conflicts_from_log() {
  local log="$1"
  awk '
    /untracked working tree files would be overwritten by/ {
      in_conflicts = 1
      next
    }
    in_conflicts && /^[[:space:]]+[^[:space:]]/ {
      sub(/^[[:space:]]+/, "")
      print
      next
    }
    in_conflicts { exit }
  ' "$log"
}

_backup_pull_conflicts() {
  local log="$1"
  local root="${2:-$HOME}"
  local files=""
  files=$(_pull_conflicts_from_log "$log") || true
  [[ -n "$files" ]] || return 1

  local backup=""
  if ! _backup_dir; then
    return 1
  fi
  backup="$REPLY"

  local file count=0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if [[ -e "$root/$file" || -L "$root/$file" ]]; then
      mkdir -p "$backup/$(dirname "$file")"
      mv "$root/$file" "$backup/$file"
      ((count++)) || true
    fi
  done <<<"$files"

  if [[ "$count" -eq 0 ]]; then
    rmdir "$backup" 2>/dev/null || true
    return 1
  fi

  _warn "  backed up $count conflicting untracked files to $backup"
  REPLY="$backup"
  return 0
}

# Run a git pull, appending --quiet in cron mode.
# Remaining args: the full git pull command.
_pull_cmd() {
  if [[ "$DOT_QUIET" -eq 1 ]]; then
    "$@" --quiet
  else
    "$@"
  fi
}

# Generic pull with optional logging, conflict backup, and retry.
# $1 = backup root for conflict resolution
# Remaining args: the full git pull command to run.
_pull_repo() {
  local backup_root="$1"
  shift
  local log=""
  if ! _logfile_create; then
    _pull_cmd "$@"
    return $?
  fi
  log="$REPLY"

  local rc=0
  _pull_cmd "$@" >"$log" 2>&1 || rc=$?

  if [[ "$rc" -ne 0 ]] && _backup_pull_conflicts "$log" "$backup_root"; then
    : >"$log"
    rc=0
    _pull_cmd "$@" >"$log" 2>&1 || rc=$?
  fi

  if [[ "$DOT_QUIET" -ne 1 && -s "$log" ]]; then
    _log_dim "$(cat "$log")"
  fi

  rm -f "$log"
  return "$rc"
}

# Ensure pull-behavior and filter config is set for both repos.
# Called by _finalize_update so it runs in dot update, dot pull, and dotbootstrap.
_ensure_repo_config() {
  # Apply git config to a single repo. $1... is the git command prefix
  # (e.g. "$GIT" or "git -C $WORK_DIR").
  # shellcheck disable=SC2086  # git_cmd is intentionally word-split.
  _apply_repo_config() {
    local git_cmd="$*"
    # Rebase on pull to keep linear history; stash dirty files automatically.
    $git_cmd config pull.rebase true 2>/dev/null || true
    $git_cmd config rebase.autoStash true 2>/dev/null || true
    # Let git status update the index for files that are stat-dirty but
    # content-clean after clean filter comparison. Without this, files
    # modified by external tools (e.g. Claude Code stripping trailing
    # newlines) show as phantom dirty even though git diff shows nothing.
    $git_cmd config diff.autoRefreshIndex true 2>/dev/null || true
    # Remove old json-sort filter (had both clean+smudge, which prevented
    # git from updating the stat cache — root cause of phantom dirty).
    # Safe to remove once all machines have run dot update (2026-04+).
    $git_cmd config --unset filter.json-sort.clean 2>/dev/null || true
    $git_cmd config --unset filter.json-sort.smudge 2>/dev/null || true
    # Clean-only filter: sort JSON keys on commit for stable diffs.
    # No smudge — blob content goes directly to disk on checkout.
    # A smudge filter would prevent diff.autoRefreshIndex from working.
    $git_cmd config filter.json-normalize.clean "jq --sort-keys ." 2>/dev/null || true
  }
  # shellcheck disable=SC2086  # $GIT is intentionally word-split.
  [[ -d "$DOTFILES" ]] && _apply_repo_config $GIT
  [[ -d "$WORK_DIR/.git" ]] && _apply_repo_config git -C "$WORK_DIR"
  unset -f _apply_repo_config
}

# shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
_pull_personal() {
  _pull_repo "$HOME" $GIT pull "$@"
}

# Restore git-tracked versions of skip-worktree files so pull won't
# conflict with work symlinks.  _link_work_home re-symlinks and
# re-sets skip-worktree after pull.
_unstash_work_overrides() {
  [[ -d "$WORK_DIR" ]] || return 0
  local files
  files=$($GIT ls-files -v 2>/dev/null | awk '/^S /{print $2}') || true
  [[ -n "$files" ]] || return 0
  echo "$files" | while IFS= read -r f; do
    $GIT update-index --no-skip-worktree "$f" 2>/dev/null || true
    $GIT checkout -- "$f" 2>/dev/null || true
  done
}

# Pull work repo.
_pull_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  _log_header "==> Pulling work dotfiles..."
  _pull_repo "$WORK_DIR" git -C "$WORK_DIR" pull "$@" ||
    _warn "  warning: work dotfiles pull failed"
  return 0
}

# Link work dotfiles into $HOME.
# Creates relative symlinks from $HOME for each file in $WORK_DIR/home/.
# Sets skip-worktree on personal-repo-tracked files that work symlinks shadow.
_link_work_home() {
  local work_home="$WORK_DIR/home"
  [[ -d "$work_home" ]] || return 0
  _log_header "==> Linking work dotfiles..."
  while IFS= read -r src; do
    local rel="${src#"$work_home"/}"
    local dst="$HOME/$rel"
    mkdir -p "$(dirname "$dst")"
    # Build relative symlink: ../ for each dir level, then .dotfiles-work/home/rel
    local depth
    depth=$(echo "$rel" | tr -cd '/' | wc -c)
    local prefix=""
    for ((i = 0; i < depth; i++)); do prefix="../$prefix"; done
    local target="${prefix}.dotfiles-work/home/$rel"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$target" ]]; then
      # Correct symlink already exists — just ensure skip-worktree
      if $GIT ls-files --error-unmatch "$rel" &>/dev/null; then
        $GIT update-index --skip-worktree "$rel" 2>/dev/null || true
      fi
      continue
    fi
    ln -sf "$target" "$dst"
    if $GIT ls-files --error-unmatch "$rel" &>/dev/null; then
      $GIT update-index --skip-worktree "$rel" 2>/dev/null || true
      _log_ok "  linked (override): $rel"
    else
      _log_ok "  linked: $rel"
    fi
  done < <(find "$work_home" -type f ! -name '*.~[0-9]*~')
}

# Push work repo.
_push_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  _log_header "==> Pushing work dotfiles..."
  git -C "$WORK_DIR" push "$@" || _warn "  warning: work dotfiles push failed"
}

# ---------------------------------------------------------------------------
# Worktree dirty check
# ---------------------------------------------------------------------------

# Returns 0 (true) if there are uncommitted changes in either repo.
_is_worktree_dirty() {
  if [[ -d "$DOTFILES" ]]; then
    if ! $GIT diff-index --quiet HEAD 2>/dev/null; then
      return 0
    fi
  fi
  if [[ -d "$WORK_DIR/.git" ]]; then
    if ! git -C "$WORK_DIR" diff-index --quiet HEAD 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Attempt to resolve dirty worktrees caused by dotsync writing files that
# match what's on the remote.  Fetches origin, then for each dirty file
# checks whether its working-tree content matches origin/main.  If every
# dirty file matches, discards the local copy (the pull will bring the
# same content).  Returns 0 if both repos are clean after resolution.
_try_resolve_dirty() {
  local dirty=0
  if [[ -d "$DOTFILES" ]] && ! $GIT diff-index --quiet HEAD 2>/dev/null; then
    $GIT fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote personal; then
      $GIT checkout -- . 2>/dev/null || true
    else
      dirty=1
    fi
  fi
  if [[ -d "$WORK_DIR/.git" ]] && ! git -C "$WORK_DIR" diff-index --quiet HEAD 2>/dev/null; then
    git -C "$WORK_DIR" fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote work; then
      git -C "$WORK_DIR" checkout -- . 2>/dev/null || true
    else
      dirty=1
    fi
  fi
  return "$dirty"
}

# Check if every dirty file in a repo matches content on origin/main.
# $1 = worktree root (for hash-object paths)
# remaining args = git command prefix (word-split $GIT or "git -C <dir>")
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

# $1 = "personal" or "work"
_dirty_files_match_remote() {
  # shellcheck disable=SC2086  # $GIT is intentionally word-split
  if [[ "$1" == "personal" ]]; then
    _dirty_files_match_ref "$HOME" $GIT
  else
    _dirty_files_match_ref "$WORK_DIR" git -C "$WORK_DIR"
  fi
}

# Re-checkout files that are stat-dirty but content-clean (mtime-only).
# Not needed for settings.json (diff.autoRefreshIndex + clean-only filter
# handles that natively), but still useful for other tracked files where
# cp/mv changes mtime without changing content.
_normalize_filtered() {
  local dirty
  dirty=$($GIT diff-files --name-only 2>/dev/null) || true
  if [[ -n "$dirty" ]]; then
    echo "$dirty" | while IFS= read -r f; do
      if $GIT diff --quiet -- "$f" 2>/dev/null; then
        $GIT checkout -- "$f" 2>/dev/null || true
      fi
    done
  fi
  if [[ -d "$WORK_DIR/.git" ]]; then
    dirty=$(git -C "$WORK_DIR" diff-files --name-only 2>/dev/null) || true
    if [[ -n "$dirty" ]]; then
      echo "$dirty" | while IFS= read -r f; do
        if git -C "$WORK_DIR" diff --quiet -- "$f" 2>/dev/null; then
          git -C "$WORK_DIR" checkout -- "$f" 2>/dev/null || true
        fi
      done
    fi
  fi
}
