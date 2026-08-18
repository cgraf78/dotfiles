# shellcheck shell=bash
# launchers.sh - launcher coverage.

dot_core_test_launchers() {
  echo ""
  echo "=== Normalize filtered ==="

  echo "modified" >"$TEST_HOME/.testrc"
  $GIT add .testrc
  $GIT commit -m "modified" >/dev/null 2>&1

  # Touch the file so stat differs (mtime) but content is same
  cp "$TEST_HOME/.testrc" "$TEST_HOME/.testrc.tmp"
  mv "$TEST_HOME/.testrc.tmp" "$TEST_HOME/.testrc"

  # File should show as "dirty" in diff-files (stat mismatch) but not in diff
  dirty=$($GIT diff-files --name-only 2>/dev/null || true)
  if [[ -n "$dirty" ]]; then
    # Stat-dirty but content-clean — dot status normalizes it as a side effect
    "$BIN_DIR/dot" status >/dev/null 2>&1
    dirty_after=$($GIT diff-files --name-only 2>/dev/null || true)
    _assert_eq "normalize: clears phantom dirty file" "" "$dirty_after"
  else
    _pass "normalize: file not stat-dirty (nothing to test)"
  fi

  # ---------------------------------------------------------------------------
  # Tests: dot command routing (via subprocess)
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Command routing ==="

  # dot status shows base dotfiles header
  result=$("$BIN_DIR/dot" status 2>&1)
  _assert_contains "status: base header" "dotfiles" "$result"

  # dot status without overlay dir: no overlay section
  _assert_not_contains "status: no overlay section without overlay dir" "work dotfiles" "$result"

  # dot status with overlay dir: shows both
  dot_fixture_file_origin OVERLAY_BARE "f" "x"
  OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$OVERLAY_DIR"

  result=$("$BIN_DIR/dot" status 2>&1)
  _assert_contains "status: base with overlay dir" "dotfiles" "$result"
  _assert_contains "status: overlay section present" "work dotfiles" "$result"

  _discover_overlays
  normalize_sync=$(_tmpdir)
  mkdir -p "$normalize_sync"
  # shellcheck disable=SC2329 # invoked indirectly by _normalize_filtered.
  _normalize_dirty_files() {
    local kind=base started=$SECONDS
    [[ "$*" != *" -C $OVERLAY_DIR"* ]] || kind=overlay
    : >"$normalize_sync/$kind.started"
    while [[ ! -e "$normalize_sync/base.started" || ! -e "$normalize_sync/overlay.started" ]]; do
      if ((SECONDS - started >= 5)); then
        : >"$normalize_sync/not-concurrent"
        break
      fi
      sleep 0.01
    done
    : >"$normalize_sync/$kind.finished"
  }
  _normalize_filtered
  _assert_file_missing "normalize parallel: repositories overlap" \
    "$normalize_sync/not-concurrent"
  _assert_file_exists "normalize parallel: drains base worker" \
    "$normalize_sync/base.finished"
  _assert_file_exists "normalize parallel: drains overlay worker" \
    "$normalize_sync/overlay.finished"
  unset -f _normalize_dirty_files
  # shellcheck disable=SC1091 # restore the production helper after the canary.
  . "$_DOT_REPOS_DIR/dirty.sh"

  rm -rf "$OVERLAY_DIR" "$OVERLAY_BARE"

  # dot with no args shows usage
  result=$("$BIN_DIR/dot" 2>&1 || true)
  _assert_contains "no args: usage" "usage:" "$result"

  # dot --help / -h / help print usage and exit 0 (not "unknown command")
  local _help_flag
  for _help_flag in --help -h help; do
    result=$("$BIN_DIR/dot" "$_help_flag" 2>&1)
    _assert_exit "help ($_help_flag): exits 0" 0 "$?"
    _assert_contains "help ($_help_flag): shows usage" "usage: dot" "$result"
    _assert_not_contains "help ($_help_flag): not treated as unknown" "unknown command" "$result"
  done

  # git launcher forwards args with flags against the base repo
  echo "tag-test" >"$TEST_HOME/.testrc"
  $GIT add .testrc
  $GIT commit -m "tag test" >/dev/null 2>&1

  # dot <unknown> prints error with hint
  result=$("$BIN_DIR/dot" log 2>&1 || true)
  _assert_contains "unknown cmd: error" "unknown command" "$result"
  _assert_contains "unknown cmd: hint" "git log" "$result"

  # dot <unknown> exits non-zero
  if "$BIN_DIR/dot" nosuchcommand 2>/dev/null; then
    _fail "unknown cmd: exits non-zero"
  else
    _pass "unknown cmd: exits non-zero"
  fi

  # dot <unknown> hint includes the actual command name
  result=$("$BIN_DIR/dot" branch 2>&1 || true)
  _assert_contains "unknown cmd: hint matches arg" "git branch" "$result"

  # dot <unknown> outputs on stderr only
  stdout=$("$BIN_DIR/dot" nosuchcommand 2>/dev/null || true)
  _assert_eq "unknown cmd: nothing on stdout" "" "$stdout"

  result=$("$BIN_DIR/dot" git log 2>&1 || true)
  _assert_contains "git removed: dot reports unknown command" \
    "unknown command: git" "$result"
  _assert_contains "git removed: dot suggests launcher" \
    "PATH-visible \"git\" launcher" "$result"

  # ---------------------------------------------------------------------------
  # Tests: git launcher
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== git launcher ==="

  _git_temporary_home=$(_tmpdir)
  _git_temporary_bin=$(_tmpdir)
  _git_temporary_cache=$(_tmpdir)
  cat >"$_git_temporary_bin/git" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  --version | version)
    printf 'git version temporary-home\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$_git_temporary_bin/git"
  result=$(
    cd "$REAL_HOME" &&
      env -u DOT_TEST_HOST_HOME -u DOT_TEST_SOURCE_HOME \
        HOME="$_git_temporary_home" \
        XDG_CACHE_HOME="$_git_temporary_cache" \
        PATH="$REAL_HOME/.local/bin:$_git_temporary_bin:/usr/bin:/bin" \
        "$REAL_HOME/.local/bin/git" version 2>&1
  )
  _assert_eq "git launcher temporary HOME: loads support beside itself" \
    "git version temporary-home" "$result"

  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" log --format=%s -1 2>&1)
  _assert_contains "git launcher base: routes HOME to bare dotfiles" \
    "tag test" "$result"

  # Detect the default branch name (master or main)
  DEFAULT_BRANCH=$($GIT branch --show-current 2>/dev/null || echo "master")
  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" branch 2>&1)
  _assert_contains "git launcher base: branch works" "$DEFAULT_BRANCH" "$result"

  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" stash list 2>&1 || true)
  _assert_not_contains "git launcher multi-arg: no error" "unknown command" "$result"

  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" log --format=%s -1 2>&1)
  _assert_contains "git launcher flags: format flag works" "tag test" "$result"

  (cd "$TEST_HOME" && "$BIN_DIR/git" diff --quiet 2>/dev/null)
  _assert_eq "git launcher exit code: clean diff returns 0" "0" "$?"

  if (cd "$TEST_HOME" && "$BIN_DIR/git" log --bad-flag 2>/dev/null); then
    _fail "git launcher exit code: bad flag returns non-zero"
  else
    _pass "git launcher exit code: bad flag returns non-zero"
  fi

  _git_fast_probe_bin=$(_tmpdir)
  _git_fast_probe_cache=$(_tmpdir)
  _git_fast_probe_log="$(_tmpdir)/git-fast-probe.log"
  cat >"$_git_fast_probe_bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_FAST_PROBE_LOG"
