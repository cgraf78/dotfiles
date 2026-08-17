# shellcheck shell=bash
# `dot update` orchestration.
#
# This module owns the update lifecycle end-to-end after init has loaded the
# core helpers. The launcher still performs the tiny pre-scan for flags that
# affect shdeps bootstrap before this file is sourced; everything else about
# update/pull behavior should live here so cron, reexec, repo sync, and final
# convergence stay in one readable state machine.

_dot_update_no_base_pull() {
  _ensure_repo_config
  _ui_stage_start "Repos" "checking repositories"
  _pull_overlays
  local status=ok
  [[ "${DOT_PULL_OVERLAY_FAILED:-0}" -eq 0 ]] || status=failed
  if [[ -n "${REPLY:-}" ]]; then
    _ui_stage_finish "$status" "no base repo, $REPLY"
  else
    _ui_stage_finish "$status" "no base repo"
  fi
  [[ "${DOT_PULL_OVERLAY_FAILED:-0}" -eq 0 ]]
}

_dot_update_head() {
  [[ -d "$DOTFILES" ]] || return 0
  $GIT rev-parse HEAD 2>/dev/null || true
}

_dot_update_infra_changed() {
  local head_before="$1" head_after="$2"
  [[ -n "$head_before" && -n "$head_after" ]] || return 1
  [[ "$head_before" != "$head_after" ]] || return 1

  # Only re-exec for files that can affect the running dot process. Other
  # pulled changes can finish in the current process and will be picked up by
  # merge hooks, shdeps, or the user's next shell.
  # The `.local/bin/dot` alternative is the worktree-relative form of DOT_BIN;
  # kept literal here because it is one arm of an anchored, dot-escaped regex.
  $GIT diff --name-only "$head_before" "$head_after" 2>/dev/null |
    grep -qE '^(\.local/lib/dot/|\.local/bin/dot$)'
}

_dot_update_infra_has_conflicts() {
  # Autostash conflicts can leave conflict markers in sourced files. Re-execing
  # into those files would turn a recoverable pull conflict into a broken shell.
  grep -rqE '^<{7} |^={7}$|^>{7} ' \
    "$HOME/.local/lib/dot/" \
    "$DOT_BIN" \
    2>/dev/null
}

_dot_update_cpu_count() {
  local _n=""
  _n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)
  if [[ -z "$_n" && "$(uname -s)" = "Darwin" ]]; then
    _n=$(sysctl -n hw.ncpu 2>/dev/null || true)
  fi
  case "$_n" in
    '' | *[!0-9]*) _n=4 ;;
  esac
  [[ "$_n" -lt 1 ]] && _n=1
  printf '%s\n' "$_n"
}

_dot_update_jobs() {
  local _jobs="${DOT_UPDATE_JOBS:-}"
  case "$_jobs" in
    '' | *[!0-9]*) _jobs="$(_dot_update_cpu_count)" ;;
  esac
  [[ "$_jobs" -lt 1 ]] && _jobs=1
  printf '%s\n' "$_jobs"
}

_dot_update_prepare_shdeps_jobs() {
  [[ -n "${SHDEPS_JOBS+x}" ]] && return 0
  SHDEPS_JOBS="$(_dot_update_jobs)"
  export SHDEPS_JOBS
}

_dot_update_reexec() {
  local cron_mode="$1" front_door="$0" candidate="${DOT_CLIENT_FRONT_DOOR:-}"
  shift

  # Once the adapter has delegated to the retained launcher, $0 names that
  # implementation detail. Re-enter the exact public front door so later
  # infrastructure updates cannot bypass phase/readiness policy. Ignore an
  # ambient override unless it is the installed regular launcher generation.
  if [[ -n $candidate && -f $candidate && ! -L $candidate && -x $candidate &&
    -f $DOT_BIN && ! -L $DOT_BIN && $candidate -ef $DOT_BIN ]]; then
    front_door=$candidate
  fi

  [[ "${DOT_VERBOSE:-0}" -eq 1 ]] &&
    _ui_status changed "dot infrastructure updated, re-running"

  local -a reexec_flags=(--skip-pull)
  [[ "$cron_mode" -eq 1 ]] && reexec_flags+=(--cron)
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && reexec_flags+=(--force)
  [[ "${DOT_VERBOSE:-0}" -eq 1 ]] && reexec_flags+=(--verbose)

  export DOT_REEXEC=1
  exec "$front_door" update "${reexec_flags[@]}" "$@"
}

_dot_update_publish_client_readiness() {
  local helper="$HOME/.local/lib/dotfiles/dot-client-readiness.sh"

  if [[ ! -e $helper && ! -L $helper ]]; then
    return 0
  fi
  [[ -f $helper && ! -L $helper && -x $helper ]] || return 1
  "$helper" write
}

_dot_update_reexec_if_needed() {
  local cron_mode="$1" head_before="$2"
  shift 2

  [[ -d "$DOTFILES" && -n "$head_before" && -z "${DOT_REEXEC:-}" ]] || return 0

  local head_after
  head_after="$(_dot_update_head)"
  _dot_update_infra_changed "$head_before" "$head_after" || return 0

  if _dot_update_infra_has_conflicts; then
    _warn "  warning: conflict markers in dot infrastructure — skipping re-exec"
    return 0
  fi

  _dot_update_reexec "$cron_mode" "$@"
}

