# shellcheck shell=bash
# runner.sh - dot-test runner coverage.

dot_core_test_runner() {
  echo "=== dot-test runner ==="

  _dot_runner_tests=$(_tmpdir)
  _dot_runner_bin=$(_tmpdir)
  _dot_runner_input="$(_tmpdir)/stdin.txt"
  _dot_runner_setsid_log="$(_tmpdir)/setsid.log"
  printf '%s\n' "leaked stdin" >"$_dot_runner_input"
  cat >"$_dot_runner_tests/stdin-test" <<'DOTRUNNER'
#!/usr/bin/env bash
set -o pipefail
if IFS= read -r leaked; then
  printf 'stdin leaked: %s\n' "$leaked" >&2
  exit 1
fi
printf 'Results: 1 passed, 0 failed\n'
exit 0
DOTRUNNER
  chmod +x "$_dot_runner_tests/stdin-test"
  cat >"$_dot_runner_bin/setsid" <<'DOTRUNNER'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOT_TEST_SETSID_LOG"
exec "$@"
DOTRUNNER
  chmod +x "$_dot_runner_bin/setsid"

  _dot_runner_lifecycle_parent=$(_tmpdir)
  _dot_runner_lifecycle_root="$_dot_runner_lifecycle_parent/dot-test-runs.$EUID"
  _dot_runner_lifecycle_tests=$(_tmpdir)
  _dot_runner_old_dead="$_dot_runner_lifecycle_root/run.old-dead"
  _dot_runner_recent_dead="$_dot_runner_lifecycle_root/run.recent-dead"
  _dot_runner_old_live="$_dot_runner_lifecycle_root/run.old-live"
  _dot_runner_unmarked="$_dot_runner_lifecycle_root/run.unmarked"
  _dot_runner_malformed="$_dot_runner_lifecycle_root/run.malformed"
  _dot_runner_malformed_time="$_dot_runner_lifecycle_root/run.malformed-time"
  _dot_runner_symlink="$_dot_runner_lifecycle_root/run.symlink"
  _dot_runner_symlink_target="$_dot_runner_lifecycle_parent/symlink-target"
  mkdir -p "$_dot_runner_old_dead" "$_dot_runner_recent_dead" \
    "$_dot_runner_old_live" "$_dot_runner_unmarked" \
    "$_dot_runner_malformed" "$_dot_runner_malformed_time" \
    "$_dot_runner_symlink_target"
  ln -s "$_dot_runner_symlink_target" "$_dot_runner_symlink"
  _dot_runner_dead_pid=9999999999
  _dot_runner_now=$(date +%s)
  printf '%s\t%s\n' "$_dot_runner_dead_pid" 1 \
    >"$_dot_runner_old_dead/.dot-test-owner-v2"
  printf '%s\t%s\n' "$_dot_runner_dead_pid" "$_dot_runner_now" \
    >"$_dot_runner_recent_dead/.dot-test-owner-v2"
  printf '%s\t%s\n' "$$" 1 >"$_dot_runner_old_live/.dot-test-owner-v2"
  printf 'not-a-pid\tnot-a-time\n' >"$_dot_runner_malformed/.dot-test-owner-v2"
  printf '%s\tnot-a-time\n' "$_dot_runner_dead_pid" \
    >"$_dot_runner_malformed_time/.dot-test-owner-v2"
  cat >"$_dot_runner_lifecycle_tests/lifecycle-test" <<'DOTRUNNER'
#!/usr/bin/env bash
printf 'Results: 1 passed, 0 failed\n'
DOTRUNNER
  chmod +x "$_dot_runner_lifecycle_tests/lifecycle-test"
  TMPDIR="$_dot_runner_lifecycle_parent" \
    DOT_TEST_TESTS_DIR="$_dot_runner_lifecycle_tests" DOT_TEST_NO_COLOR=1 \
    "$BIN_DIR/dot-test" -s lifecycle >/dev/null 2>&1
  _dot_runner_lifecycle_rc=$?
  _assert_exit "dot-test temp lifecycle: cleanup probe succeeds" \
    0 "$_dot_runner_lifecycle_rc"
  _dot_runner_concurrent_parent=$(_tmpdir)
  TMPDIR="$_dot_runner_concurrent_parent" \
    DOT_TEST_TESTS_DIR="$_dot_runner_lifecycle_tests" DOT_TEST_NO_COLOR=1 \
    "$BIN_DIR/dot-test" -s lifecycle >/dev/null 2>&1 &
  _dot_runner_concurrent_one=$!
  TMPDIR="$_dot_runner_concurrent_parent" \
    DOT_TEST_TESTS_DIR="$_dot_runner_lifecycle_tests" DOT_TEST_NO_COLOR=1 \
    "$BIN_DIR/dot-test" -s lifecycle >/dev/null 2>&1 &
  _dot_runner_concurrent_two=$!
  _dot_runner_concurrent_one_rc=0
  _dot_runner_concurrent_two_rc=0
  wait "$_dot_runner_concurrent_one" || _dot_runner_concurrent_one_rc=$?
  wait "$_dot_runner_concurrent_two" || _dot_runner_concurrent_two_rc=$?
  _assert_exit "dot-test temp lifecycle: first concurrent runner succeeds" \
    0 "$_dot_runner_concurrent_one_rc"
  _assert_exit "dot-test temp lifecycle: second concurrent runner succeeds" \
    0 "$_dot_runner_concurrent_two_rc"
  _dot_runner_wait_block=$(sed -n '/^_wait_job_bounded()/,/^}/p' "$BIN_DIR/dot-test")
  # These are literal implementation contracts, not shell expressions here.
  # shellcheck disable=SC2016
  _assert_contains "dot-test wait: uses a complete polling budget" \
    'remaining=$((limit * 20))' "$_dot_runner_wait_block"
  # shellcheck disable=SC2016
  _assert_not_contains "dot-test wait: avoids coarse integer-second deadlines" \
    'started=$SECONDS' "$_dot_runner_wait_block"
  if [[ ! -e "$_dot_runner_old_dead" && ! -L "$_dot_runner_old_dead" ]]; then
    _pass "dot-test temp lifecycle: old dead runner is reclaimed"
  else
    _fail "dot-test temp lifecycle: old dead runner is reclaimed"
  fi
  for _dot_runner_preserved in \
    "$_dot_runner_recent_dead" "$_dot_runner_old_live" \
    "$_dot_runner_unmarked" "$_dot_runner_malformed" \
    "$_dot_runner_malformed_time"; do
    if [[ -d "$_dot_runner_preserved" ]]; then
      _pass "dot-test temp lifecycle: preserves ${_dot_runner_preserved##*.} runner"
    else
      _fail "dot-test temp lifecycle: preserves ${_dot_runner_preserved##*.} runner"
    fi
  done
  if [[ -L "$_dot_runner_symlink" && -d "$_dot_runner_symlink_target" ]]; then
    _pass "dot-test temp lifecycle: preserves symlink runner"
  else
    _fail "dot-test temp lifecycle: preserves symlink runner"
  fi
  _dot_runner_lifecycle_count=0
  for _dot_runner_lifecycle_dir in "$_dot_runner_lifecycle_root"/run.*; do
    [[ -d "$_dot_runner_lifecycle_dir" && ! -L "$_dot_runner_lifecycle_dir" ]] || continue
    _dot_runner_lifecycle_count=$((_dot_runner_lifecycle_count + 1))
  done
  _assert_eq "dot-test temp lifecycle: completed runners remove their roots" \
    5 "$_dot_runner_lifecycle_count"

  _dot_runner_parallel_output=$(
    PATH="$_dot_runner_bin:$PATH" DOT_TEST_SETSID_LOG="$_dot_runner_setsid_log" \
      DOT_TEST_TESTS_DIR="$_dot_runner_tests" DOT_TEST_JOBS=1 DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" stdin <"$_dot_runner_input" 2>&1
  )
  _dot_runner_parallel_rc=$?
  _assert_exit "dot-test parallel: child stdin is closed" 0 "$_dot_runner_parallel_rc"
  _assert_not_contains "dot-test parallel: child does not see caller stdin" \
    "stdin leaked" "$_dot_runner_parallel_output"
  _assert_contains "dot-test parallel: suite is detached" \
    "$_dot_runner_tests/stdin-test" "$(cat "$_dot_runner_setsid_log")"

  : >"$_dot_runner_setsid_log"
  _dot_runner_sequential_output=$(
    PATH="$_dot_runner_bin:$PATH" DOT_TEST_SETSID_LOG="$_dot_runner_setsid_log" \
      DOT_TEST_TESTS_DIR="$_dot_runner_tests" DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" -s stdin <"$_dot_runner_input" 2>&1
  )
  _dot_runner_sequential_rc=$?
  _assert_exit "dot-test sequential: child stdin is closed" 0 "$_dot_runner_sequential_rc"
  _assert_not_contains "dot-test sequential: child does not see caller stdin" \
    "stdin leaked" "$_dot_runner_sequential_output"
  _assert_eq "dot-test sequential: suite stays foreground" \
    "" "$(cat "$_dot_runner_setsid_log")"

  _dot_runner_filter_tests=$(_tmpdir)
  for _dot_runner_filter_name in filter filter-extra; do
    cat >"$_dot_runner_filter_tests/${_dot_runner_filter_name}-test" <<'DOTRUNNER'
#!/usr/bin/env bash
printf 'Results: 1 passed, 0 failed\n'
DOTRUNNER
    chmod +x "$_dot_runner_filter_tests/${_dot_runner_filter_name}-test"
  done
  _dot_runner_filter_output=$(
    DOT_TEST_TESTS_DIR="$_dot_runner_filter_tests" DOT_TEST_NO_COLOR=1 \
      _with_timeout 5 "$BIN_DIR/dot-test" filter filter-extra 2>&1
  )
  _dot_runner_filter_rc=$?
  _assert_exit "dot-test filters: overlapping selections finish" \
    0 "$_dot_runner_filter_rc"
  _assert_contains "dot-test filters: overlapping selections run each suite once" \
    "Running 2 test suites" "$_dot_runner_filter_output"

  # The automatic worker cap smooths process-heavy full runs on high-core
  # hosts. Exercise it through the public runner rather than duplicating the
  # helper's arithmetic here, and prove an explicit operator choice still wins.
  _dot_runner_jobs_tests=$(_tmpdir)
  _dot_runner_jobs_bin=$(_tmpdir)
  for _dot_runner_job_index in {1..25}; do
    cat >"$_dot_runner_jobs_tests/job-$_dot_runner_job_index-test" <<'DOTRUNNER'
#!/usr/bin/env bash
printf 'Results: 1 passed, 0 failed\n'
DOTRUNNER
    chmod +x "$_dot_runner_jobs_tests/job-$_dot_runner_job_index-test"
  done
  cat >"$_dot_runner_jobs_bin/getconf" <<'DOTRUNNER'
#!/usr/bin/env bash
printf '64\n'
DOTRUNNER
  chmod +x "$_dot_runner_jobs_bin/getconf"

  _dot_runner_default_jobs_output=$(
    # Shared CI sets DOT_TEST_JOBS to bound each platform container. This
    # fixture owns the automatic-selection case, so isolate it from that
    # operator override before exercising the public runner.
    unset DOT_TEST_JOBS
    PATH="$_dot_runner_jobs_bin:$PATH" DOT_TEST_TESTS_DIR="$_dot_runner_jobs_tests" \
      DOT_TEST_NO_COLOR=1 "$BIN_DIR/dot-test" 2>&1
  )
  _assert_contains "dot-test jobs: automatic high-core selection is capped" \
    "Running 25 test suites with up to 24 jobs" \
    "$_dot_runner_default_jobs_output"

  _dot_runner_explicit_jobs_output=$(
    PATH="$_dot_runner_jobs_bin:$PATH" DOT_TEST_TESTS_DIR="$_dot_runner_jobs_tests" \
      DOT_TEST_JOBS=25 DOT_TEST_NO_COLOR=1 "$BIN_DIR/dot-test" 2>&1
  )
  _assert_contains "dot-test jobs: explicit worker selection overrides the cap" \
    "Running 25 test suites with up to 25 jobs" \
    "$_dot_runner_explicit_jobs_output"

  _dot_runner_flag_jobs_output=$(
    PATH="$_dot_runner_jobs_bin:$PATH" DOT_TEST_TESTS_DIR="$_dot_runner_jobs_tests" \
      DOT_TEST_NO_COLOR=1 "$BIN_DIR/dot-test" -j 25 2>&1
  )
  _assert_contains "dot-test jobs: -j worker selection overrides the cap" \
    "Running 25 test suites with up to 25 jobs" \
    "$_dot_runner_flag_jobs_output"

  _assert_contains "dot-test shards: static wrapper suppresses runner coverage" \
    "DOT_CORE_SHARD=static" \
    "$(cat "$HOME/.local/lib/dot/tests/core-static-test")"

  _dot_runner_timeout_tests=$(_tmpdir)
  cat >"$_dot_runner_timeout_tests/hang-test" <<'DOTRUNNER'
#!/usr/bin/env bash
while :; do
  sleep 1
done
DOTRUNNER
  chmod +x "$_dot_runner_timeout_tests/hang-test"
  _dot_runner_timeout_output=$(
    PATH="$_dot_runner_bin:$PATH" DOT_TEST_SETSID_LOG="$_dot_runner_setsid_log" \
      DOT_TEST_TESTS_DIR="$_dot_runner_timeout_tests" DOT_TEST_JOBS=1 \
      DOT_TEST_SUITE_TIMEOUT_SECONDS=1 DOT_TEST_NO_COLOR=1 \
      _with_timeout 5 "$BIN_DIR/dot-test" 2>&1
  )
  _dot_runner_timeout_rc=$?
  _assert_exit "dot-test parallel: hanging suite fails within its deadline" \
    1 "$_dot_runner_timeout_rc"
  _assert_contains "dot-test parallel: timed-out suite is reported" \
    "Failed: hang-test" "$_dot_runner_timeout_output"

  _dot_runner_descendant_tests=$(_tmpdir)
  _dot_runner_descendant_pid_file="$_dot_runner_descendant_tests/descendant.pid"
  cat >"$_dot_runner_descendant_tests/descendant-test" <<'DOTRUNNER'
#!/usr/bin/env bash
python3 - "$DOT_TEST_DESCENDANT_PID_FILE" <<'PY' &
import os
import sys
import time
from pathlib import Path

os.setpgid(0, 0)
Path(sys.argv[1]).write_text(str(os.getpid()), encoding="utf-8")
time.sleep(300)
PY
while [[ ! -s "$DOT_TEST_DESCENDANT_PID_FILE" ]]; do
  sleep 0.01
done
printf 'Results: 1 passed, 0 failed\n'
exit 0
DOTRUNNER
  chmod +x "$_dot_runner_descendant_tests/descendant-test"
  _dot_runner_descendant_output=$(
    DOT_TEST_DESCENDANT_PID_FILE="$_dot_runner_descendant_pid_file" \
      DOT_TEST_TESTS_DIR="$_dot_runner_descendant_tests" DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" -s descendant 2>&1
  )
  _dot_runner_descendant_rc=$?
  _assert_exit "dot-test sequential: passing suite with a descendant succeeds" \
    0 "$_dot_runner_descendant_rc"
  if [[ -s "$_dot_runner_descendant_pid_file" ]]; then
    _dot_runner_descendant_pid=$(cat "$_dot_runner_descendant_pid_file")
    _dot_runner_descendant_started=$SECONDS
    while kill -0 "$_dot_runner_descendant_pid" 2>/dev/null; do
      _dot_runner_descendant_state=$(ps -o stat= -p "$_dot_runner_descendant_pid" 2>/dev/null) || break
      [[ "$_dot_runner_descendant_state" =~ ^[[:space:]]*Z ]] && break
      ((SECONDS - _dot_runner_descendant_started >= 5)) && break
      sleep 0.05
    done
    _dot_runner_descendant_state=$(ps -o stat= -p "$_dot_runner_descendant_pid" 2>/dev/null || true)
    if kill -0 "$_dot_runner_descendant_pid" 2>/dev/null &&
      [[ ! "$_dot_runner_descendant_state" =~ ^[[:space:]]*Z ]]; then
      _fail "dot-test sequential: passing suite stops its descendant"
      kill -KILL "$_dot_runner_descendant_pid" 2>/dev/null || true
    else
      _pass "dot-test sequential: passing suite stops its descendant"
    fi
  else
    _fail "dot-test sequential: passing suite records its descendant"
  fi

  _dot_runner_escape_tests=$(_tmpdir)
  _dot_runner_escape_pid_file="$_dot_runner_escape_tests/escaped.pid"
  cat >"$_dot_runner_escape_tests/escaped-test" <<'DOTRUNNER'
#!/usr/bin/env bash
python3 - "$DOT_TEST_ESCAPED_PID_FILE" <<'PY' &
import subprocess
import sys

process = subprocess.Popen(
    [sys.executable, "-c", "import time; time.sleep(15)"],
    start_new_session=True,
)
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(str(process.pid))
PY
while :; do
  sleep 1
done
DOTRUNNER
  chmod +x "$_dot_runner_escape_tests/escaped-test"
  SECONDS=0
  _dot_runner_escape_output=$(
    PATH="$_dot_runner_bin:$PATH" DOT_TEST_SETSID_LOG="$_dot_runner_setsid_log" \
      DOT_TEST_ESCAPED_PID_FILE="$_dot_runner_escape_pid_file" \
      DOT_TEST_TESTS_DIR="$_dot_runner_escape_tests" DOT_TEST_SUITE_TIMEOUT_SECONDS=1 \
      DOT_TEST_NO_COLOR=1 _with_timeout 20 "$BIN_DIR/dot-test" -s 2>&1
  )
  _dot_runner_escape_rc=$?
  _dot_runner_escape_elapsed=$SECONDS
  if [[ -s "$_dot_runner_escape_pid_file" ]]; then
    _dot_runner_escape_pid=$(cat "$_dot_runner_escape_pid_file")
    kill -KILL "$_dot_runner_escape_pid" 2>/dev/null || true
  fi
  _assert_exit "dot-test sequential: escaped writer cannot bypass suite deadline" \
    1 "$_dot_runner_escape_rc"
  _assert_contains "dot-test sequential: escaped-writer timeout is reported" \
    "Failed: escaped-test" "$_dot_runner_escape_output"
  if [[ "$_dot_runner_escape_elapsed" -le 8 ]]; then
    _pass "dot-test sequential: escaped writer cannot delay timeout reporting"
  else
    _fail "dot-test sequential: escaped writer cannot delay timeout reporting"
  fi

  _assert_dot_runner_cancellation() {
    local mode="$1"
    shift
    local cancel_tests cancel_pid_file cancel_output cancel_pid cancel_rc
    local suite_pid started state

    cancel_tests=$(_tmpdir)
    cancel_pid_file="$cancel_tests/suite.pid"
    cancel_output="$cancel_tests/runner.out"
    cat >"$cancel_tests/cancel-test" <<'DOTRUNNER'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$DOT_TEST_CANCEL_SUITE_PID_FILE"
while :; do
  sleep 1
done
DOTRUNNER
    chmod +x "$cancel_tests/cancel-test"
    PATH="$_dot_runner_bin:$PATH" DOT_TEST_SETSID_LOG="$_dot_runner_setsid_log" \
      DOT_TEST_CANCEL_SUITE_PID_FILE="$cancel_pid_file" \
      DOT_TEST_TESTS_DIR="$cancel_tests" DOT_TEST_JOBS=1 \
      DOT_TEST_SUITE_TIMEOUT_SECONDS=30 DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" "$@" >"$cancel_output" 2>&1 &
    cancel_pid=$!
    started=$SECONDS
    while [[ ! -s "$cancel_pid_file" ]]; do
      if ((SECONDS - started >= 5)); then
        break
      fi
      sleep 0.05
    done
    if [[ -s "$cancel_pid_file" ]]; then
      kill -TERM "$cancel_pid"
      cancel_rc=0
      wait "$cancel_pid" || cancel_rc=$?
      _assert_exit "dot-test $mode: cancellation preserves signal status" 143 "$cancel_rc"

      suite_pid=$(cat "$cancel_pid_file")
      started=$SECONDS
      while kill -0 "$suite_pid" 2>/dev/null; do
        state=$(ps -o stat= -p "$suite_pid" 2>/dev/null) || break
        [[ "$state" =~ ^[[:space:]]*Z ]] && break
        if ((SECONDS - started >= 5)); then
          break
        fi
        sleep 0.05
      done
      state=$(ps -o stat= -p "$suite_pid" 2>/dev/null || true)
      if kill -0 "$suite_pid" 2>/dev/null && [[ ! "$state" =~ ^[[:space:]]*Z ]]; then
        _fail "dot-test $mode: cancellation stops active suite"
        kill -KILL "$suite_pid" 2>/dev/null || true
      else
        _pass "dot-test $mode: cancellation stops active suite"
      fi
    else
      _fail "dot-test $mode: cancellation fixture becomes ready"
      kill -TERM "$cancel_pid" 2>/dev/null || true
      wait "$cancel_pid" 2>/dev/null || true
    fi
  }
  _assert_dot_runner_cancellation parallel
  _assert_dot_runner_cancellation sequential -s

  # Worktree ergonomics: running dot-test from a linked worktree should exercise
  # that tree's files without forcing developers to create helper symlinks for
  # host-installed dependencies. DOT_TEST_SOURCE_HOME models the discovered
  # worktree; DOT_TEST_HOST_HOME models the real machine home.
  _dot_runner_source_home=$(_tmpdir)
  _dot_runner_host_home=$(_tmpdir)
  _dot_runner_source_home_real=$(_test_realpath "$_dot_runner_source_home")
  _dot_runner_host_home_real=$(_test_realpath "$_dot_runner_host_home")
  _dot_runner_source_tests=$(_tmpdir)
  _dot_runner_source_log=$(_tmpdir)/source-home.log
  mkdir -p "$_dot_runner_source_home/.local/bin" \
    "$_dot_runner_source_home/.local/lib/dot/core" \
    "$_dot_runner_source_home/.local/lib/dot/tests" \
    "$_dot_runner_host_home/git/shdeps" \
    "$_dot_runner_host_home/.local/share/mise" \
    "$_dot_runner_host_home/.local/state/mise" \
    "$_dot_runner_host_home/.cache/mise"
  cp "$BIN_DIR/dot-test" "$_dot_runner_source_home/.local/bin/dot-test"
  cp "$REAL_HOME/.local/lib/dot/core/ui.sh" "$_dot_runner_source_home/.local/lib/dot/core/ui.sh"
  cp "$REAL_HOME/.local/lib/dot/tests/timeout.py" \
    "$_dot_runner_source_home/.local/lib/dot/tests/timeout.py"
  printf '%s\n' '# fake shdeps' >"$_dot_runner_host_home/git/shdeps/shdeps.sh"
  cat >"$_dot_runner_source_tests/home-test" <<'DOTRUNNER'
#!/usr/bin/env bash
{
  printf 'HOME=%s\n' "$HOME"
  printf 'SOURCE=%s\n' "${DOT_TEST_SOURCE_HOME:-}"
  printf 'HOST=%s\n' "${DOT_TEST_HOST_HOME:-}"
  printf 'SHDEPS_LIB=%s\n' "${SHDEPS_LIB:-}"
  printf 'MISE_DATA_DIR=%s\n' "${MISE_DATA_DIR:-}"
  printf 'PATH=%s\n' "$PATH"
}
printf 'Results: 1 passed, 0 failed\n'
DOTRUNNER
  chmod +x "$_dot_runner_source_home/.local/bin/dot-test" "$_dot_runner_source_tests/home-test"
  env -u SHDEPS_LIB -u SHDEPS_DIR -u MISE_DATA_DIR -u MISE_STATE_DIR -u MISE_CACHE_DIR \
    DOT_TEST_SOURCE_HOME="$_dot_runner_source_home" \
    DOT_TEST_HOST_HOME="$_dot_runner_host_home" \
    DOT_TEST_TESTS_DIR="$_dot_runner_source_tests" \
    DOT_TEST_NO_COLOR=1 \
    "$_dot_runner_source_home/.local/bin/dot-test" -s home >"$_dot_runner_source_log" 2>&1
  _dot_runner_source_rc=$?
  _assert_exit "dot-test worktree: source-home run succeeds" 0 "$_dot_runner_source_rc"
  _dot_runner_source_result=$(cat "$_dot_runner_source_log")
  _assert_contains "dot-test worktree: child HOME is source tree" \
    "HOME=$_dot_runner_source_home_real" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: DOT_TEST_SOURCE_HOME is exported" \
    "SOURCE=$_dot_runner_source_home_real" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: host home is preserved" \
    "HOST=$_dot_runner_host_home" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: global shdeps env is left to suites" \
    "SHDEPS_LIB=" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: mise data comes from host home" \
    "MISE_DATA_DIR=$_dot_runner_host_home/.local/share/mise" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: source launchers stay first on PATH" \
    "PATH=$_dot_runner_source_home_real/.local/bin:" "$_dot_runner_source_result"
  _assert_contains "dot-test worktree: host launchers remain available" \
    ":$_dot_runner_host_home/.local/bin" "$_dot_runner_source_result"

  # shellcheck disable=SC2016 # The child shell receives $1 as source home.
  env -u DOT_TEST_SOURCE_HOME -u DOT_TEST_HOST_HOME -u SHDEPS_LIB -u SHDEPS_DIR \
    -u MISE_DATA_DIR -u MISE_STATE_DIR -u MISE_CACHE_DIR \
    HOME="$_dot_runner_host_home" \
    DOT_TEST_TESTS_DIR="$_dot_runner_source_tests" \
    DOT_TEST_NO_COLOR=1 \
    bash -c 'cd "$1" || exit 97; exec "$1/.local/bin/dot-test" -s home' \
    bash "$_dot_runner_source_home" >"$_dot_runner_source_log" 2>&1
  _dot_runner_discovered_rc=$?
  _assert_exit "dot-test worktree: cwd-discovered run succeeds" \
    0 "$_dot_runner_discovered_rc"
  _dot_runner_discovered_result=$(cat "$_dot_runner_source_log")
  _assert_contains "dot-test worktree: cwd discovery uses source tree" \
    "HOME=$_dot_runner_source_home_real" "$_dot_runner_discovered_result"
  _assert_contains "dot-test worktree: cwd discovery preserves host home" \
    "HOST=$_dot_runner_host_home_real" "$_dot_runner_discovered_result"

  if ! command -v setsid >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    _dot_runner_session_tests=$(_tmpdir)
    _dot_runner_session_log="$(_tmpdir)/session.log"
    cat >"$_dot_runner_session_tests/session-test" <<'DOTRUNNER'
#!/usr/bin/env bash
python3 - "$DOT_TEST_SESSION_LOG" <<'PY'
import os
import sys

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    handle.write(f"{os.getsid(0)}\n")
PY
printf 'Results: 1 passed, 0 failed\n'
DOTRUNNER
    chmod +x "$_dot_runner_session_tests/session-test"

    _dot_runner_parent_sid=$(
      python3 - <<'PY'
import os

print(os.getsid(0))
PY
    )
    _dot_runner_session_output=$(
      DOT_TEST_SESSION_LOG="$_dot_runner_session_log" \
        DOT_TEST_TESTS_DIR="$_dot_runner_session_tests" DOT_TEST_JOBS=1 \
        DOT_TEST_NO_COLOR=1 "$BIN_DIR/dot-test" session 2>&1
    )
    _dot_runner_session_rc=$?
    _assert_exit "dot-test parallel: python detacher run succeeds" 0 "$_dot_runner_session_rc"
    _dot_runner_child_sid=$(cat "$_dot_runner_session_log" 2>/dev/null)
    if [[ "$_dot_runner_child_sid" != "$_dot_runner_parent_sid" ]]; then
      _pass "dot-test parallel: python detacher creates a new session"
    else
      _fail "dot-test parallel: python detacher creates a new session"
      printf '    parent sid: %s\n' "$_dot_runner_parent_sid" >&2
      printf '    child sid: %s\n' "$_dot_runner_child_sid" >&2
    fi
  fi

  # Green-on-error guard: suites do not run under `set -e`, so one that errors
  # mid-run and exits 0 without ever printing its results summary would read as a
  # false green. The runner must fail such an incomplete run, while still passing
  # a summarizing suite and skipping a SKIP: suite. Exercise both the parallel
  # and sequential classification paths.
  _dot_ge_tests=$(_tmpdir)
  printf '#!/usr/bin/env bash\necho "did setup then returned early"\nexit 0\n' \
    >"$_dot_ge_tests/incomplete-test"
  printf '#!/usr/bin/env bash\necho "Results: 1 passed, 0 failed"\nexit 0\n' \
    >"$_dot_ge_tests/good-test"
  printf '#!/usr/bin/env bash\necho "SKIP: not applicable here"\nexit 0\n' \
    >"$_dot_ge_tests/skipped-test"
  chmod +x "$_dot_ge_tests"/*-test

  _dot_ge_parallel=$(
    DOT_TEST_TESTS_DIR="$_dot_ge_tests" DOT_TEST_JOBS=1 DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" </dev/null 2>&1
  )
  _dot_ge_parallel_rc=$?
  _assert_exit "dot-test parallel: incomplete suite fails the run" 1 "$_dot_ge_parallel_rc"
  _assert_contains "dot-test parallel: incomplete suite is flagged" \
    "incomplete-test: exited 0 without a results summary" "$_dot_ge_parallel"
  _assert_contains "dot-test parallel: summarizing suite still passes" \
    "1 passed" "$_dot_ge_parallel"
  _assert_contains "dot-test parallel: SKIP suite still skips" \
    "skipped" "$_dot_ge_parallel"

  _dot_ge_sequential=$(
    DOT_TEST_TESTS_DIR="$_dot_ge_tests" DOT_TEST_NO_COLOR=1 \
      "$BIN_DIR/dot-test" -s </dev/null 2>&1
  )
  _dot_ge_sequential_rc=$?
  _assert_exit "dot-test sequential: incomplete suite fails the run" 1 "$_dot_ge_sequential_rc"
  _assert_contains "dot-test sequential: incomplete suite is flagged" \
    "incomplete-test: exited 0 without a results summary" "$_dot_ge_sequential"
}