case "$1" in
  --version | version)
    printf 'git version fast-probe\n'
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$_git_fast_probe_bin/git"
  result=$(
    cd "$TEST_HOME" &&
      GIT_FAST_PROBE_LOG="$_git_fast_probe_log" \
        XDG_CACHE_HOME="$_git_fast_probe_cache" \
        PATH="$BIN_DIR:$_git_fast_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" --version 2>&1
  )
  _assert_contains "git launcher fast path: version reaches real git" \
    "git version fast-probe" "$result"
  _assert_not_contains "git launcher fast path: version skips worktree probe" \
    "rev-parse --show-toplevel" "$(cat "$_git_fast_probe_log" 2>/dev/null || true)"

  _git_home_probe_bin=$(_tmpdir)
  _git_home_probe_cache=$(_tmpdir)
  _git_home_probe_log="$(_tmpdir)/git-home-probe.log"
  cat >"$_git_home_probe_bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git:%s\n' "$*" >>"$GIT_HOME_PROBE_LOG"
case "$1" in
  rev-parse)
    exit 1
    ;;
  status)
    if [ "${GIT_DIR:-}" = "$GIT_HOME_PROBE_HOME/.dotfiles" ] &&
      [ "${GIT_WORK_TREE:-}" = "$GIT_HOME_PROBE_HOME" ]; then
      printf 'dotfiles-status\n'
      exit 0
    fi
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
  cat >"$_git_home_probe_bin/sl" <<'EOF'
#!/usr/bin/env bash
printf 'sl:%s\n' "$*" >>"$GIT_HOME_PROBE_LOG"
printf '%s\n' "$PWD"
EOF
  chmod +x "$_git_home_probe_bin/git" "$_git_home_probe_bin/sl"
  result=$(
    cd "$TEST_HOME" &&
      GIT_HOME_PROBE_HOME="$TEST_HOME" \
        GIT_HOME_PROBE_LOG="$_git_home_probe_log" \
        XDG_CACHE_HOME="$_git_home_probe_cache" \
        PATH="$BIN_DIR:$_git_home_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status 2>&1
  )
  _assert_contains "git launcher HOME root: routes to bare dotfiles" \
    "dotfiles-status" "$result"
  _assert_not_contains "git launcher HOME root: skips git worktree probe" \
    "git:rev-parse --show-toplevel" "$(cat "$_git_home_probe_log" 2>/dev/null || true)"
  _assert_not_contains "git launcher HOME root: skips Sapling probe" \
    "sl:root --config ui.color=never" "$(cat "$_git_home_probe_log" 2>/dev/null || true)"

  _git_exact_root_bin=$(_tmpdir)
  _git_exact_root_cache=$(_tmpdir)
  _git_exact_root_log="$(_tmpdir)/git-exact-root.log"
  _git_exact_root_base="$TEST_HOME/git/exact-root"
  mkdir -p "$_git_exact_root_base" "$_git_exact_root_cache/dotfiles"
  cat >"$_git_exact_root_bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_EXACT_ROOT_LOG"
case "$1" in
  rev-parse)
    printf '%s\n' "$GIT_EXACT_ROOT"
    ;;
esac
case "${!#}" in
  status)
    printf 'real-root-status\n'
    ;;
