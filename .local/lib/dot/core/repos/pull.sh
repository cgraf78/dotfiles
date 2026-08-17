# shellcheck shell=bash
# Pull orchestration for the base repo and pull-eligible overlays.
#
# Pull is update's most sensitive repo operation: it may repair untracked-file
# adoption conflicts, clone missing overlays, and render live progress. Keep
# those rules together so update/cron behavior can be reviewed in one place.

_backup_dir() {
  local root="$HOME/.dotfiles-backup"
  mkdir -p "$root"
  local backup
  backup="$root/$(date +%Y%m%d%H%M%S)"
  if ! mkdir "$backup" 2>/dev/null; then
    backup=$(mktemp -d "$backup.XXXXXX" 2>/dev/null) || {
      REPLY=""
      return 1
    }
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
#
# Force C locale: the conflict-backup detector (_pull_conflicts_from_log) and the
# quiet-output filter both match literal English git messages ("untracked working
# tree files would be overwritten by", "Already up to date.", "Current branch ...
# is up to date."). git localizes these under a non-English LC_*, which would
# silently defeat the self-healing untracked-conflict backup/retry. LC_ALL is set
# (not LC_MESSAGES) so it wins even when the environment already exports LC_ALL.
_pull_cmd() {
  if [[ "$DOT_QUIET" -eq 1 ]]; then
    LC_ALL=C "$@" --quiet
  else
    LC_ALL=C "$@"
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
  _run_to_log_with_ticks "$log" _pull_cmd "$@" || rc=$?

  if [[ "$rc" -ne 0 ]] && _backup_pull_conflicts "$log" "$backup_root"; then
    : >"$log"
    rc=0
    _run_to_log_with_ticks "$log" _pull_cmd "$@" || rc=$?
  fi

  if [[ "$DOT_QUIET" -ne 1 && -s "$log" && ("${DOT_VERBOSE:-0}" -eq 1 || "$rc" -ne 0) ]]; then
    local visible_log
    visible_log=$(sed \
      -e '/^Already up to date\.$/d' \
      -e '/^Current branch .* is up to date\.$/d' \
      "$log")
    [[ -z "$visible_log" ]] || _log_dim "$visible_log"
  fi

  _dot_cleanup_remove_path "$log" || true
  return "$rc"
}

_repo_head() {
  "$@" rev-parse --verify HEAD 2>/dev/null || true
}

_base_repo_operation_in_progress() {
  local state path
  for state in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    path=$($GIT rev-parse --git-path "$state" 2>/dev/null) || return 0
    [[ ! -e "$path" ]] || return 0
  done
  return 1
}

# shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
_seed_republished_base_anchor() {
  local head upstream_head
  head=$(_repo_head $GIT)
  upstream_head=$($GIT rev-parse --verify '@{u}' 2>/dev/null) || {
    REPLY="cannot resolve the dotfiles upstream while seeding history adoption"
    return 2
  }
  if [[ -z "$head" || "$head" != "$upstream_head" ]]; then
    REPLY="cannot seed history adoption from a locally divergent dotfiles branch"
    return 1
  fi
  if ! $GIT config dot.republishedBaseAnchor "$head"; then
    REPLY="cannot persist the dotfiles history-adoption anchor"
    return 2
  fi
}

# Re-anchor a base checkout when its upstream was intentionally republished
# with a parentless commit containing the exact same tree. Returns 0 after
# adoption, 1 when the histories are related, and 2 when unrelated histories
# fail the cutover safety checks. REPLY describes a status-2 failure.
# shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
_adopt_republished_base() {
  local head upstream upstream_ref remote upstream_branch previous_remote_head remote_head
  local anchor branch_ref tracked_head candidate_ref merge_base_rc=0
  local local_tree root_tree
  local -a roots=()

  head=$(_repo_head $GIT)
  [[ -n "$head" ]] || {
    REPLY="cannot resolve the local dotfiles HEAD during history adoption"
    return 2
  }
  upstream=$($GIT rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
    REPLY="cannot resolve the dotfiles upstream during history adoption"
    return 2
  }
  upstream_ref=$($GIT rev-parse --symbolic-full-name '@{u}' 2>/dev/null) || {
    REPLY="cannot resolve the dotfiles upstream ref during history adoption"
    return 2
  }
  remote=${upstream%%/*}
  [[ -n "$remote" && "$remote" != "$upstream" ]] || {
    REPLY="cannot resolve the dotfiles remote during history adoption"
    return 2
  }
  upstream_branch=${upstream#"$remote/"}
  previous_remote_head=$($GIT rev-parse --verify "$upstream" 2>/dev/null) || {
    REPLY="cannot resolve the previous dotfiles upstream during history adoption"
    return 2
  }
  if [[ "$head" == "$previous_remote_head" ]]; then
    local seed_rc=0
    _seed_republished_base_anchor || seed_rc=$?
    [[ "$seed_rc" -eq 0 ]] || return 2
  fi
  anchor=$($GIT config --get dot.republishedBaseAnchor 2>/dev/null || true)

  # Keep the candidate isolated from both the upstream ref and shared FETCH_HEAD.
  # This preserves retry evidence and gives validation a stable fetched object.
  candidate_ref="refs/dot/republished-candidate/$$-$RANDOM"
  if ! $GIT fetch --quiet "$remote" \
    "refs/heads/$upstream_branch:$candidate_ref"; then
    REPLY="cannot fetch the candidate dotfiles history for validation"
    return 2
  fi
  remote_head=$($GIT rev-parse --verify "$candidate_ref" 2>/dev/null) || {
    REPLY="cannot resolve the candidate dotfiles history after fetching"
    return 2
  }
  if ! $GIT update-ref -d "$candidate_ref" "$remote_head"; then
    REPLY="cannot remove the temporary dotfiles history candidate"
    return 2
  fi

  $GIT merge-base "$head" "$remote_head" >/dev/null 2>&1 || merge_base_rc=$?
  if [[ "$merge_base_rc" -eq 0 ]]; then
    return 1
  fi
  if [[ "$merge_base_rc" -ne 1 ]]; then
    REPLY="cannot compare the local and candidate dotfiles histories"
    return 2
  fi

  branch_ref=$($GIT symbolic-ref -q HEAD 2>/dev/null) || {
    REPLY="refusing unrelated dotfiles history from a detached HEAD"
    return 2
  }
  if [[ "$branch_ref" != "refs/heads/$upstream_branch" ]]; then
    REPLY="refusing unrelated dotfiles history on a branch that differs from its upstream"
    return 2
  fi
  if [[ "$head" != "$previous_remote_head" && "$head" != "$anchor" ]]; then
    REPLY="refusing unrelated dotfiles history on a locally divergent branch"
    return 2
  fi
  if _base_repo_operation_in_progress; then
    REPLY="refusing unrelated dotfiles history while another Git operation is in progress"
    return 2
  fi
  if ! $GIT diff-index --quiet "$head" --; then
    REPLY="refusing unrelated dotfiles history with a dirty worktree"
    return 2
  fi

  mapfile -t roots < <($GIT rev-list --max-parents=0 "$remote_head" 2>/dev/null)
  if [[ "${#roots[@]}" -ne 1 ]]; then
    REPLY="refusing unrelated dotfiles history with ${#roots[@]} root commits"
    return 2
  fi
  local_tree=$($GIT rev-parse "$head^{tree}" 2>/dev/null) || {
    REPLY="cannot resolve the local dotfiles tree for history adoption"
    return 2
  }
  root_tree=$($GIT rev-parse "${roots[0]}^{tree}" 2>/dev/null) || {
    REPLY="cannot resolve the republished dotfiles root tree"
    return 2
  }
  if [[ "$local_tree" != "$root_tree" ]]; then
    REPLY="refusing unrelated dotfiles history whose root tree differs from HEAD"
    return 2
  fi
  tracked_head=$($GIT rev-parse --verify "$upstream_ref" 2>/dev/null) || {
    REPLY="cannot resolve the previous dotfiles upstream during history adoption"
    return 2
  }
  if [[ "$tracked_head" != "$remote_head" ]] &&
    ! $GIT update-ref "$upstream_ref" "$remote_head" "$tracked_head"; then
    REPLY="the dotfiles upstream changed during history adoption"
    return 2
  fi
  if ! $GIT update-ref "$branch_ref" "${roots[0]}" "$head"; then
    REPLY="failed to adopt the republished dotfiles root"
    return 2
  fi
  $GIT config --unset-all dot.republishedBaseAnchor 2>/dev/null || true
  REPLY="$remote_head"
}

# Pull the base repo. Reports the outcome through the REPLY_STATUS enum
# (changed|current|skipped|failed|blocked) rather than a display string, so callers
# branch on a stable key instead of parsing prose.
# shellcheck disable=SC2086  # $GIT is intentionally word-split (multi-word command).
_pull_base() {
  REPLY_STATUS=""
  _prefer_base_dotfiles_ssh_remote
  if ! _repo_has_upstream $GIT; then
    REPLY_STATUS="skipped"
    return 0
  fi
  local adopt_rc=0
  _adopt_republished_base || adopt_rc=$?
  if [[ "$adopt_rc" -eq 2 ]]; then
    _warn "  warning: $REPLY"
    REPLY_STATUS="blocked"
    return 1
  fi
  local validated_tip=""
  [[ "$adopt_rc" -ne 0 ]] || validated_tip="$REPLY"
  local head_before head_after
  head_before=$(_repo_head $GIT)
  local pull_rc=0
  if [[ "$adopt_rc" -eq 0 ]]; then
    _pull_repo "$HOME" $GIT merge --ff-only "$validated_tip" || pull_rc=$?
  else
    _pull_repo "$HOME" $GIT pull "$@" || pull_rc=$?
  fi
  if [[ "$pull_rc" -eq 0 ]]; then
    head_after=$(_repo_head $GIT)
    if [[ "$adopt_rc" -eq 0 ]] ||
      [[ -n "$head_before" && -n "$head_after" && "$head_before" != "$head_after" ]]; then
      REPLY_STATUS="changed"
    else
      REPLY_STATUS="current"
    fi
    return 0
  fi
  if [[ "$adopt_rc" -eq 0 ]]; then
    _warn "  warning: failed to integrate the validated dotfiles history"
    REPLY_STATUS="blocked"
  else
    REPLY_STATUS="failed"
  fi
  return 1
}

# Resolve the deploy key path declared by an overlay's companion `.ssh` file.
# A companion file is optional; only an explicit IdentityFile turns the overlay
# into a key-gated repo. REPLY is the tilde-expanded key path when one exists.
_overlay_key_path() {
  local ssh_file="$1"
  [[ -f "$ssh_file" ]] || return 1
  local key_path
  key_path=$(awk '/^[[:space:]]+IdentityFile / {print $2; exit}' "$ssh_file")
  [[ -n "$key_path" ]] || return 1
  key_path="${key_path/#\~/$HOME}"
  REPLY="$key_path"
  return 0
}

_overlay_key_missing() {
  _overlay_key_path "$1" || return 1
  [[ ! -f "$REPLY" ]]
}

# Explain an origin mismatch and provide the command appropriate to its state.
# Adoption is deliberately explicit: update never rewrites this ownership
# boundary itself.
_overlay_origin_mismatch() {
  local name="$1" path="$2" expected="$3" actual="$4"
  local adopt_command
  case "$actual" in
    "<missing>")
      printf -v adopt_command 'git -C %q remote add origin %q' "$path" "$expected"
      ;;
    "<multiple origin URLs>")
      printf -v adopt_command 'git -C %q config --replace-all remote.origin.url %q' \
        "$path" "$expected"
      ;;
    *)
      printf -v adopt_command 'git -C %q remote set-url origin %q' "$path" "$expected"
      ;;
  esac

  if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
    _ui_status warning "$name overlay origin mismatch: expected $expected, found $actual"
    _ui_status warning "verify the checkout, then adopt it with: $adopt_command"
  else
    _warn "  warning: $name overlay origin does not match its configured URL"
    _warn "    expected: $expected"
    _warn "    found:    $actual"
    _warn "    verify the checkout, then adopt it with: $adopt_command"
  fi
}

_pull_overlay_active() {
  local _name="$1" path="$2" url="$3" optional="$4" ssh_file="$5"
  if _overlay_key_missing "$ssh_file"; then
    [[ "$optional" == "true" ]] && return 1
    return 0
  fi
  if _overlay_is_worktree "$path"; then
    return 0
  fi
  [[ -n "$url" ]]
}

_pull_overlay_count() {
  local entry count=0
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local name path url _conf optional ssh_file sync
    IFS='|' read -r name path url _conf optional ssh_file sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$sync" == "git" ]] || continue
    if _pull_overlay_active "$name" "$path" "$url" "$optional" "$ssh_file"; then
      count=$((count + 1))
    fi
  done
  printf '%s' "$count"
}

_dot_progress_detail() {
  local label="$1" done="$2" total="$3"
  [[ "$total" -gt 0 ]] || return 0
  _ui_progress_detail_with_label "$label" "$done" "$total"
}

_dot_maybe_stage_progress() {
  local label="$1" done="$2" total="$3"
  [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]] || return 0
  [[ "${DOT_VERBOSE:-0}" -eq 0 ]] || return 0
  _ui_stage_update "$(_dot_progress_detail "$label" "$done" "$total")"
}

# Pull a single overlay repo, cloning it first if missing.
# $1 = name, $2 = path, $3 = url, $4 = optional, $5 = ssh file
# Remaining args are forwarded to git pull.
# Pull (or clone) a single overlay. Reports the outcome through REPLY_STATUS
# (changed|cloned|current|skipped|failed, or empty when the overlay is a
# no-op) so the caller tallies on a stable key, not on parsed display text.
_pull_overlay() {
  local name="$1" path="$2" url="$3" optional="$4" ssh_file="$5"
  shift 5
  _overlay_effective_url "$url"
  url="$REPLY"
  REPLY_STATUS=""
  if _overlay_key_missing "$ssh_file"; then
    [[ "$optional" == "true" ]] && return 0
    if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
      _ui_status warning "$name overlay deploy key missing"
    else
      _warn "  warning: $name overlay deploy key missing: $REPLY"
    fi
    REPLY_STATUS="failed"
    return 0
  fi

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    [[ -n "$url" ]] || return 0
    if [[ "$optional" == "true" ]]; then
      if git clone "$url" "$path" >/dev/null 2>&1; then
        REPLY_STATUS="cloned"
      fi
      return 0
    fi
    if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
      [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status running "$name dotfiles: cloning"
    else
      _log_header "==> Cloning $name dotfiles..."
    fi
    if ! git clone "$url" "$path" >/dev/null 2>&1; then
      if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
        _ui_status warning "$name dotfiles clone failed"
      else
        _warn "  warning: $name dotfiles clone failed"
      fi
      REPLY_STATUS="failed"
      return 0
    fi
    [[ "${DOT_UI_TOTAL:-0}" -gt 0 && "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status changed "$name dotfiles cloned"
    REPLY_STATUS="cloned"
    return 0
  fi

  # Do not replace existing paths during unattended updates. A linked worktree
  # has a `.git` file, and any other path may contain user-owned data.
  if ! _overlay_is_worktree "$path"; then
    if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
      _ui_status warning "$name overlay path exists but is not a Git worktree"
    else
      _warn "  warning: $name overlay path exists but is not a Git worktree; leaving it untouched: $path"
    fi
    REPLY_STATUS="failed"
    return 0
  fi

  local actual_origin
  if ! _overlay_origin_matches "$path" "$url"; then
    actual_origin="$REPLY"
    _overlay_origin_mismatch "$name" "$path" "$url" "$actual_origin"
    REPLY_STATUS="failed"
    return 0
  fi

  if ! _repo_has_upstream git -C "$path"; then
    [[ "${DOT_UI_TOTAL:-0}" -gt 0 && "${DOT_VERBOSE:-0}" -eq 1 ]] &&
      _ui_status skipped "$name dotfiles pull skipped (no upstream)"
    REPLY_STATUS="skipped"
    return 0
  fi

  if [[ "$optional" == "true" ]]; then
    local head_before head_after quiet_before quiet_was_set=0
    head_before=$(_repo_head git -C "$path")
    if [[ -n "${DOT_QUIET+x}" ]]; then
      quiet_was_set=1
      quiet_before="$DOT_QUIET"
    fi
    DOT_QUIET=1
    if ! _pull_repo "$path" git -C "$path" pull "$@"; then
      if [[ "$quiet_was_set" -eq 1 ]]; then
        DOT_QUIET="$quiet_before"
      else
        unset DOT_QUIET
      fi
      return 0
    fi
    if [[ "$quiet_was_set" -eq 1 ]]; then
      DOT_QUIET="$quiet_before"
    else
      unset DOT_QUIET
    fi
    head_after=$(_repo_head git -C "$path")
    if [[ -n "$head_before" && -n "$head_after" && "$head_before" != "$head_after" ]]; then
      REPLY_STATUS="changed"
    else
      REPLY_STATUS="current"
    fi
    return 0
  fi

  if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
    [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status running "$name dotfiles: pulling"
  else
    _log_header "==> Pulling $name dotfiles..."
  fi
  local head_before head_after
  head_before=$(_repo_head git -C "$path")
  if ! _pull_repo "$path" git -C "$path" pull "$@"; then
    if [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
      _ui_status warning "$name dotfiles pull failed"
    else
      _warn "  warning: $name dotfiles pull failed"
    fi
    REPLY_STATUS="failed"
    return 0
  fi
  head_after=$(_repo_head git -C "$path")
  if [[ -n "$head_before" && -n "$head_after" && "$head_before" != "$head_after" ]]; then
    [[ "${DOT_UI_TOTAL:-0}" -gt 0 && "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status changed "$name dotfiles updated"
    REPLY_STATUS="changed"
  else
    [[ "${DOT_UI_TOTAL:-0}" -gt 0 && "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status ok "$name dotfiles current"
    REPLY_STATUS="current"
  fi
  return 0
}

# Active Git overlays are separate synchronization units, so their pulls can
# overlap within the bound from _dot_update_jobs. A worker cannot return shell
# state to its parent, so each writes indexed log, status, and exit-code files in
# parent-owned scratch; the parent then replays declaration order for stable UI
# and tallies the structured statuses. If scratch allocation is unavailable, the
# serial path preserves the same pull and status behavior without parallel state.
_pull_overlay_result_prefix() {
  local _dir="$1" _idx="$2"
  printf '%s/%03d' "$_dir" "$_idx"
}

_pull_overlay_capture() {
  local _idx="$1" _result_dir="$2" name="$3" path="$4" url="$5" optional="$6" ssh_file="$7"
  shift 7
  local _prefix _rc=0
  # Capture-worker helpers may allocate their own logs. Contain them in the
  # parent-owned result root so forced worker termination cannot leak storage.
  local TMPDIR="$_result_dir"
  export TMPDIR
  _dot_cleanup_prepare_subshell
  _prefix="$(_pull_overlay_result_prefix "$_result_dir" "$_idx")"
  REPLY_STATUS=""
  _pull_overlay "$name" "$path" "$url" "$optional" "$ssh_file" "$@" >"$_prefix.log" 2>&1 || _rc=$?
  printf '%s' "$_rc" >"$_prefix.rc"
  printf '%s' "${REPLY_STATUS:-}" >"$_prefix.status"
}

_pull_overlay_drain_workers() {
  local _result_dir="$1" _pid _log
  shift
  for _pid in "$@"; do
    wait "$_pid" 2>/dev/null || true
    _dot_cleanup_unregister_pid "$_pid"
  done
  # Preserve diagnostics already captured by siblings when a coordinator
  # worker itself fails before the normal ordered rendering pass.
  for _log in "$_result_dir"/*.log; do
    [[ -f "$_log" ]] || continue
    [[ ! -s "$_log" ]] || cat "$_log"
  done
  _dot_cleanup_remove_path "$_result_dir" || true
}

_pull_overlay_record_status() {
  local name="$1" status="$2"
  [[ -n "$status" ]] || return 0

  # The terse "<name> <status>" summary is display text, rebuilt here at the
  # boundary; the tally below keys off the structured status, not this string.
  _summaries+=("$name $status")
  case "$status" in
    failed)
      DOT_PULL_OVERLAY_FAILED=$((DOT_PULL_OVERLAY_FAILED + 1))
      ;;
    changed)
      DOT_PULL_OVERLAY_CHANGED=$((DOT_PULL_OVERLAY_CHANGED + 1))
      DOT_PULL_OVERLAY_CHANGED_ITEMS+="${name} dotfiles updated"$'\n'
      ;;
    cloned)
      DOT_PULL_OVERLAY_CHANGED=$((DOT_PULL_OVERLAY_CHANGED + 1))
      DOT_PULL_OVERLAY_CHANGED_ITEMS+="${name} dotfiles cloned"$'\n'
      ;;
    skipped)
      DOT_PULL_OVERLAY_SKIPPED=$((DOT_PULL_OVERLAY_SKIPPED + 1))
      ;;
    current)
      DOT_PULL_OVERLAY_CURRENT=$((DOT_PULL_OVERLAY_CURRENT + 1))
      ;;
  esac
}

_pull_overlays_serial() {
  local entry name path url _conf optional ssh_file sync status
  for entry in "${_active_entries[@]+"${_active_entries[@]}"}"; do
    IFS='|' read -r name path url _conf optional ssh_file sync <<<"$entry"
    _done=$((_done + 1))
    _dot_maybe_stage_progress "$name" "$_done" "$_total"
    _pull_overlay "$name" "$path" "$url" "$optional" "$ssh_file" "$@"
    status="${REPLY_STATUS:-}"
    _pull_overlay_record_status "$name" "$status"
  done
}

_pull_overlays() {
  local entry
  local _summaries=()
  local _done="${DOT_REPO_PROGRESS_DONE:-0}"
  local _total="${DOT_REPO_PROGRESS_TOTAL:-0}"
  DOT_PULL_OVERLAY_CURRENT=0
  DOT_PULL_OVERLAY_CHANGED=0
  DOT_PULL_OVERLAY_CHANGED_ITEMS=""
  DOT_PULL_OVERLAY_FAILED=0
  DOT_PULL_OVERLAY_SKIPPED=0
  local name path url _conf optional ssh_file sync status
  local -a _active_entries=()
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path url _conf optional ssh_file sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$sync" == "git" ]] || continue
    if ! _pull_overlay_active "$name" "$path" "$url" "$optional" "$ssh_file"; then
      continue
    fi
    _active_entries+=("$entry")
  done
  if ((${#_active_entries[@]} == 0)); then
    DOT_REPO_PROGRESS_DONE="$_done"
    REPLY=""
    return 0
  fi

  local _result_dir=""
  if ! _dot_cleanup_mktemp -d 2>/dev/null; then
    _pull_overlays_serial "$@"
    DOT_REPO_PROGRESS_DONE="$_done"
    REPLY=$(_join_comma "${_summaries[@]}")
    return 0
  fi
  _result_dir=$REPLY

  local _jobs _running=0 _idx=0 _pid
  local -a _pids=()
  _jobs="$(_dot_update_jobs)"

  for entry in "${_active_entries[@]+"${_active_entries[@]}"}"; do
    IFS='|' read -r name path url _conf optional ssh_file sync <<<"$entry"
    _done=$((_done + 1))
    _dot_maybe_stage_progress "$name" "$_done" "$_total"
    _idx=$((_idx + 1))
    _dot_cleanup_begin_job_launch
    _pull_overlay_capture "$_idx" "$_result_dir" "$name" "$path" "$url" "$optional" "$ssh_file" "$@" \
      <&"$DOT_CLEANUP_LAUNCH_STDIN_FD" &
    _pid=$!
    _dot_cleanup_finish_job_launch "$_pid"
    _pids+=("$_pid")
    _running=$((_running + 1))
    if [[ "$_running" -ge "$_jobs" ]]; then
      _pid="${_pids[0]}"
      _pids=("${_pids[@]:1}")
      if ! wait "$_pid" 2>/dev/null; then
        _dot_cleanup_unregister_pid "$_pid"
        _pull_overlay_drain_workers "$_result_dir" "${_pids[@]}"
        return 1
      fi
      _dot_cleanup_unregister_pid "$_pid"
      _running=$((_running - 1))
    fi
  done

  while ((${#_pids[@]} > 0)); do
    _pid="${_pids[0]}"
    _pids=("${_pids[@]:1}")
    if ! wait "$_pid" 2>/dev/null; then
      _dot_cleanup_unregister_pid "$_pid"
      _pull_overlay_drain_workers "$_result_dir" "${_pids[@]}"
      return 1
    fi
    _dot_cleanup_unregister_pid "$_pid"
  done

  _idx=0
  for entry in "${_active_entries[@]+"${_active_entries[@]}"}"; do
    IFS='|' read -r name path url _conf optional ssh_file sync <<<"$entry"
    _idx=$((_idx + 1))
    local _prefix _rc
    _prefix="$(_pull_overlay_result_prefix "$_result_dir" "$_idx")"
    [[ ! -s "$_prefix.log" ]] || cat "$_prefix.log"
    status="$(cat "$_prefix.status" 2>/dev/null || true)"
    _rc="$(cat "$_prefix.rc" 2>/dev/null || printf '1')"
    if [[ -z "$status" && "$_rc" -ne 0 ]]; then
      status=failed
    fi
    # An empty status means the overlay was a no-op (inactive/missing key);
    # leave it out of the tally and the summary entirely.
    _pull_overlay_record_status "$name" "$status"
  done
  _dot_cleanup_remove_path "$_result_dir" || true
  DOT_REPO_PROGRESS_DONE="$_done"
  REPLY=$(_join_comma "${_summaries[@]}")
}

# Pull all repos that update treats as part of the synchronized repo set: base
# first, then pull-eligible overlays. This owns only repository synchronization;
# `_dot_update_finalize` still handles dependency updates, overlay linking, merge
# hooks, and cron installation after the repo set is current.
_repo_pull_all() {
  _ensure_repo_config
  _normalize_filtered
  if ! _unstash_overlay_overrides; then
    return 1
  fi

  local _repo_total
  _repo_total=$((1 + $(_pull_overlay_count)))
  local _repo_detail="pulling repositories"
  if [[ "${DOT_VERBOSE:-0}" -eq 0 ]]; then
    _repo_detail="$(_dot_progress_detail "dotfiles" 1 "$_repo_total")"
  fi
  _ui_stage_start "Repos" "$_repo_detail"

  local _repo_status=ok
  local _repo_current=0
  local _repo_changed=0
  local _repo_failed=0
  local _repo_skipped=0
  local -a _repo_changed_items=()

  [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status running "dotfiles: pulling"
  REPLY_STATUS=""
  if ! _pull_base "$@"; then
    if [[ "$DOT_QUIET" -eq 1 && "${REPLY_STATUS:-}" != "blocked" ]]; then
      _warn "  warning: dotfiles pull failed"
    else
      [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status failed "dotfiles: pull failed"
      _repo_status=failed
      _repo_failed=$((_repo_failed + 1))
    fi
  else
    if [[ "${REPLY_STATUS:-}" == "skipped" ]]; then
      [[ "${DOT_VERBOSE:-0}" -eq 1 ]] &&
        _ui_status skipped "dotfiles pull skipped (no upstream)"
      _repo_skipped=$((_repo_skipped + 1))
    elif [[ "${REPLY_STATUS:-}" == "changed" ]]; then
      [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status changed "dotfiles updated"
      _repo_changed=$((_repo_changed + 1))
      _repo_changed_items+=("dotfiles updated")
    else
      [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && _ui_status ok "dotfiles current"
      _repo_current=$((_repo_current + 1))
    fi
  fi

  # _pull_overlays owns per-overlay result classification. Seed its progress
  # counters with the already-rendered base repo so non-verbose live progress
  # stays on the same dashboard row.
  # shellcheck disable=SC2034  # read by _pull_overlays while this stage is active.
  DOT_REPO_PROGRESS_DONE=1
  # shellcheck disable=SC2034  # read by _pull_overlays while this stage is active.
  DOT_REPO_PROGRESS_TOTAL="$_repo_total"
  local _pull_overlays_rc=0
  _pull_overlays "$@" || _pull_overlays_rc=$?
  _repo_current=$((_repo_current + ${DOT_PULL_OVERLAY_CURRENT:-0}))
  _repo_changed=$((_repo_changed + ${DOT_PULL_OVERLAY_CHANGED:-0}))
  _repo_failed=$((_repo_failed + ${DOT_PULL_OVERLAY_FAILED:-0}))
  _repo_skipped=$((_repo_skipped + ${DOT_PULL_OVERLAY_SKIPPED:-0}))
  if [[ "$_pull_overlays_rc" -ne 0 ]]; then
    _repo_failed=$((_repo_failed + 1))
  fi
  [[ "$_repo_failed" -eq 0 ]] || _repo_status=failed
  if [[ "$_repo_failed" -eq 0 && "$_repo_changed" -gt 0 ]]; then
    _repo_status=changed
  fi
  if [[ -n "${DOT_PULL_OVERLAY_CHANGED_ITEMS:-}" ]]; then
    local _changed_item
    while IFS= read -r _changed_item; do
      [[ -n "$_changed_item" ]] || continue
      _repo_changed_items+=("$_changed_item")
    done <<<"$DOT_PULL_OVERLAY_CHANGED_ITEMS"
  fi
  unset DOT_REPO_PROGRESS_DONE DOT_REPO_PROGRESS_TOTAL

  local _summary
  local _repo_parts=()
  [[ "$_repo_changed" -gt 0 ]] &&
    _repo_parts+=("$(_ui_count_phrase "$_repo_changed" repo repos) changed")
  [[ "$_repo_current" -gt 0 || ("$_repo_failed" -eq 0 && "$_repo_skipped" -eq 0) ]] &&
    _repo_parts+=("$(_ui_count_phrase "$_repo_current" repo repos) current")
  [[ "$_repo_failed" -gt 0 ]] &&
    _repo_parts+=("$(_ui_count_phrase "$_repo_failed" repo repos) failed")
  [[ "$_repo_skipped" -gt 0 ]] &&
    _repo_parts+=("$(_ui_count_phrase "$_repo_skipped" repo repos) skipped")
  _summary=$(_join_comma "${_repo_parts[@]}")
  _ui_stage_finish "$_repo_status" "$_summary"
  if [[ "${DOT_VERBOSE:-0}" -eq 0 ]]; then
    local _repo_item
    for _repo_item in "${_repo_changed_items[@]+"${_repo_changed_items[@]}"}"; do
      _ui_stage_note changed "$_repo_item"
    done
  fi
  [[ "$_repo_status" != "failed" ]]
}
