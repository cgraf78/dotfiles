# shellcheck shell=bash
# Process-owned child, descriptor, and temporary-path cleanup.

_dot_cleanup_reset() {
  DOT_CLEANUP_PIDS=()
  DOT_CLEANUP_PID_IDENTITIES=()
  DOT_CLEANUP_PATHS=()
  DOT_CLEANUP_FDS=()
  DOT_CLEANUP_REGISTRATION_DEPTH=0
  DOT_CLEANUP_PENDING_STATUS=0
  DOT_CLEANUP_RUNNING=0
}

_dot_cleanup_reset

_dot_cleanup_ignore_signals() {
  # A trap protects this shell, but external commands spawned by cleanup reset
  # trapped dispositions to their defaults. Ignore the handled signals while
  # cleanup runs so a later terminal-group signal cannot kill `ps`, `pgrep`,
  # `rm`, or lock-release helpers midway through an otherwise exact cleanup.
  trap '' HUP
  trap '' INT
  trap '' QUIT
  trap '' TERM
}

_dot_cleanup_begin_registration() {
  DOT_CLEANUP_REGISTRATION_DEPTH=$((DOT_CLEANUP_REGISTRATION_DEPTH + 1))
}

_dot_cleanup_end_registration() {
  local pending=0
  if [[ "$DOT_CLEANUP_REGISTRATION_DEPTH" -gt 0 ]]; then
    DOT_CLEANUP_REGISTRATION_DEPTH=$((DOT_CLEANUP_REGISTRATION_DEPTH - 1))
  fi
  if [[ "$DOT_CLEANUP_REGISTRATION_DEPTH" -eq 0 &&
    "$DOT_CLEANUP_PENDING_STATUS" -ne 0 ]]; then
    pending=$DOT_CLEANUP_PENDING_STATUS
    _dot_cleanup_signal "$pending"
  fi
}

_dot_cleanup_signal() {
  local status="$1"
  if [[ "$DOT_CLEANUP_RUNNING" -eq 1 ]]; then
    return 0
  fi
  # Latch before requesting exit. EXIT traps do not begin atomically with the
  # `exit` builtin, so a second signal in that boundary must not replace the
  # first status or interrupt owned-resource cleanup.
  if [[ "$DOT_CLEANUP_PENDING_STATUS" -eq 0 ]]; then
    DOT_CLEANUP_PENDING_STATUS=$status
  fi
  if [[ "$DOT_CLEANUP_REGISTRATION_DEPTH" -gt 0 ]]; then
    return 0
  fi

  # Enter the running state before the first cleanup command. Later signals
  # then return from their traps while this exact cleanup completes. Leave the
  # state set through exit; the EXIT trap becomes an idempotent no-op, followed
  # by any outer owner action such as releasing the dot update lock.
  DOT_CLEANUP_RUNNING=1
  _dot_cleanup_ignore_signals
  _dot_cleanup_owned
  exit "$DOT_CLEANUP_PENDING_STATUS"
}

_dot_cleanup_register_pid() {
  local pid="$1" backend="" identity=""
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 2
  if _dot_cleanup_job_matches "$pid" all; then
    _dot_cleanup_process_backend backend
    if _dot_cleanup_observe_process "$backend" "$pid"; then
      identity=$DOT_CLEANUP_OBS_ID
    fi
  fi
  DOT_CLEANUP_PIDS+=("$pid")
  DOT_CLEANUP_PID_IDENTITIES+=("$identity")
}

_dot_cleanup_register_path() {
  local path="$1"
  [[ -n "$path" ]] || return 2
  DOT_CLEANUP_PATHS+=("$path")
}

_dot_cleanup_register_fd() {
  local fd="$1"
  [[ "$fd" =~ ^[0-9]+$ ]] || return 2
  DOT_CLEANUP_FDS+=("$fd")
}

_dot_cleanup_unregister_pid() {
  local pid="$1" index
  [[ ${DOT_CLEANUP_PIDS[*]+set} == set ]] || return 0
  for index in "${!DOT_CLEANUP_PIDS[@]}"; do
    [[ "${DOT_CLEANUP_PIDS[$index]}" == "$pid" ]] || continue
    unset "DOT_CLEANUP_PIDS[$index]"
    unset "DOT_CLEANUP_PID_IDENTITIES[$index]"
  done
}