esac
EOF
  chmod +x "$_git_exact_root_bin/git"
  local _git_exact_marker _git_exact_mode _git_exact_expected
  for _git_exact_marker in git-dir git-file git-dangling sl-dir sl-file sl-dangling hg-dir hg-file hg-dangling; do
    _git_exact_root="$_git_exact_root_base/$_git_exact_marker"
    mkdir -p "$_git_exact_root"
    case "$_git_exact_marker" in
      git-dir) mkdir "$_git_exact_root/.git" ;;
      git-file) printf 'malformed gitfile\n' >"$_git_exact_root/.git" ;;
      git-dangling) ln -s missing-gitdir "$_git_exact_root/.git" ;;
      sl-dir) mkdir "$_git_exact_root/.sl" ;;
      sl-file) printf 'malformed marker\n' >"$_git_exact_root/.sl" ;;
      sl-dangling) ln -s missing-sldir "$_git_exact_root/.sl" ;;
      hg-dir) mkdir "$_git_exact_root/.hg" ;;
      hg-file) printf 'malformed marker\n' >"$_git_exact_root/.hg" ;;
      hg-dangling) ln -s missing-hgdir "$_git_exact_root/.hg" ;;
    esac

    for _git_exact_mode in cwd explicit-c; do
      : >"$_git_exact_root_log"
      printf 'sentinel\n' >"$_git_exact_root_cache/dotfiles/git-nested-worktree-roots"
      if [[ "$_git_exact_mode" == cwd ]]; then
        result=$(
          cd "$_git_exact_root" &&
            GIT_EXACT_ROOT="$_git_exact_root" \
              GIT_EXACT_ROOT_LOG="$_git_exact_root_log" \
              XDG_CACHE_HOME="$_git_exact_root_cache" \
              PATH="$BIN_DIR:$_git_exact_root_bin:/usr/bin:/bin" \
              "$BIN_DIR/git" status
        )
        _git_exact_expected="status"
      else
        result=$(
          cd "$TEST_HOME" &&
            GIT_EXACT_ROOT="$_git_exact_root" \
              GIT_EXACT_ROOT_LOG="$_git_exact_root_log" \
              XDG_CACHE_HOME="$_git_exact_root_cache" \
              PATH="$BIN_DIR:$_git_exact_root_bin:/usr/bin:/bin" \
              "$BIN_DIR/git" -C "$_git_exact_root" status
        )
        _git_exact_expected="-C $_git_exact_root status"
      fi
      _assert_eq "git launcher exact root ($_git_exact_marker, $_git_exact_mode): reaches real git" \
        "real-root-status" "$result"
      _assert_eq "git launcher exact root ($_git_exact_marker, $_git_exact_mode): executes only requested git" \
        "$_git_exact_expected" "$(cat "$_git_exact_root_log")"
      _assert_eq "git launcher exact root ($_git_exact_marker, $_git_exact_mode): leaves cache untouched" \
        "sentinel" "$(cat "$_git_exact_root_cache/dotfiles/git-nested-worktree-roots")"
    done
  done

  _git_cached_probe_bin=$(_tmpdir)
  _git_cached_probe_cache=$(_tmpdir)
  _git_cached_probe_log="$(_tmpdir)/git-cached-probe.log"
  _git_cached_probe_root="$TEST_HOME/git/cached-worktree"
  _git_cached_probe_subdir="$_git_cached_probe_root/project/src"
  _git_cached_probe_other="$TEST_HOME/git/cached-worktree-other"
  _git_cached_probe_other_subdir="$_git_cached_probe_other/project/src"
  mkdir -p \
    "$_git_cached_probe_bin" \
    "$_git_cached_probe_cache/dot" \
    "$_git_cached_probe_root/.git" \
    "$_git_cached_probe_subdir" \
    "$_git_cached_probe_other/.git" \
    "$_git_cached_probe_other_subdir"
  _git_cached_probe_root=$(cd "$_git_cached_probe_root" && pwd -P)
  _git_cached_probe_subdir=$(cd "$_git_cached_probe_subdir" && pwd -P)
  _git_cached_probe_other=$(cd "$_git_cached_probe_other" && pwd -P)
  _git_cached_probe_other_subdir=$(cd "$_git_cached_probe_other_subdir" && pwd -P)
  cat >"$_git_cached_probe_bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$GIT_CACHED_PROBE_LOG"
