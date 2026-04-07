#!/bin/bash
# Shared helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
WORK_DIR="$HOME/.dotfiles-work"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"

# Print a message unless quiet mode is active.
_log() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "$@"
}

# Print a message to stderr regardless of quiet mode.
_warn() {
  echo "$@" >&2
}

_logfile_create() {
  local log=""
  if ! log=$(mktemp 2>/dev/null); then
    REPLY=""
    return 1
  fi
  REPLY="$log"
}

_logfile_print() {
  local label="$1"
  local log="$2"
  [[ -n "$log" && -s "$log" ]] || return 0
  _warn "  $label output:"
  sed 's/^/    /' "$log" >&2
}

_run_quiet_logged() {
  local label="$1"
  local warning="$2"
  shift 2

  local log=""
  if ! _logfile_create; then
    "$@" >/dev/null 2>&1 || _warn "  warning: $warning"
    return 0
  fi
  log="$REPLY"

  if "$@" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi

  _logfile_print "$label" "$log"
  rm -f "$log"
  _warn "  warning: $warning"
  return 0
}

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
    if [[ -e "$HOME/$file" || -L "$HOME/$file" ]]; then
      mkdir -p "$backup/$(dirname "$file")"
      mv "$HOME/$file" "$backup/$file"
      ((count++)) || true
    fi
  done <<< "$files"

  if [[ "$count" -eq 0 ]]; then
    rmdir "$backup" 2>/dev/null || true
    return 1
  fi

  _warn "  backed up $count conflicting untracked files to $backup"
  REPLY="$backup"
  return 0
}

_pull_personal() {
  local log=""
  if ! _logfile_create; then
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      $GIT pull --quiet "$@"
    else
      $GIT pull "$@"
    fi
    return $?
  fi
  log="$REPLY"

  local rc=0
  if [[ "$DOT_QUIET" -eq 1 ]]; then
    $GIT pull --quiet "$@" >"$log" 2>&1 || rc=$?
  else
    $GIT pull "$@" >"$log" 2>&1 || rc=$?
  fi

  if [[ "$rc" -ne 0 ]] && _backup_pull_conflicts "$log"; then
    : > "$log"
    rc=0
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      $GIT pull --quiet "$@" >"$log" 2>&1 || rc=$?
    else
      $GIT pull "$@" >"$log" 2>&1 || rc=$?
    fi
  fi

  if [[ "$DOT_QUIET" -ne 1 && -s "$log" ]]; then
    cat "$log"
  fi

  rm -f "$log"
  return "$rc"
}

# Restore git-tracked versions of skip-worktree files so pull won't
# conflict with work symlinks.  The work bootstrap re-symlinks and
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

# Pull work repo (without running bootstrap).
_pull_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  _log "==> Pulling work dotfiles..."
  if [[ "$DOT_QUIET" -eq 1 ]]; then
    _run_quiet_logged \
      "work dotfiles pull" \
      "work dotfiles pull failed" \
      git -C "$WORK_DIR" pull --quiet "$@"
  else
    git -C "$WORK_DIR" pull "$@" || _warn "  warning: work dotfiles pull failed"
  fi
}

# Run work bootstrap (symlinks, app config merges).
# Separated from _pull_work_repo so callers can run deps between pull and bootstrap.
_run_work_bootstrap() {
  [[ -d "$WORK_DIR" && -x "$WORK_DIR/bootstrap" ]] || return 0
  if [[ "$DOT_QUIET" -eq 1 ]]; then
    _run_quiet_logged \
      "work bootstrap" \
      "work bootstrap failed" \
      "$WORK_DIR/bootstrap"
  else
    "$WORK_DIR/bootstrap" || true
  fi
}

# Push work repo.
_push_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  _log "==> Pushing work dotfiles..."
  git -C "$WORK_DIR" push "$@" || _warn "  warning: work dotfiles push failed"
}

# Run all app config merge scripts (iTerm2, Karabiner, VS Code, etc.).
_run_merges() {
  for _script in "$HOME/.config/dot"/merge-*.sh; do
    [[ -f "$_script" ]] || continue
    # shellcheck source=/dev/null
    . "$_script"
    _fn="merge_${_script##*merge-}"; _fn="${_fn%.sh}"
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      _run_quiet_logged "$_fn" "$_fn failed" "$_fn"
    else
      "$_fn" || true
    fi
  done
}

# ---------------------------------------------------------------------------
# Dependency management (deps.sh)
# ---------------------------------------------------------------------------

# shellcheck source=deps.sh
. "${BASH_SOURCE[0]%/*}/deps.sh"

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