_dot_cleanup_unregister_path() {
  local path="$1" index
  [[ ${DOT_CLEANUP_PATHS[*]+set} == set ]] || return 0
  for index in "${!DOT_CLEANUP_PATHS[@]}"; do
    [[ "${DOT_CLEANUP_PATHS[$index]}" == "$path" ]] || continue
    unset "DOT_CLEANUP_PATHS[$index]"
  done
}

_dot_cleanup_unregister_fd() {
  local fd="$1" index
  [[ ${DOT_CLEANUP_FDS[*]+set} == set ]] || return 0
  for index in "${!DOT_CLEANUP_FDS[@]}"; do
    [[ "${DOT_CLEANUP_FDS[$index]}" == "$fd" ]] || continue
    unset "DOT_CLEANUP_FDS[$index]"
  done
}

_dot_cleanup_job_matches() {
  local target="$1" mode="${2:-all}" job
  local jobs_output=""
  case "$mode" in
    active) jobs_output=$(
      jobs -pr
      jobs -ps
    ) ;;
    all) jobs_output=$(jobs -p) ;;
    *) return 2 ;;
  esac
  while IFS= read -r job; do
    [[ "$job" == "$target" ]] && return 0
  done <<<"$jobs_output"
  return 1
}

_dot_cleanup_process_backend() {
  local output_name="$1"
  if [[ -r "/proc/$$/stat" ]]; then
    printf -v "$output_name" '%s' proc
  else
    printf -v "$output_name" '%s' ps
  fi
}

_dot_cleanup_observe_proc() {
  local pid="$1" line rest
  IFS= read -r line 2>/dev/null <"/proc/$pid/stat" || return 1
  [[ "$line" == "$pid ("* ]] || return 1
  # A process name may contain spaces or ')', so field extraction starts after
  # the final closing delimiter. In the remainder, state is field 3, parent is
  # field 4, and the kernel start tick is field 22 (the twentieth token here).
  rest="${line##*) }"
  [[ "$rest" != "$line" ]] || return 1
  # shellcheck disable=SC2086  # Kernel stat fields are intentionally tokenized.
  set -- $rest
  [[ "$#" -ge 20 && "$2" =~ ^[0-9]+$ && "${20}" =~ ^[0-9]+$ ]] || return 1
  DOT_CLEANUP_OBS_PPID=$2
  DOT_CLEANUP_OBS_STATE=$1
  DOT_CLEANUP_OBS_ID="proc:${20}"
}

_dot_cleanup_observe_ps() {
  local pid="$1" row ppid state weekday month day clock year extra
  row=$(LC_ALL=C TZ=UTC0 command ps -o ppid=,stat=,lstart= -p "$pid" 2>/dev/null) || return 1
  read -r ppid state weekday month day clock year extra <<<"$row"
  [[ "$ppid" =~ ^[0-9]+$ && -n "$state" && -n "$year" && -z "$extra" ]] || return 1
  DOT_CLEANUP_OBS_PPID=$ppid
  DOT_CLEANUP_OBS_STATE=$state
  DOT_CLEANUP_OBS_ID="ps:$weekday $month $day $clock $year"
}

_dot_cleanup_observe_process() {
  local backend="$1" pid="$2"
  case "$backend" in
    proc) _dot_cleanup_observe_proc "$pid" ;;
    ps) _dot_cleanup_observe_ps "$pid" ;;
    *) return 2 ;;
  esac
}

_dot_cleanup_process_matches_live() {
  local backend="$1" pid="$2" identity="$3"
  [[ -n "$identity" ]] || return 1
  _dot_cleanup_observe_process "$backend" "$pid" || return 1
  [[ "$DOT_CLEANUP_OBS_ID" == "$identity" ]] || return 1
  [[ ! "$DOT_CLEANUP_OBS_STATE" =~ ^Z ]]
}