case "$1" in
  rev-parse)
    [[ "${GIT_CACHED_PROBE_MISS:-0}" -eq 0 ]] || exit 1
    printf '%s\n' "$GIT_CACHED_PROBE_ROOT"
    ;;
  status)
    if [[ -n "${GIT_CACHED_PROBE_HOME:-}" &&
      "${GIT_DIR:-}" == "$GIT_CACHED_PROBE_HOME/.dotfiles" ]]; then
      printf 'dotfiles-status\n'
    else
      printf 'real-git-status\n'
    fi
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$_git_cached_probe_bin/git"

  result=$(
    cd "$_git_cached_probe_subdir" &&
      GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_root" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: cold call reaches real git" \
    "real-git-status" "$result"

  _git_cached_probe_file="$_git_cached_probe_cache/dotfiles/git-nested-worktree-roots"
  _git_cached_probe_inode=$(
    stat -c '%i' "$_git_cached_probe_file" 2>/dev/null ||
      stat -f '%i' "$_git_cached_probe_file"
  )
  : >"$_git_cached_probe_log"
  result=$(
    cd "$_git_cached_probe_subdir" &&
      GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_root" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: warm call reaches real git" \
    "real-git-status" "$result"
  _assert_eq "git launcher nested Git cache: warm call executes only requested git" \
    "status" "$(cat "$_git_cached_probe_log")"
  _assert_eq "git launcher nested Git cache: warm call does not replace cache" \
    "$_git_cached_probe_inode" \
    "$(stat -c '%i' "$_git_cached_probe_file" 2>/dev/null ||
      stat -f '%i' "$_git_cached_probe_file")"

  printf 'git\t%s\ngit\t%s\n' \
    "$_git_cached_probe_root" "$_git_cached_probe_other" \
    >"$_git_cached_probe_file"
  _git_cached_probe_expected=$(cat "$_git_cached_probe_file")
  result=$(
    cd "$_git_cached_probe_subdir" &&
      GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_root" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: multi-root warm call succeeds" \
    "real-git-status" "$result"
  _assert_file_content "git launcher nested Git cache: warm hit preserves other roots" \
    "$_git_cached_probe_expected" "$_git_cached_probe_file"

  : >"$_git_cached_probe_log"
  result=$(
    cd "$_git_cached_probe_other_subdir" &&
      GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_other" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: alternate warm root succeeds" \
    "real-git-status" "$result"
  _assert_eq "git launcher nested Git cache: alternate warm root skips ownership probe" \
    "status" "$(cat "$_git_cached_probe_log")"
  _assert_file_content "git launcher nested Git cache: alternate hit preserves all roots" \
    "$_git_cached_probe_expected" "$_git_cached_probe_file"

  rm -rf "$_git_cached_probe_root/.git"
  printf 'malformed gitfile\n' >"$_git_cached_probe_root/.git"
  printf 'git\t%s\n' "$_git_cached_probe_root" >"$_git_cached_probe_file"
  : >"$_git_cached_probe_log"
  result=$(
    cd "$_git_cached_probe_subdir" &&
      GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_root" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: malformed cached marker stays Git-owned" \
    "real-git-status" "$result"
  _assert_eq "git launcher nested Git cache: malformed cached marker skips ownership probe" \
    "status" "$(cat "$_git_cached_probe_log")"

  rm -f "$_git_cached_probe_root/.git"
  : >"$_git_cached_probe_log"
  result=$(
    cd "$_git_cached_probe_subdir" &&
      GIT_CACHED_PROBE_HOME="$TEST_HOME" \
        GIT_CACHED_PROBE_LOG="$_git_cached_probe_log" \
        GIT_CACHED_PROBE_MISS=1 \
        GIT_CACHED_PROBE_ROOT="$_git_cached_probe_root" \
        XDG_CACHE_HOME="$_git_cached_probe_cache" \
        PATH="$BIN_DIR:$_git_cached_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested Git cache: removed marker falls back to dotfiles" \
    "dotfiles-status" "$result"
  _assert_file_content "git launcher nested Git cache: removed root is pruned" \
    "" "$_git_cached_probe_file"

  _git_nested_probe_bin=$(_tmpdir)
  _git_nested_probe_cache=$(_tmpdir)
  _git_nested_probe_log="$(_tmpdir)/git-nested-probe.log"
  _git_nested_probe_root="$TEST_HOME/git/nested-worktree"
  _git_nested_probe_subdir="$_git_nested_probe_root/nested-repository/project"
  mkdir -p "$_git_nested_probe_root/.sl" "$_git_nested_probe_subdir"
  cat >"$_git_nested_probe_bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git:%s\n' "$*" >>"$GIT_NESTED_PROBE_LOG"
case "$1" in
  rev-parse)
    exit 1
    ;;
  config)
    printf 'real-git-config\n'
    exit 0
    ;;
  status)
    if [ "${GIT_DIR:-}" = "$GIT_NESTED_PROBE_HOME/.dotfiles" ] &&
      [ "${GIT_WORK_TREE:-}" = "$GIT_NESTED_PROBE_HOME" ]; then
      printf 'dotfiles-status\n'
      exit 0
    fi
    printf 'real-git-status\n'
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF
  cat >"$_git_nested_probe_bin/sl" <<'EOF'
#!/usr/bin/env bash
printf 'sl:%s\n' "$*" >>"$GIT_NESTED_PROBE_LOG"
printf '%s\n' "$GIT_NESTED_PROBE_ROOT"
EOF
  chmod +x "$_git_nested_probe_bin/git" "$_git_nested_probe_bin/sl"

  local _git_stale_marker _git_stale_mode _git_stale_cache
  local _git_stale_root _git_stale_leaf
  for _git_stale_marker in sl hg; do
    for _git_stale_mode in file dangling; do
      _git_stale_cache=$(_tmpdir)
      _git_stale_root="$TEST_HOME/git/stale-$_git_stale_marker-$_git_stale_mode"
      _git_stale_leaf="$_git_stale_root/project"
      mkdir -p "$_git_stale_cache/dotfiles" "$_git_stale_leaf"
      case "$_git_stale_mode" in
        file)
          printf 'malformed marker\n' >"$_git_stale_root/.$_git_stale_marker"
          ;;
        dangling)
          ln -s missing-marker "$_git_stale_root/.$_git_stale_marker"
          ;;
      esac
      printf 'sl\t%s\n' "$_git_stale_root" \
        >"$_git_stale_cache/dotfiles/git-nested-worktree-roots"

      result=$(
        cd "$_git_stale_leaf" &&
          GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
            GIT_NESTED_PROBE_HOME="$TEST_HOME" \
            GIT_NESTED_PROBE_ROOT="$_git_stale_root" \
            XDG_CACHE_HOME="$_git_stale_cache" \
            PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
            "$BIN_DIR/git" status
      )
      _assert_eq "git launcher nested cache: invalidates stale $_git_stale_marker $_git_stale_mode marker" \
        "dotfiles-status" "$result"
      _assert_eq "git launcher nested cache: removes stale $_git_stale_marker $_git_stale_mode entry" \
        "" "$(cat "$_git_stale_cache/dotfiles/git-nested-worktree-roots")"
    done
  done
  : >"$_git_nested_probe_log"

  result=$(
    cd "$_git_nested_probe_subdir" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_root" \
        XDG_CACHE_HOME="$_git_nested_probe_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" config --show-scope --get-regexp '^(remote|user|submodule)\.'
  )
  _assert_eq "git launcher SCM config probe: reaches real git" \
    "real-git-config" "$result"
  _assert_not_contains "git launcher SCM config probe: skips Sapling probe" \
    "sl:root --config ui.color=never" "$(cat "$_git_nested_probe_log" 2>/dev/null || true)"

  _git_no_marker_cache=$(_tmpdir)
  _git_no_marker_root="$TEST_HOME/git/no-marker"
  _git_no_marker_leaf="$_git_no_marker_root/project/src"
  mkdir -p "$_git_no_marker_leaf"
  : >"$_git_nested_probe_log"
  result=$(
    cd "$_git_no_marker_leaf" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_no_marker_root" \
        XDG_CACHE_HOME="$_git_no_marker_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested probe: no marker falls back to dotfiles" \
    "dotfiles-status" "$result"
  _assert_not_contains "git launcher nested probe: no marker skips Sapling" \
    "sl:root --config ui.color=never" "$(cat "$_git_nested_probe_log")"

  _git_hg_probe_cache=$(_tmpdir)
  _git_hg_probe_root="$TEST_HOME/git/hg-worktree"
  _git_hg_probe_leaf="$_git_hg_probe_root/project/src"
  mkdir -p "$_git_hg_probe_root/.hg" "$_git_hg_probe_leaf"
  : >"$_git_nested_probe_log"
  result=$(
    cd "$_git_hg_probe_leaf" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_hg_probe_root" \
        XDG_CACHE_HOME="$_git_hg_probe_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested probe: hg marker reaches real git" \
    "real-git-status" "$result"
  _assert_contains "git launcher nested probe: hg marker keeps Sapling authority" \
    "sl:root --config ui.color=never" "$(cat "$_git_nested_probe_log")"

  : >"$_git_nested_probe_log"
  result=$(
    cd "$_git_nested_probe_subdir" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_root" \
        XDG_CACHE_HOME="$_git_nested_probe_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_root" \
        XDG_CACHE_HOME="$_git_nested_probe_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status &&
      rm -rf "$_git_nested_probe_root/.sl" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_root" \
        XDG_CACHE_HOME="$_git_nested_probe_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested repo cache: invalidates stale Sapling root" \
    "real-git-status"$'\n'"real-git-status"$'\n'"dotfiles-status" "$result"
  _nested_sl_count=$(grep -c 'sl:root --config ui.color=never' "$_git_nested_probe_log" 2>/dev/null || true)
  _assert_eq "git launcher nested repo cache: removed marker skips Sapling reprobe" \
    "1" "$_nested_sl_count"

  _git_nested_probe_semantic_cache=$(_tmpdir)
  _git_nested_probe_semantic_log="$(_tmpdir)/git-nested-semantic.log"
  _git_nested_probe_outer="$TEST_HOME/git/stale-outer-worktree"
  _git_nested_probe_inner="$_git_nested_probe_outer/project"
  _git_nested_probe_leaf="$_git_nested_probe_inner/src"
  mkdir -p "$_git_nested_probe_outer/.sl" "$_git_nested_probe_leaf"
  result=$(
    cd "$_git_nested_probe_leaf" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_semantic_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_outer" \
        XDG_CACHE_HOME="$_git_nested_probe_semantic_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status &&
      mkdir -p "$_git_nested_probe_inner/.sl" &&
      GIT_NESTED_PROBE_LOG="$_git_nested_probe_semantic_log" \
        GIT_NESTED_PROBE_HOME="$TEST_HOME" \
        GIT_NESTED_PROBE_ROOT="$_git_nested_probe_inner" \
        XDG_CACHE_HOME="$_git_nested_probe_semantic_cache" \
        PATH="$BIN_DIR:$_git_nested_probe_bin:/usr/bin:/bin" \
        "$BIN_DIR/git" status
  )
  _assert_eq "git launcher nested repo cache: prefers nearer marker over stale broad root" \
    "real-git-status"$'\n'"real-git-status" "$result"
  _nested_semantic_sl_count=$(grep -c 'sl:root --config ui.color=never' "$_git_nested_probe_semantic_log" 2>/dev/null || true)
  _assert_eq "git launcher nested repo cache: reprobes when nearer marker appears" \
    "2" "$_nested_semantic_sl_count"

  _git_cross_wrapper_bin=$(_tmpdir)
  _git_cross_real_bin=$(_tmpdir)
  _git_cross_cache=$(_tmpdir)
  cp "$BIN_DIR/git" "$_git_cross_wrapper_bin/git"
  chmod +x "$_git_cross_wrapper_bin/git"
  cat >"$_git_cross_real_bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'real-git:%s\n' "$*"
EOF
  chmod +x "$_git_cross_real_bin/git"
  _git_cross_timeout=""
  if command -v timeout >/dev/null 2>&1; then
    _git_cross_timeout=$(command -v timeout)
  elif command -v gtimeout >/dev/null 2>&1; then
    _git_cross_timeout=$(command -v gtimeout)
  fi
  if [[ -n "$_git_cross_timeout" ]]; then
    result=$(
      cd "$TEST_HOME" &&
        XDG_CACHE_HOME="$_git_cross_cache" \
          PATH="$BIN_DIR:$_git_cross_wrapper_bin:$_git_cross_real_bin:/usr/bin:/bin" \
          "$_git_cross_timeout" 3s "$BIN_DIR/git" --version 2>&1
    )
    _assert_eq "git launcher cross-account path: skips other launcher copies" \
      "real-git:--version" "$result"
  else
    _pass "git launcher cross-account path: timeout unavailable, skipped"
  fi

  mkdir -p "$TEST_HOME/.config/git-launcher"
  echo "old launcher" >"$TEST_HOME/.config/git-launcher/file"
  $GIT add .config/git-launcher/file
  $GIT commit -m "add git launcher scope file" >/dev/null 2>&1
  echo "new launcher" >"$TEST_HOME/.config/git-launcher/file"
  result=$(cd "$TEST_HOME/.config/git-launcher" && "$BIN_DIR/git" diff -- file 2>&1)
  _assert_contains "git launcher subdir: routes HOME descendants to bare dotfiles" \
    "+new launcher" "$result"
  $GIT checkout -- .config/git-launcher/file

  GIT_LAUNCHER_NORMAL="$TEST_HOME/git/git-launcher-project"
  mkdir -p "$GIT_LAUNCHER_NORMAL"
  GIT_LAUNCHER_NORMAL_PHYSICAL=$(cd "$GIT_LAUNCHER_NORMAL" && pwd -P)
  git -C "$GIT_LAUNCHER_NORMAL" init -q
  _git_set_test_identity git -C "$GIT_LAUNCHER_NORMAL"
  result=$(cd "$GIT_LAUNCHER_NORMAL" && "$BIN_DIR/git" rev-parse --show-toplevel 2>&1)
  _assert_eq "git launcher normal repo: uses nested repo" \
    "$GIT_LAUNCHER_NORMAL_PHYSICAL" "$result"

  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" -C "$GIT_LAUNCHER_NORMAL" rev-parse --show-toplevel 2>&1)
  _assert_eq "git launcher -C normal repo: uses target repo" \
    "$GIT_LAUNCHER_NORMAL_PHYSICAL" "$result"

  result=$(
    cd "$TEST_HOME/.config/git-launcher" &&
      GIT_DIR="$GIT_LAUNCHER_NORMAL/.git" GIT_WORK_TREE="$GIT_LAUNCHER_NORMAL" \
        "$BIN_DIR/git" rev-parse --show-toplevel 2>&1
  )
  _assert_eq "git launcher explicit env: uses provided repo" \
    "$GIT_LAUNCHER_NORMAL_PHYSICAL" "$result"

  GIT_LAUNCHER_ORIGIN=$(_tmpdir)
  git init --bare "$GIT_LAUNCHER_ORIGIN" >/dev/null 2>&1
  result=$(cd "$TEST_HOME" && "$BIN_DIR/git" clone "$GIT_LAUNCHER_ORIGIN" git-launcher-clone 2>&1 || true)
  _assert_contains "git launcher clone: repo-creating commands use real git" \
    "warning: You appear to have cloned an empty repository" "$result"
  _assert_eq "git launcher clone: created normal repo" \
    "true" "$([[ -d "$TEST_HOME/git-launcher-clone/.git" ]] && echo true || echo false)"

  # ---------------------------------------------------------------------------
  # Tests: git absorb-and-rebase launcher integration
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== git absorb-and-rebase launcher integration ==="

  result=$(PATH="$BIN_DIR:$PATH" git absorb-and-rebase -h 2>&1 || true)
  _assert_contains "git absorb-and-rebase: dependency command is installed" \
    "Usage: git absorb-and-rebase" "$result"
  # Git-tools owns absorb and autosquash semantics, including explicit bare
  # GIT_DIR/GIT_WORK_TREE layouts. Dotfiles only needs to prove that Git can
  # discover the installed dependency command through its launcher.

  # ---------------------------------------------------------------------------
  # Tests: nvim launcher
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== nvim launcher ==="

  # These launchers run only after dot has converged the managed dependency
  # set. Keep that fleet contract explicit here so test fixtures, old install
  # layouts, and duplicated provider inference cannot creep back into the
  # production entry points.
  _hm_launcher_source=$(cat "$BIN_DIR/hm")
  _nvim_launcher_source=$(cat "$BIN_DIR/nvim")
  _git_launcher_source=$(cat "$BIN_DIR/git")
  _assert_not_contains "launchers: production code is independent of dot-test" \
    "DOT_TEST_" "$_hm_launcher_source$_nvim_launcher_source$_git_launcher_source"
  _assert_not_contains "hm launcher: has no core-path override" \
    "HIVE_MEMORY_CORE" "$_hm_launcher_source"
  _assert_not_contains "hm launcher: has no legacy core fallback" \
    ".local/share/hive-memory/bin/hm-core" "$_hm_launcher_source"
  _assert_not_contains "hm launcher: does not infer Codex identity" \
    "CODEX_THREAD_ID" "$_hm_launcher_source"
  _assert_not_contains "hm launcher: does not infer Claude identity" \
    "CLAUDE_CODE_SESSION_ID" "$_hm_launcher_source"
  _assert_not_contains "nvim launcher: does not search for alternate editors" \
    "_dot_launcher_find_real" "$_nvim_launcher_source"
  _assert_not_contains "git launcher: has no source-only test mode" \
    "DOT_GIT_LAUNCHER_SOURCED" "$_git_launcher_source"

  NVIM_LAUNCHER_HOME=$(_tmpdir)
  NVIM_LAUNCHER_BIN=$(_mock_bin)
  NVIM_LAUNCHER_CWD="$NVIM_LAUNCHER_HOME/project"
  NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_HOME/termnav-nvim-launcher.sh"
  mkdir -p "$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin" "$NVIM_LAUNCHER_CWD"

  cat >"$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin/nvim" <<'MOCK'
#!/usr/bin/env bash
printf 'real:%s\n' "$*"
MOCK
  chmod +x "$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin/nvim"

  cat >"$NVIM_LAUNCHER_PROVIDER" <<'MOCK'
termnav_nvim_try_reuse() {
  printf 'provider:%s\n' "$*"
  [[ "${NVIM_TEST_REUSE:-0}" == 1 ]]
}
MOCK

  cat >"$NVIM_LAUNCHER_BIN/shdeps" <<'MOCK'
#!/usr/bin/env bash
[[ "${NVIM_TEST_PROVIDER_MISSING:-0}" != 1 ]] || exit 1
[[ "$*" == "dep-file cgraf78/termnav lib/termnav/nvim-open/launcher.sh" ]] || exit 2
printf '%s\n' "$NVIM_LAUNCHER_PROVIDER"
MOCK
  chmod +x "$NVIM_LAUNCHER_BIN/shdeps"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" || exit
    HOME="$NVIM_LAUNCHER_HOME" PATH="$NVIM_LAUNCHER_BIN:$PATH" \
      NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_PROVIDER" \
      NVIM_TEST_REUSE=1 \
      "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: delegates pane reuse to Termnav" \
    "provider:src/app.lua" "$result"

  NVIM_REUSE_HOME=$(_tmpdir)
  result=$(
    cd "$NVIM_LAUNCHER_CWD" || exit
    HOME="$NVIM_REUSE_HOME" PATH="$NVIM_LAUNCHER_BIN:/usr/bin:/bin" \
      NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_PROVIDER" \
      NVIM_TEST_REUSE=1 \
      "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: provider success does not require a fallback binary" \
    "provider:src/app.lua" "$result"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" || exit
    HOME="$NVIM_LAUNCHER_HOME" PATH="$NVIM_LAUNCHER_BIN:$PATH" \
      NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_PROVIDER" \
      "$BIN_DIR/nvim" src/app.lua
  )
  expected="$(printf 'provider:src/app.lua\nreal:src/app.lua')"
  _assert_eq "nvim launcher: provider refusal falls back to real nvim" "$expected" "$result"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" || exit
    HOME="$NVIM_LAUNCHER_HOME" PATH="$NVIM_LAUNCHER_BIN:$PATH" \
      NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_PROVIDER" \
      "$BIN_DIR/nvim" --headless src/app.lua
  )
  _assert_eq "nvim launcher: forwards the complete argv to Termnav and real nvim" \
    "$(printf 'provider:--headless src/app.lua\nreal:--headless src/app.lua')" "$result"

  _nvim_missing_rc=0
  _nvim_missing_output=$(
    cd "$NVIM_LAUNCHER_CWD" || exit
    HOME="$NVIM_LAUNCHER_HOME" PATH="$NVIM_LAUNCHER_BIN:$PATH" \
      NVIM_LAUNCHER_PROVIDER="$NVIM_LAUNCHER_PROVIDER" \
      NVIM_TEST_PROVIDER_MISSING=1 \
      "$BIN_DIR/nvim" src/app.lua 2>&1
  ) || _nvim_missing_rc=$?
  _assert_eq "nvim launcher: missing Termnav is a broken installation" \
    "127" "$_nvim_missing_rc"
  _assert_contains "nvim launcher: missing Termnav suggests repair" \
    "run dot update" "$_nvim_missing_output"

  # ---------------------------------------------------------------------------
  # Tests: Hive Memory launcher
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== hm launcher ==="

  HM_LAUNCHER_HOME=$(_tmpdir)
  HM_LAUNCHER_REAL="$HM_LAUNCHER_HOME/.local/share/cgraf78/hive-memory/hm"
  mkdir -p "${HM_LAUNCHER_REAL%/*}"
  cat >"$HM_LAUNCHER_REAL" <<'MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == env-probe ]]; then
  printf 'agent=%s\n' "${HIVE_MEMORY_AGENT_ID:-}"
  printf 'session=%s\n' "${HIVE_MEMORY_SESSION_ID:-}"
  printf 'project=%s\n' "${HIVE_MEMORY_PROJECT:-}"
else
  printf 'real:%s\n' "$*"
fi
MOCK
  chmod +x "$HM_LAUNCHER_REAL"

  # The launcher consumes AgentGuard as a required provider. Keep the fixture
  # opaque so this suite tests only dotfiles' Hive mapping; AgentGuard's own
  # suite owns runtime-specific detection and session precedence.
  HM_AGENTGUARD_API=$(_tmpdir)/agentguard.sh
  cat >"$HM_AGENTGUARD_API" <<'MOCK'
agentguard_agent_name() {
  printf '%s\n' "${HM_TEST_AGENT:-unknown}"
}

agentguard_session_id() {
  if [[ -n "${HM_TEST_SESSION:-}" ]]; then
    printf '%s\n' "$HM_TEST_SESSION"
  elif [[ -n "${1:-}" ]]; then
    printf 'fallback:%s\n' "$1"
  else
    return 1
  fi
}
MOCK
  HM_AGENTGUARD_BIN=$(_mock_bin)
  cat >"$HM_AGENTGUARD_BIN/shdeps" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == dep-file && "$2" == cgraf78/agentguard && \
  "$3" == lib/agentguard/agentguard.sh ]]; then
  printf '%s\n' "$HM_AGENTGUARD_API"
  exit 0
