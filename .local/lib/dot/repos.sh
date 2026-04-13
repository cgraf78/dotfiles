# shellcheck shell=bash
# Repository management: backup, pull, push, link, and dirty-check
# for the base (bare) repo and overlay repos.

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

# Ensure pull-behavior and filter config is set for all repos.
# Called by _finalize_update so it runs in dot update, dot pull, and dotbootstrap.
_ensure_repo_config() {
  # Apply git config to a single repo. $1... is the git command prefix.
  # shellcheck disable=SC2086  # git_cmd is intentionally word-split.
  _apply_repo_config() {
    local git_cmd="$*"
    $git_cmd config pull.rebase true 2>/dev/null || true
    $git_cmd config rebase.autoStash true 2>/dev/null || true
    $git_cmd config diff.autoRefreshIndex true 2>/dev/null || true
    # Remove old json-sort filter (had both clean+smudge).
    # Safe to remove once all machines have run dot update (2026-04+).
    $git_cmd config --unset filter.json-sort.clean 2>/dev/null || true
    $git_cmd config --unset filter.json-sort.smudge 2>/dev/null || true
    $git_cmd config filter.json-normalize.clean "jq --sort-keys ." 2>/dev/null || true
  }
  # shellcheck disable=SC2086  # $GIT is intentionally word-split.
  [[ -d "$DOTFILES" ]] && _apply_repo_config $GIT
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path url
    IFS='|' read -r _ path url <<< "$entry"
    if [[ -d "$path/.git" ]]; then
      _apply_repo_config git -C "$path"
      # Sync remote URL from overlay conf
      local current_url
      current_url=$(git -C "$path" remote get-url origin 2>/dev/null) || true
      if [[ -n "$url" && "$current_url" != "$url" ]]; then
        git -C "$path" remote set-url origin "$url" 2>/dev/null || true
      fi
    fi
  done
  unset -f _apply_repo_config
}

# ---------------------------------------------------------------------------
# Base repo
# ---------------------------------------------------------------------------

# shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
_pull_base() {
  _pull_repo "$HOME" $GIT pull "$@"
}

# Restore git-tracked versions of skip-worktree files so pull won't
# conflict with overlay symlinks. _link_overlays re-symlinks and
# re-sets skip-worktree after pull.
_unstash_overlay_overrides() {
  [[ -d "$DOTFILES" ]] || return 0
  local files
  files=$($GIT ls-files -v 2>/dev/null | awk '/^S /{print $2}') || true
  [[ -n "$files" ]] || return 0
  echo "$files" | while IFS= read -r f; do
    $GIT update-index --no-skip-worktree "$f" 2>/dev/null || true
    $GIT checkout -- "$f" 2>/dev/null || true
  done
}

# ---------------------------------------------------------------------------
# Overlay repos
# ---------------------------------------------------------------------------

