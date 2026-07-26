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