fi
exit 1
MOCK
  chmod +x "$HM_AGENTGUARD_BIN/shdeps"

  # Clear ambient runtime identity for every probe so the assertions describe
  # only the environment each case supplies, regardless of which agent runs
  # dot-test. Later env operands intentionally override this baseline.
  HM_LAUNCHER_SCRUB_ENV=(
    GEMINI_PROJECT_DIR=
    HM_AGENTGUARD_API="$HM_AGENTGUARD_API"
    HM_TEST_AGENT=unknown
    HM_TEST_SESSION=
    HIVE_MEMORY_AGENT_ID=
    HIVE_MEMORY_PROJECT_INFER=
    HIVE_MEMORY_SESSION_ID=
    HIVE_MEMORY_PROJECT=
    PATH="$HM_AGENTGUARD_BIN:$PATH"
  )

  result=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" HOME="$HM_LAUNCHER_HOME" \
    "$BIN_DIR/hm" recall --limit 2)
  _assert_eq "hm launcher: delegates to stable Shdeps archive path" \
    "real:recall --limit 2" "$result"

  _hm_plain_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" "$BIN_DIR/hm" env-probe)
  _assert_eq "hm launcher: leaves human agent unset" \
    "agent=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^agent=')"
  _assert_eq "hm launcher: leaves human session unset" \
    "session=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^session=')"
  _assert_eq "hm launcher: leaves human project unset" \
    "project=" "$(printf '%s\n' "$_hm_plain_probe" | grep '^project=')"

  _hm_provider_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" "$BIN_DIR/hm" env-probe)
  _assert_contains "hm launcher: consumes AgentGuard agent identity" \
    "agent=provider-agent" "$_hm_provider_probe"
  _assert_contains "hm launcher: consumes AgentGuard session identity" \
    "session=provider-session" "$_hm_provider_probe"
  _assert_contains "hm launcher: maps agent calls to the current project" \
    "project=$(pwd)" "$_hm_provider_probe"

  _hm_gemini_project="$HM_LAUNCHER_HOME/gemini-project"
  _hm_gemini_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT=gemini \
    HM_TEST_SESSION="gemini-session" \
    GEMINI_PROJECT_DIR="$_hm_gemini_project" "$BIN_DIR/hm" env-probe)
  _assert_contains "hm launcher: uses Gemini's precise project hint" \
    "project=$_hm_gemini_project" "$_hm_gemini_probe"

  _hm_explicit_only_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HIVE_MEMORY_AGENT_ID="custom-agent" \
    "$BIN_DIR/hm" env-probe)
  _assert_contains "hm launcher: preserves an explicit Hive agent" \
    "agent=custom-agent" "$_hm_explicit_only_probe"
  _assert_contains "hm launcher: gives AgentGuard the Hive fallback namespace" \
    "session=fallback:custom-agent" "$_hm_explicit_only_probe"

  _hm_explicit_context_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" \
    HIVE_MEMORY_SESSION_ID="hive-session" \
    HIVE_MEMORY_PROJECT="/explicit/project" \
    "$BIN_DIR/hm" env-probe)
  _assert_contains "hm launcher: preserves explicit Hive session" \
    "session=hive-session" "$_hm_explicit_context_probe"
  _assert_contains "hm launcher: preserves explicit Hive project" \
    "project=/explicit/project" "$_hm_explicit_context_probe"

  _hm_no_project_probe=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" HM_TEST_AGENT="provider-agent" \
    HM_TEST_SESSION="provider-session" HIVE_MEMORY_PROJECT_INFER=0 \
    "$BIN_DIR/hm" env-probe)
  _assert_eq "hm launcher: keeps project unset when inference is disabled" \
    "project=" "$(printf '%s\n' "$_hm_no_project_probe" | grep '^project=')"

  _hm_missing_output=""
  _hm_missing_rc=0
  mv "$HM_LAUNCHER_REAL" "$HM_LAUNCHER_REAL.saved"
  _hm_missing_output=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" "$BIN_DIR/hm" --version 2>&1) || _hm_missing_rc=$?
  mv "$HM_LAUNCHER_REAL.saved" "$HM_LAUNCHER_REAL"
  _assert_eq "hm launcher: missing core exits like a missing command" \
    "127" "$_hm_missing_rc"
  _assert_contains "hm launcher: missing core names the rejected path" \
    "$HM_LAUNCHER_REAL" "$_hm_missing_output"

  HM_MISSING_PROVIDER_BIN=$(_mock_bin)
  cat >"$HM_MISSING_PROVIDER_BIN/shdeps" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
  chmod +x "$HM_MISSING_PROVIDER_BIN/shdeps"
  _hm_provider_missing_rc=0
  _hm_provider_missing_output=$(env "${HM_LAUNCHER_SCRUB_ENV[@]}" \
    HOME="$HM_LAUNCHER_HOME" PATH="$HM_MISSING_PROVIDER_BIN:$PATH" \
    "$BIN_DIR/hm" --version 2>&1) || _hm_provider_missing_rc=$?
  _assert_eq "hm launcher: missing AgentGuard is a broken installation" \
    "127" "$_hm_provider_missing_rc"
  _assert_contains "hm launcher: missing AgentGuard suggests repair" \
    "run dot update" "$_hm_provider_missing_output"

  # ---------------------------------------------------------------------------
  # Tests: Sley consumer policy
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Sley consumer policy ==="

  # Sley owns help, repository discovery, status, and change scoping. Dotfiles
  # owns only the local decision to opt its unusual bare-HOME repository into
  # Sley's generic fallback API, so exercise that environment boundary without
  # carrying a second behavioral suite for the provider.
  SLEY_ENV_FILE="$REAL_HOME/.config/shell/env.d/60-tools.sh"
  # Keep child-shell probes in variables so their parameter expansion remains
  # visibly deferred until after env has established each synthetic HOME.
  # shellcheck disable=SC2016
  SLEY_ENV_VALUES_PROBE='. "$1"; printf "%s\n%s\n" "${SLEY_BARE_REPO_GIT_DIR-}" "${SLEY_BARE_REPO_WORK_TREE-}"'
  # shellcheck disable=SC2016
  SLEY_ENV_PRESENCE_PROBE='. "$1"; printf "%s:%s\n" "${SLEY_BARE_REPO_GIT_DIR+set}" "${SLEY_BARE_REPO_WORK_TREE+set}"'
  SLEY_ENV_HOME=$(_tmpdir)
  mkdir -p "$SLEY_ENV_HOME/.dotfiles"
  result=$(
    env -i HOME="$SLEY_ENV_HOME" PATH=/usr/bin:/bin \
      /bin/bash -c "$SLEY_ENV_VALUES_PROBE" \
      _ "$SLEY_ENV_FILE"
  )
  _assert_eq "sley policy: bare dotfiles home configures the provider API" \
    "$SLEY_ENV_HOME/.dotfiles