# Check if the deploy key for an overlay is available.
# Returns 0 if no .ssh file exists (public repo) or if the key file exists.
# Returns 1 if a .ssh file declares an IdentityFile that's missing.
_overlay_key_available() {
  local name="$1"
  local conf_dir="$HOME/.config/dot/overlays.d"
  # Find the companion .ssh file (any numeric prefix)
  local f
  for f in "$conf_dir"/*-"$name".ssh "$conf_dir"/"$name".ssh; do
    [[ -f "$f" ]] || continue
    local key_path
    key_path=$(awk '/^[[:space:]]+IdentityFile / {print $2; exit}' "$f")
    [[ -n "$key_path" ]] || return 0
    key_path="${key_path/#\~/$HOME}"
    [[ -f "$key_path" ]] && return 0
    return 1
  done
  return 0
}

# Pull a single overlay repo, cloning it first if missing.
# $1 = name, $2 = path, $3 = url (from OVERLAYS entry)
# Remaining args are forwarded to git pull.
_pull_overlay() {
  local name="$1" path="$2" url="$3"
  shift 3
  if [[ ! -d "$path/.git" ]]; then
    if [[ -z "$url" ]]; then
      return 0
    fi
    # Skip clone if the deploy key is missing — avoids noisy failures
    # on machines that don't have access yet.
    if ! _overlay_key_available "$name"; then
      _log_dim "  skipping $name overlay (deploy key not found)"
      return 0
    fi
    if [[ -d "$path" ]]; then
      _warn "  warning: $name overlay dir exists but isn't a git repo — re-cloning"
      rm -rf "$path"
    fi
    _log_header "==> Cloning $name dotfiles..."
    git clone "$url" "$path" || { _warn "  warning: $name dotfiles clone failed"; return 0; }
    return 0
  fi
  _log_header "==> Pulling $name dotfiles..."
  _pull_repo "$path" git -C "$path" pull "$@" ||
    _warn "  warning: $name dotfiles pull failed"
  return 0
}

# Pull all active overlays.
_pull_overlays() {
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local name path url
    IFS='|' read -r name path url <<< "$entry"
    _pull_overlay "$name" "$path" "$url" "$@"
  done
}

# Push a single overlay repo.
_push_overlay() {
  local name="$1" path="$2"
  shift 2
  [[ -d "$path/.git" ]] || return 0
  _log_header "==> Pushing $name dotfiles..."
  git -C "$path" push "$@" || _warn "  warning: $name dotfiles push failed"
}

# Push all active overlays.
_push_overlays() {
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local name path
    IFS='|' read -r name path _ <<< "$entry"
    _push_overlay "$name" "$path" "$@"
  done
}

# ---------------------------------------------------------------------------
# Overlay linking
# ---------------------------------------------------------------------------

# Link a single overlay's home/ directory into $HOME.
# Creates relative symlinks. Sets skip-worktree on base-repo files
# that overlay symlinks shadow.
# Appends linked paths to $_overlay_manifest_new (set by _link_overlays).
_link_overlay() {
  local name="$1" path="$2"
  local overlay_home="$path/home"
  [[ -d "$overlay_home" ]] || return 0
  _log_header "==> Linking $name dotfiles..."
  while IFS= read -r src; do
    local rel="${src#"$overlay_home"/}"
    local dst="$HOME/$rel"
    mkdir -p "$(dirname "$dst")"
    local depth
    depth=$(echo "$rel" | tr -cd '/' | wc -c)
    local prefix=""
    for ((i = 0; i < depth; i++)); do prefix="../$prefix"; done
    local target="${prefix}.dotfiles-$name/home/$rel"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$target" ]]; then
      # Correct symlink already exists — just ensure skip-worktree
      if [[ -d "$DOTFILES" ]] && $GIT ls-files --error-unmatch "$rel" &>/dev/null; then
        $GIT update-index --skip-worktree "$rel" 2>/dev/null || true
      fi
      # Record in manifest
      printf '%s\t%s\n' "$rel" "$name" >>"${_overlay_manifest_new:-/dev/null}"
      continue
    fi
    ln -sf "$target" "$dst"
    if [[ -d "$DOTFILES" ]] && $GIT ls-files --error-unmatch "$rel" &>/dev/null; then
      $GIT update-index --skip-worktree "$rel" 2>/dev/null || true
      _log_dim "  linked (override): $rel"
    else
      _log_dim "  linked: $rel"
    fi
    printf '%s\t%s\n' "$rel" "$name" >>"${_overlay_manifest_new:-/dev/null}"
  done < <(find "$overlay_home" -type f ! -name '*.~[0-9]*~')
}

# Link all active overlays and clean up stale symlinks from removed overlays.
_link_overlays() {
  local manifest_dir="$HOME/.local/state/dot"
  local manifest="$manifest_dir/overlay-links"
  mkdir -p "$manifest_dir"

  # Build new manifest in a temp file
  local _overlay_manifest_new=""
  if ! _overlay_manifest_new=$(mktemp 2>/dev/null); then
    _warn "  warning: could not create manifest temp file — skipping stale cleanup"
    _overlay_manifest_new=""
  fi

  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local name path
    IFS='|' read -r name path _ <<< "$entry"
    _link_overlay "$name" "$path"
  done

  # Clean up stale symlinks: paths in old manifest but not in new
  if [[ -f "$manifest" && -n "$_overlay_manifest_new" ]]; then
    local stale
    stale=$(comm -23 \
      <(cut -f1 "$manifest" | grep -v '^$' | sort) \
      <(cut -f1 "$_overlay_manifest_new" | grep -v '^$' | sort)) || true
    if [[ -n "$stale" ]]; then
      _log_header "==> Cleaning stale overlay symlinks..."
      while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        local dst="$HOME/$rel"
        if [[ -L "$dst" ]]; then
          rm -f "$dst"
          _log_dim "  removed: $rel"
        fi
        # Restore base repo version if tracked
        if [[ -d "$DOTFILES" ]] && $GIT ls-files --error-unmatch "$rel" &>/dev/null; then
          $GIT update-index --no-skip-worktree "$rel" 2>/dev/null || true
          $GIT checkout -- "$rel" 2>/dev/null || true
        fi
      done <<< "$stale"
    fi
  fi

  # Atomically replace manifest
  if [[ -n "$_overlay_manifest_new" ]]; then
    mv "$_overlay_manifest_new" "$manifest"
  fi
}

# ---------------------------------------------------------------------------
# Worktree dirty check
# ---------------------------------------------------------------------------

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
    IFS='|' read -r _ path _ <<< "$entry"
    if [[ -d "$path/.git" ]]; then
      if ! git -C "$path" diff-index --quiet HEAD 2>/dev/null; then
        return 0
      fi
    fi
  done
  return 1
}

# Attempt to resolve dirty worktrees caused by dotsync writing files that
# match what's on the remote. Returns 0 if all repos are clean after resolution.
_try_resolve_dirty() {
  local dirty=0
  if [[ -d "$DOTFILES" ]] && ! $GIT diff-index --quiet HEAD 2>/dev/null; then
    $GIT fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote; then
      $GIT checkout -- . 2>/dev/null || true
    else
      dirty=1
    fi
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path
    IFS='|' read -r _ path _ <<< "$entry"
    if [[ -d "$path/.git" ]] && ! git -C "$path" diff-index --quiet HEAD 2>/dev/null; then
      git -C "$path" fetch --quiet origin 2>/dev/null || true
      if _dirty_files_match_ref "$path" git -C "$path"; then
        git -C "$path" checkout -- . 2>/dev/null || true
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

# Re-checkout files that are stat-dirty but content-clean (mtime-only).
_normalize_filtered() {
  local dirty
  if [[ -d "$DOTFILES" ]]; then
    dirty=$($GIT diff-files --name-only 2>/dev/null) || true
    if [[ -n "$dirty" ]]; then
      echo "$dirty" | while IFS= read -r f; do
        if $GIT diff --quiet -- "$f" 2>/dev/null; then
          $GIT checkout -- "$f" 2>/dev/null || true
        fi
      done
    fi
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path
    IFS='|' read -r _ path _ <<< "$entry"
    if [[ -d "$path/.git" ]]; then
      dirty=$(git -C "$path" diff-files --name-only 2>/dev/null) || true
      if [[ -n "$dirty" ]]; then
        echo "$dirty" | while IFS= read -r f; do
          if git -C "$path" diff --quiet -- "$f" 2>/dev/null; then
            git -C "$path" checkout -- "$f" 2>/dev/null || true
          fi
        done
      fi
    fi
  done
}