# Check if every dirty file in a repo matches the content on a remote ref.
# $1 = "personal" or "work"
_dirty_files_match_remote() {
  local repo="$1" remote_ref="origin/main"
  local dirty_files
  if [[ "$repo" == "personal" ]]; then
    dirty_files=$($GIT diff-index --name-only HEAD 2>/dev/null) || return 1
    $GIT rev-parse --verify "$remote_ref" &>/dev/null || return 1
    while IFS= read -r f; do
      local work_hash remote_hash
      # diff-index paths are relative to work-tree ($HOME for bare repo)
      work_hash=$($GIT hash-object "$HOME/$f" 2>/dev/null) || return 1
      remote_hash=$($GIT rev-parse "$remote_ref:$f" 2>/dev/null) || return 1
      [[ "$work_hash" == "$remote_hash" ]] || return 1
    done <<< "$dirty_files"
  else
    dirty_files=$(git -C "$WORK_DIR" diff-index --name-only HEAD 2>/dev/null) || return 1
    git -C "$WORK_DIR" rev-parse --verify "$remote_ref" &>/dev/null || return 1
    while IFS= read -r f; do
      local work_hash remote_hash
      work_hash=$(git -C "$WORK_DIR" hash-object "$WORK_DIR/$f" 2>/dev/null) || return 1
      remote_hash=$(git -C "$WORK_DIR" rev-parse "$remote_ref:$f" 2>/dev/null) || return 1
      [[ "$work_hash" == "$remote_hash" ]] || return 1
    done <<< "$dirty_files"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Cron install from tracked file
# ---------------------------------------------------------------------------

DOT_CRON_FILE="$HOME/.config/dot/cron"
DOT_CRON_LOCAL="$HOME/.config/dot/cron.local"
DOT_CRON_MARKER="# dot-managed-cron"

# Build a clean PATH for cron from the current PATH.
# Keeps: $HOME dirs, /opt/homebrew, /usr/local, and standard system dirs.
# Drops: obscure system dirs (cryptex, munki, etc.) that clutter the crontab.
_cron_path() {
  local result="" dir _dirs
  IFS=: read -ra _dirs <<< "$HOME/.local/bin:$PATH"
  for dir in "${_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    [[ ":$result:" == *":$dir:"* ]] && continue
    # Keep user dirs, homebrew, /usr/local, and standard system dirs.
    case "$dir" in
      "$HOME"/*|/opt/homebrew/*|/usr/local/bin|/usr/bin|/bin|/usr/sbin|/sbin) ;;
      *) continue ;;
    esac
    result="${result:+$result:}$dir"
  done
  echo "$result"
}

# Parse a cron file: expand $HOME in entries, skip comments/blanks.
# Appends processed lines to $DOT_CRON_PARSED (caller must initialize).
_parse_cron_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    line="${line//\$HOME/$HOME}"
    if [[ -n "$DOT_CRON_PARSED" ]]; then
      DOT_CRON_PARSED="$DOT_CRON_PARSED"$'\n'"$line"
    else
      DOT_CRON_PARSED="$line"
    fi
  done < "$file"
}

# Install cron entries from ~/.config/dot/cron (tracked) and
# ~/.config/dot/cron.local (machine-local, untracked) into the user crontab.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment.
# Idempotent — skips if the installed block already matches.
_install_cron() {
  [[ -f "$DOT_CRON_FILE" || -f "$DOT_CRON_LOCAL" ]] || return 0

  DOT_CRON_PARSED=""
  _parse_cron_file "$DOT_CRON_FILE"
  _parse_cron_file "$DOT_CRON_LOCAL"

  local block_start="$DOT_CRON_MARKER begin"
  local block_end="$DOT_CRON_MARKER end"
  local current
  current=$(crontab -l 2>/dev/null || true)

  # No active entries — strip any existing managed block and return.
  if [[ -z "$DOT_CRON_PARSED" ]]; then
    if [[ "$current" == *"$block_start"* ]]; then
      local stripped
      stripped=$(echo "$current" | sed "/$block_start/,/$block_end/d")
      if [[ -n "$stripped" ]]; then
        echo "$stripped" | crontab -
      else
        crontab -r 2>/dev/null || true
      fi
      _log "  cron entries removed"
    fi
    return 0
  fi

  local cron_path
  cron_path=$(_cron_path)
  local managed_block="$block_start"$'\n'"PATH=$cron_path"$'\n'"$DOT_CRON_PARSED"$'\n'"$block_end"

  # Already installed with same content — nothing to do.
  if [[ "$current" == *"$managed_block"* ]]; then
    _log "  cron up to date"
    return 0
  fi

  # Strip any existing managed block.
  local filtered
  if [[ "$current" == *"$block_start"* ]]; then
    filtered=$(echo "$current" | sed "/$block_start/,/$block_end/d")
  else
    filtered="$current"
  fi

  # Append the new managed block.
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="$filtered"$'\n\n'"$managed_block"
  else
    new_crontab="$managed_block"
  fi

  echo "$new_crontab" | crontab -
  _log "  cron installed"
}