$SLEY_ENV_HOME" "$result"

  result=$(
    env -i HOME="$SLEY_ENV_HOME" PATH=/usr/bin:/bin \
      SLEY_BARE_REPO_GIT_DIR=/custom/git \
      SLEY_BARE_REPO_WORK_TREE=/custom/work \
      /bin/bash -c "$SLEY_ENV_VALUES_PROBE" \
      _ "$SLEY_ENV_FILE"
  )
  _assert_eq "sley policy: explicit provider configuration wins" \
    $'/custom/git\n/custom/work' "$result"

  SLEY_PLAIN_HOME=$(_tmpdir)
  result=$(
    env -i HOME="$SLEY_PLAIN_HOME" PATH=/usr/bin:/bin \
      /bin/bash -c "$SLEY_ENV_PRESENCE_PROBE" \
      _ "$SLEY_ENV_FILE"
  )
  _assert_eq "sley policy: ordinary homes do not enable bare-repo fallback" \
    ":" "$result"

  result=$("$BIN_DIR/dot" sley status 2>&1 || true)
  _assert_contains "sley removed: dot reports unknown command" \
    "unknown command: sley" "$result"
  _assert_contains "sley removed: dot suggests raw git fallback" \
    "git sley" "$result"
  _assert_not_contains "sley removed: does not run sley status" \
    "repo: git" "$result"

  echo ""
  echo "=== git launcher argument routing ==="

  # Exercise parsing through the public command. `clone` must bypass the bare
  # HOME repo; if a global option accidentally swallows it, the fake real Git
  # observes the injected dotfiles environment and makes the regression visible
  # without a source-only mode in production.
  GIT_PARSE_BIN=$(_mock_bin)
  GIT_PARSE_CACHE=$(_tmpdir)
  cat >"$GIT_PARSE_BIN/git" <<'MOCK'
#!/usr/bin/env bash
if [[ -n "${GIT_DIR:-}" || -n "${GIT_WORK_TREE:-}" ]]; then
  printf 'dotfiles\n'
else
  printf 'real\n'
fi
MOCK
  chmod +x "$GIT_PARSE_BIN/git"
  _git_parse_route() {
    (
      cd "$TEST_HOME" || exit
      XDG_CACHE_HOME="$GIT_PARSE_CACHE" \
        PATH="$BIN_DIR:$GIT_PARSE_BIN:/usr/bin:/bin" \
        "$BIN_DIR/git" "$@"
    )
  }
  result=$(_git_parse_route --exec-path clone)
  _assert_eq "git parse: bare --exec-path keeps subcommand" "real" "$result"
  result=$(_git_parse_route --exec-path=/custom/path clone)
  _assert_eq "git parse: --exec-path=VALUE keeps subcommand" "real" "$result"
  result=$(_git_parse_route -c user.name=foo clone)
  _assert_eq "git parse: -c consumes its value, keeps subcommand" "real" "$result"
  result=$(_git_parse_route --namespace ns clone)
  _assert_eq "git parse: --namespace consumes its value, keeps subcommand" \
    "real" "$result"
}