_dot_cleanup_descendant_records() {
  local backend="$1" root="$2" root_identity="$3"
  local index=0 parent parent_identity depth
  local children child child_identity child_depth observed_parent
  local -a queue_pids=("$root") queue_identities=("$root_identity") queue_depths=(0)
  local -A seen=(["$root"]=1)

  [[ "$root" =~ ^[1-9][0-9]*$ && -n "$root_identity" ]] || return 0
  command -v pgrep >/dev/null 2>&1 || return 0
  _dot_cleanup_observe_process "$backend" "$root" || return 0
  [[ "$DOT_CLEANUP_OBS_ID" == "$root_identity" ]] || return 0

  while ((index < ${#queue_pids[@]} && index < 512)); do
    parent=${queue_pids[$index]}
    parent_identity=${queue_identities[$index]}
    depth=${queue_depths[$index]}
    index=$((index + 1))
    ((depth < 64)) || continue

    children=$(command pgrep -P "$parent" 2>/dev/null || true)
    # shellcheck disable=SC2086  # pgrep emits a whitespace-delimited PID list.
    for child in $children; do
      [[ "$child" =~ ^[1-9][0-9]*$ && "$child" != "$$" &&
        -z "${seen[$child]:-}" ]] || continue
      _dot_cleanup_observe_process "$backend" "$child" || continue
      [[ "$DOT_CLEANUP_OBS_PPID" == "$parent" ]] || continue
      child_identity=$DOT_CLEANUP_OBS_ID

      # Re-read the parent after observing the child. If its PID changed or the
      # edge was reparented during discovery, discard this subtree.
      _dot_cleanup_observe_process "$backend" "$parent" || continue
      observed_parent=$DOT_CLEANUP_OBS_ID
      [[ "$observed_parent" == "$parent_identity" ]] || continue

      child_depth=$((depth + 1))
      seen["$child"]=1
      printf '%s\t%s\t%s\n' "$child" "$child_identity" "$child_depth"
      queue_pids+=("$child")
      queue_identities+=("$child_identity")
      queue_depths+=("$child_depth")
    done
  done
}

_dot_cleanup_remove_path() {
  local path="$1" rc=0
  if [[ "$DOT_CLEANUP_RUNNING" -eq 1 ]]; then
    if rm -rf -- "$path"; then
      _dot_cleanup_unregister_path "$path"
      return 0
    fi
    return 1
  fi

  # Stop owning the name before deletion. Signals stay deferred across this
  # short region, so a path recreated after rm cannot be deleted by EXIT
  # cleanup as though it were still the original temporary object.
  _dot_cleanup_begin_registration
  _dot_cleanup_unregister_path "$path"
  if ! rm -rf -- "$path"; then
    _dot_cleanup_register_path "$path"
    rc=1
  fi
  _dot_cleanup_end_registration
  if [[ "$rc" -eq 0 ]]; then
    return 0
  fi
  return 1
}

_dot_cleanup_close_fd() {
  local fd="$1"
  if [[ "$fd" =~ ^[0-9]+$ ]]; then
    exec {fd}>&- 2>/dev/null || true
  fi
  _dot_cleanup_unregister_fd "$fd"
}

_dot_cleanup_wait_job() {
  local pid="$1"
  # Bash can interrupt wait to run another signal trap. Keep consuming the
  # exact active job until it stops running, then consume any stored status
  # once. `jobs -p` may retain a completed record, so it is not a loop bound.
  while _dot_cleanup_job_matches "$pid" active; do
    wait "$pid" 2>/dev/null || true
  done
  wait "$pid" 2>/dev/null || true
}

_dot_cleanup_owned() {
  local fd pid path attempt active backend index root_identity
  local descendant descendant_identity depth level max_depth=0
  local -a fds=() pids=() root_identities=() paths=()
  local -a descendant_pids=() descendant_identities=() descendant_depths=()
  local -A descendant_seen=()

  fds=("${DOT_CLEANUP_FDS[@]+"${DOT_CLEANUP_FDS[@]}"}")
  pids=("${DOT_CLEANUP_PIDS[@]+"${DOT_CLEANUP_PIDS[@]}"}")
  root_identities=("${DOT_CLEANUP_PID_IDENTITIES[@]+"${DOT_CLEANUP_PID_IDENTITIES[@]}"}")
  paths=("${DOT_CLEANUP_PATHS[@]+"${DOT_CLEANUP_PATHS[@]}"}")
  _dot_cleanup_process_backend backend

  for fd in "${fds[@]+"${fds[@]}"}"; do
    [[ -n "$fd" ]] || continue
    _dot_cleanup_close_fd "$fd"
  done

  # Prompt-capable workers intentionally remain in the terminal's foreground
  # group. Before terminating their exact Bash jobs, conservatively capture
  # identity-validated descendants so a synchronous external command cannot be
  # orphaned when only the parent receives a signal. This is bounded cleanup
  # for cooperative workers, not atomic daemon containment: uncertain process
  # table edges are dropped rather than risking an unrelated PID.
  index=0
  for pid in "${pids[@]+"${pids[@]}"}"; do
    root_identity="${root_identities[$index]:-}"
    index=$((index + 1))
    [[ -n "$pid" && -n "$root_identity" ]] || continue
    _dot_cleanup_job_matches "$pid" active || continue
    while IFS=$'\t' read -r descendant descendant_identity depth; do
      [[ "$descendant" =~ ^[1-9][0-9]*$ && -n "$descendant_identity" &&
        "$depth" =~ ^[1-9][0-9]*$ ]] || continue
      [[ -z "${descendant_seen[$descendant]:-}" ]] || continue
      descendant_seen["$descendant"]=1
      descendant_pids+=("$descendant")
      descendant_identities+=("$descendant_identity")
      descendant_depths+=("$depth")
      ((depth > max_depth)) && max_depth=$depth
    done < <(_dot_cleanup_descendant_records "$backend" "$pid" "$root_identity")
  done

  # TERM leaves first opportunity for orderly shutdown. Notify each exact Bash
  # wrapper before its foreground descendants: Bash defers a trapped signal
  # while waiting, so the pending trap then runs when the descendant exits
  # instead of `set -e` winning that race first.
  for pid in "${pids[@]+"${pids[@]}"}"; do
    [[ -n "$pid" ]] || continue
    _dot_cleanup_job_matches "$pid" active || continue
    kill -TERM "$pid" 2>/dev/null || true
  done

  # Descendants still shut down deepest-first using the identities captured
  # while every validated ancestor was present.
  for ((level = max_depth; level >= 1; level--)); do
    [[ ${descendant_pids[*]+set} == set ]] || break
    for index in "${!descendant_pids[@]}"; do
      [[ "${descendant_depths[$index]}" -eq "$level" ]] || continue
      descendant=${descendant_pids[$index]}
      descendant_identity=${descendant_identities[$index]}
      if _dot_cleanup_process_matches_live "$backend" "$descendant" "$descendant_identity"; then
        kill -TERM "$descendant" 2>/dev/null || true
      fi
    done
  done

  for ((attempt = 0; attempt < 20; attempt++)); do
    active=0
    if [[ ${descendant_pids[*]+set} == set ]]; then
      for index in "${!descendant_pids[@]}"; do
        if _dot_cleanup_process_matches_live "$backend" \
          "${descendant_pids[$index]}" "${descendant_identities[$index]}"; then
          active=1
          break
        fi
      done
    fi
    for pid in "${pids[@]+"${pids[@]}"}"; do
      [[ -n "$pid" ]] || continue
      if _dot_cleanup_job_matches "$pid" active; then
        active=1
        break
      fi
    done
    [[ "$active" -eq 1 ]] || break
    # A later terminal-group signal can interrupt this external sleep even
    # though its trap correctly leaves the first signal authoritative. Do not
    # let errexit abort cleanup before escalation and exact reaping complete.
    sleep 0.05 || true
  done

  # Stop still-active roots before descendant KILL so they cannot launch more
  # work during escalation. Identity checks make every descendant signal
  # fail-closed if its PID no longer names the process captured above.
  for pid in "${pids[@]+"${pids[@]}"}"; do
    [[ -n "$pid" ]] || continue
    if _dot_cleanup_job_matches "$pid" active; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  for ((level = 1; level <= max_depth; level++)); do
    [[ ${descendant_pids[*]+set} == set ]] || break
    for index in "${!descendant_pids[@]}"; do
      [[ "${descendant_depths[$index]}" -eq "$level" ]] || continue
      descendant=${descendant_pids[$index]}
      descendant_identity=${descendant_identities[$index]}
      if _dot_cleanup_process_matches_live "$backend" "$descendant" "$descendant_identity"; then
        kill -KILL "$descendant" 2>/dev/null || true
      fi
    done
  done

  for pid in "${pids[@]+"${pids[@]}"}"; do
    [[ -n "$pid" ]] || continue
    _dot_cleanup_wait_job "$pid"
    _dot_cleanup_unregister_pid "$pid"
  done

  for path in "${paths[@]+"${paths[@]}"}"; do
    [[ -n "$path" ]] || continue
    _dot_cleanup_remove_path "$path" || true
  done

  return 0
}

_dot_cleanup_all() {
  [[ "$DOT_CLEANUP_RUNNING" -eq 0 ]] || return 0
  DOT_CLEANUP_RUNNING=1
  _dot_cleanup_owned
  DOT_CLEANUP_RUNNING=0
}

_dot_cleanup_prepare_subshell() {
  _dot_cleanup_reset
  trap '_dot_cleanup_ignore_signals; _dot_cleanup_all' EXIT
  trap '_dot_cleanup_signal 129' HUP
  trap '_dot_cleanup_signal 130' INT
  trap '_dot_cleanup_signal 131' QUIT
  trap '_dot_cleanup_signal 143' TERM
}