_dot_update_sync_repos() {
  local skip_pull="$1" cron_mode="$2"
  shift 2

  if [[ "$skip_pull" -ne 0 ]]; then
    if [[ -n "${DOT_REEXEC:-}" ]]; then
      local seed_rc=0
      _seed_republished_base_anchor || seed_rc=$?
      if [[ "$seed_rc" -eq 2 ]]; then
        _warn "  warning: $REPLY"
        return 1
      fi
      [[ "$seed_rc" -eq 0 ]] || _warn "  warning: $REPLY"
      # The pre-reexec process already rendered Repos. Keep later dashboard
      # numbering stable without exposing this internal skip as a second row.
      # shellcheck disable=SC2034  # read by later _ui_stage_start calls.
      DOT_UI_INDEX=1
    fi
    return 0
  fi

  local head_before=""
  head_before="$(_dot_update_head)"

  local sync_status=0
  if [[ -d "$DOTFILES" ]]; then
    if _repo_pull_all "$@"; then
      :
    else
      sync_status=$?
    fi
  else
    if _dot_update_no_base_pull; then
      :
    else
      sync_status=$?
    fi
  fi

  if [[ "$sync_status" -ne 0 ]]; then
    # Pull validation can reject an overlay after its previous links were
    # unstashed. Reconcile the manifest before returning so untracked links do
    # not remain attached to a checkout that no longer owns the configured URL.
    if ! _link_overlays; then
      _warn "  warning: overlay link cleanup failed after repository sync failure"
    fi
    return "$sync_status"
  fi

  _dot_update_reexec_if_needed "$cron_mode" "$head_before" "$@"
}

_dot_update_finalize() {
  local update_status="${1:-0}" shdeps_ready=0
  # Capability proof belongs to this convergence only. Clear any inherited or
  # stale shell value before bootstrap so a failed `_ensure_shdeps` cannot
  # authorize the destructive half of a later migration through merge hooks.
  unset DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
  if [[ "${DOT_UI_TOTAL:-0}" -le 0 ]]; then
    _ui_begin 4
  fi
  _ensure_repo_config
  _link_overlays || update_status=1
  if _ensure_shdeps && _dot_shdeps_require_release_launcher_preservation; then
    shdeps_ready=1
  else
    update_status=1
  fi
  _ui_stage_start "Tools" "checking configured dependencies"
  if [[ "$shdeps_ready" -eq 1 ]] && declare -f shdeps_update &>/dev/null; then
    if _run_shdeps_update_ui; then
      _ui_stage_finish "${DOT_UI_SHDEPS_STATUS:-ok}" "${DOT_UI_SHDEPS_SUMMARY:-dependencies checked}"
      _shdeps_print_group_summaries
    else
      update_status=1
      _ui_stage_finish failed "${DOT_UI_SHDEPS_SUMMARY:-dependency update failed}"
      _shdeps_print_group_summaries
    fi
  else
    update_status=1
    _ui_stage_finish failed "shdeps unavailable; dependency install skipped"
  fi
  _run_merges || update_status=1
  if [[ -d "$DOTFILES" ]]; then
    _ui_stage_start "Cleanup" "normalizing worktree"
    _normalize_filtered
    _ui_stage_finish ok "worktree normalized"
  elif [[ "${DOT_UI_TOTAL:-0}" -gt 0 ]]; then
    _ui_stage_start "Cleanup" "normalizing worktree"
    _ui_stage_finish ok "no base repo"
  fi
  if [[ "$update_status" -eq 0 ]] && ! _dot_update_publish_client_readiness; then
    update_status=1
    if [[ "${DOT_QUIET:-0}" -ne 1 ]]; then
      _warn "  warning: standalone Dot preparation could not be recorded"
    fi
  fi
  _ui_done "$update_status"
  return "$update_status"
}

_dot_update() {
  local cron_mode=0 skip_pull=0 update_status=0

  while [[ "${1:-}" == -* ]]; do
    case "$1" in
      --cron)
        cron_mode=1
        export DOT_QUIET=1
        export SHDEPS_QUIET=1
        shift
        ;;
      --quiet)
        export DOT_QUIET=1
        export SHDEPS_QUIET=1
        shift
        ;;
      -f | --force)
        export DOT_FORCE=1
        export SHDEPS_FORCE=1
        shift
        ;;
      --skip-pull)
        skip_pull=1
        shift
        ;;
      -v | --verbose)
        export DOT_VERBOSE=1
        export SHDEPS_LOG_LEVEL=2
        shift
        ;;
      *) break ;;
    esac
  done

  # The launcher performs this before entering update. Keep a defensive gate
  # here for sourced callers so SSH, repository, and HOME mutations cannot
  # precede validation of an active filesystem overlay.
  _preflight_local_overlays || return 1

  _ui_begin 5

  # Cron updates must never fight with active local edits. First discard
  # mtime-only or content-identical dirty files written by sync tooling; if
  # anything real remains dirty, exit silently just like the historical path.
  if [[ "$cron_mode" -eq 1 ]] && _is_worktree_dirty; then
    if ! _try_resolve_dirty; then
      exit 0
    fi
  fi

  # Overlay clone URLs can depend on host aliases supplied by overlay .ssh
  # snippets, so merge those snippets before any pull that may clone overlays.
  _merge_overlay_ssh_configs

  _dot_update_sync_repos "$skip_pull" "$cron_mode" "$@" || update_status=1
  _dot_update_finalize "$update_status" || update_status=1
  return "$update_status"
}
