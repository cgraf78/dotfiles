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
  mkdir -p "$_git_exact_root_base" "$_git_exact_root_cache/dot"
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
      printf 'sentinel\n' >"$_git_exact_root_cache/dot/git-nested-worktree-roots"
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
        "sentinel" "$(cat "$_git_exact_root_cache/dot/git-nested-worktree-roots")"
    done
  done

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
      mkdir -p "$_git_stale_cache/dot" "$_git_stale_leaf"
      case "$_git_stale_mode" in
        file)
          printf 'malformed marker\n' >"$_git_stale_root/.$_git_stale_marker"
          ;;
        dangling)
          ln -s missing-marker "$_git_stale_root/.$_git_stale_marker"
          ;;
      esac
      printf 'sl\t%s\n' "$_git_stale_root" \
        >"$_git_stale_cache/dot/git-nested-worktree-roots"

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
        "" "$(cat "$_git_stale_cache/dot/git-nested-worktree-roots")"
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
  _assert_eq "git launcher nested repo cache: Sapling probe reruns after invalidation" \
    "2" "$_nested_sl_count"

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

  if PATH="$BIN_DIR:$PATH" git absorb --version >/dev/null 2>&1; then
    ABSORB_DOT_HOME=$(_tmpdir)
    mkdir -p "$ABSORB_DOT_HOME/.config/test"
    git init --bare --initial-branch=main "$ABSORB_DOT_HOME/.dotfiles" >/dev/null
    ABSORB_DOT_GIT=(git --git-dir="$ABSORB_DOT_HOME/.dotfiles" --work-tree="$ABSORB_DOT_HOME")
    _git_set_test_identity "${ABSORB_DOT_GIT[@]}"
    "${ABSORB_DOT_GIT[@]}" config core.hooksPath /dev/null
    printf 'base\n' >"$ABSORB_DOT_HOME/.bashrc"
    "${ABSORB_DOT_GIT[@]}" add .bashrc
    "${ABSORB_DOT_GIT[@]}" commit -m "base" >/dev/null
    ABSORB_DOT_BASE=$("${ABSORB_DOT_GIT[@]}" rev-parse HEAD)
    printf 'alpha\n' >"$ABSORB_DOT_HOME/.config/test/file"
    "${ABSORB_DOT_GIT[@]}" add .config/test/file
    "${ABSORB_DOT_GIT[@]}" commit -m "add dot file" >/dev/null
    printf 'beta\n' >"$ABSORB_DOT_HOME/.config/test/other"
    "${ABSORB_DOT_GIT[@]}" add .config/test/other
    "${ABSORB_DOT_GIT[@]}" commit -m "add other dot file" >/dev/null
    printf 'alpha fixed\n' >"$ABSORB_DOT_HOME/.config/test/file"
    "${ABSORB_DOT_GIT[@]}" add .config/test/file
    result=$(
      cd "$ABSORB_DOT_HOME/.config/test" &&
        BASH_ENV='' HOME="$ABSORB_DOT_HOME" PATH="$BIN_DIR:$PATH" GIT_SEQUENCE_EDITOR=false \
          "$BIN_DIR/git" absorb-and-rebase --base "$ABSORB_DOT_BASE" 2>&1
    )
    _assert_contains "git absorb-and-rebase: works through dotfiles git launcher" \
      "git absorb-and-rebase: base $ABSORB_DOT_BASE" "$result"
    result=$("${ABSORB_DOT_GIT[@]}" log --format=%s --reverse "$ABSORB_DOT_BASE"..HEAD)
    expected="$(printf 'add dot file\nadd other dot file')"
    _assert_eq "git absorb-and-rebase: autosquashes bare dotfiles fixups" "$expected" "$result"
    result=$("${ABSORB_DOT_GIT[@]}" show HEAD~1:.config/test/file)
    _assert_eq "git absorb-and-rebase: folds bare dotfiles staged fix" \
      "alpha fixed" "$result"
  else
    echo "  SKIP: git absorb-and-rebase launcher rewrite smoke (git-absorb missing)"
  fi

  # ---------------------------------------------------------------------------
  # Tests: nvim launcher
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== nvim launcher ==="

  NVIM_LAUNCHER_HOME=$(_tmpdir)
  NVIM_LAUNCHER_BIN=$(_mock_bin)
  NVIM_LAUNCHER_CWD="$NVIM_LAUNCHER_HOME/project"
  NVIM_LAUNCHER_XDG_CACHE="$NVIM_LAUNCHER_HOME/xdg-cache"
  NVIM_LAUNCHER_CACHE="$NVIM_LAUNCHER_XDG_CACHE/dot/nvim-real"
  NVIM_LAUNCHER_PS_LOG="$NVIM_LAUNCHER_HOME/ps.log"
  mkdir -p "$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin" "$NVIM_LAUNCHER_CWD"

  cat >"$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin/nvim" <<'MOCK'
#!/usr/bin/env bash
printf 'real:%s\n' "$*"
MOCK
  chmod +x "$NVIM_LAUNCHER_HOME/.local/share/neovim/neovim/bin/nvim"

  cat >"$NVIM_LAUNCHER_BIN/nvim-tmux-open" <<'MOCK'
#!/usr/bin/env bash
printf 'open:%s\n' "$*"
exit "${NVIM_TMUX_OPEN_RC:-0}"
MOCK
  chmod +x "$NVIM_LAUNCHER_BIN/nvim-tmux-open"

  cat >"$NVIM_LAUNCHER_BIN/ps" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${NVIM_LAUNCHER_PS_LOG:-}" ]] || printf '%s\n' "$*" >>"$NVIM_LAUNCHER_PS_LOG"
case "$*" in
  "-ww -o comm= -o args= -p "*)
    printf '%s %s\n' \
      "${NVIM_LAUNCHER_PARENT_COMMAND:-zsh}" \
      "${NVIM_LAUNCHER_PARENT_ARGS:-${NVIM_LAUNCHER_PARENT_COMMAND:--zsh}}"
    ;;
  "-o comm= -p "*)
    printf '%s\n' "${NVIM_LAUNCHER_PARENT_COMMAND:-zsh}"
    ;;
  "-o args= -p "*)
    printf '%s\n' "${NVIM_LAUNCHER_PARENT_ARGS:-${NVIM_LAUNCHER_PARENT_COMMAND:--zsh}}"
    ;;
  *)
    exit 1
    ;;
esac
MOCK
  chmod +x "$NVIM_LAUNCHER_BIN/ps"

  : >"$NVIM_LAUNCHER_PS_LOG"
  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" TMUX="/tmp/tmux.sock,1,0" \
        NVIM_LAUNCHER_ALLOW_NONTTY=1 NVIM_LAUNCHER_PS_LOG="$NVIM_LAUNCHER_PS_LOG" \
        "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: tmux file open reuses existing pane" \
    "open:cli src/app.lua $NVIM_LAUNCHER_CWD" "$result"
  _assert_file_missing "nvim launcher: preferred binary does not create fallback cache" \
    "$NVIM_LAUNCHER_CACHE"
  _assert_eq "nvim launcher: eligible file open inspects its parent once" \
    "1" "$(wc -l <"$NVIM_LAUNCHER_PS_LOG" | tr -d ' ')"

  mkdir -p "${NVIM_LAUNCHER_CACHE%/*}"
  printf 'fallback-cache-sentinel\n' >"$NVIM_LAUNCHER_CACHE"

  : >"$NVIM_LAUNCHER_PS_LOG"
  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" TMUX="/tmp/tmux.sock,1,0" \
        NVIM_LAUNCHER_ALLOW_NONTTY=1 NVIM_TMUX_OPEN_RC=1 "$BIN_DIR/nvim" src/app.lua
  )
  expected="$(printf 'open:cli src/app.lua %s\nreal:src/app.lua' "$NVIM_LAUNCHER_CWD")"
  _assert_eq "nvim launcher: no reusable pane falls back to real nvim" "$expected" "$result"
  _assert_file_content "nvim launcher: preferred binary preserves fallback cache" \
    "fallback-cache-sentinel" "$NVIM_LAUNCHER_CACHE"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" TMUX="/tmp/tmux.sock,1,0" \
        NVIM_LAUNCHER_ALLOW_NONTTY=1 NVIM_LAUNCHER_PS_LOG="$NVIM_LAUNCHER_PS_LOG" \
        "$BIN_DIR/nvim" --headless src/app.lua
  )
  _assert_eq "nvim launcher: flags bypass pane reuse" "real:--headless src/app.lua" "$result"
  _assert_file_content "nvim launcher: ineligible arguments skip parent inspection" \
    "" "$NVIM_LAUNCHER_PS_LOG"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" TMUX="/tmp/tmux.sock,1,0" \
        NVIM_LAUNCHER_ALLOW_NONTTY=1 NVIM_LAUNCHER_PARENT_COMMAND=git "$BIN_DIR/nvim" .git/COMMIT_EDITMSG
  )
  _assert_eq "nvim launcher: editor-style parent bypasses pane reuse" \
    "real:.git/COMMIT_EDITMSG" "$result"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" TMUX="/tmp/tmux.sock,1,0" \
        NVIM_LAUNCHER_ALLOW_NONTTY=1 NVIM_LAUNCHER_PARENT_COMMAND=bash \
        NVIM_LAUNCHER_PARENT_ARGS="bash ./script-that-runs-nvim" "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: shell script parent bypasses pane reuse" \
    "real:src/app.lua" "$result"

  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_LAUNCHER_HOME" XDG_CACHE_HOME="$NVIM_LAUNCHER_XDG_CACHE" \
        PATH="$NVIM_LAUNCHER_BIN:$PATH" \
        "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: outside tmux launches real nvim" "real:src/app.lua" "$result"

  NVIM_PATH_HOME=$(_tmpdir)
  NVIM_PATH_BIN=$(_mock_bin)
  NVIM_PATH_XDG_CACHE="$NVIM_PATH_HOME/xdg-cache"
  NVIM_PATH_CACHE="$NVIM_PATH_XDG_CACHE/dot/nvim-real"
  cat >"$NVIM_PATH_BIN/nvim" <<'MOCK'
#!/usr/bin/env bash
printf 'path-real:%s\n' "$*"
MOCK
  chmod +x "$NVIM_PATH_BIN/nvim"
  result=$(
    cd "$NVIM_LAUNCHER_CWD" &&
      HOME="$NVIM_PATH_HOME" XDG_CACHE_HOME="$NVIM_PATH_XDG_CACHE" \
        PATH="$NVIM_PATH_BIN:$BIN_DIR:/usr/bin:/bin" \
        "$BIN_DIR/nvim" src/app.lua
  )
  _assert_eq "nvim launcher: path fallback skips wrapper" "path-real:src/app.lua" "$result"
  expected="$(printf '%s\n%s' \
    "$NVIM_PATH_BIN/nvim" "$NVIM_PATH_BIN:$BIN_DIR:/usr/bin:/bin")"
  _assert_file_content "nvim launcher: path fallback caches resolved binary" \
    "$expected" "$NVIM_PATH_CACHE"

  NVIM_CROSS_HOME=$(_tmpdir)
  NVIM_CROSS_WRAPPER_BIN=$(_tmpdir)
  NVIM_CROSS_REAL_BIN=$(_tmpdir)
  NVIM_CROSS_XDG_CACHE="$NVIM_CROSS_HOME/xdg-cache"
  cp "$BIN_DIR/nvim" "$NVIM_CROSS_WRAPPER_BIN/nvim"
  chmod +x "$NVIM_CROSS_WRAPPER_BIN/nvim"
  cat >"$NVIM_CROSS_REAL_BIN/nvim" <<'MOCK'
#!/usr/bin/env bash
printf 'cross-real:%s\n' "$*"
MOCK
  chmod +x "$NVIM_CROSS_REAL_BIN/nvim"
  _nvim_cross_timeout=""
  if command -v timeout >/dev/null 2>&1; then
    _nvim_cross_timeout=$(command -v timeout)
  elif command -v gtimeout >/dev/null 2>&1; then
    _nvim_cross_timeout=$(command -v gtimeout)
  fi
  if [[ -n "$_nvim_cross_timeout" ]]; then
    result=$(
      cd "$NVIM_LAUNCHER_CWD" &&
        HOME="$NVIM_CROSS_HOME" XDG_CACHE_HOME="$NVIM_CROSS_XDG_CACHE" \
          PATH="$BIN_DIR:$NVIM_CROSS_WRAPPER_BIN:$NVIM_CROSS_REAL_BIN:/usr/bin:/bin" \
          "$_nvim_cross_timeout" 3s "$BIN_DIR/nvim" --headless src/app.lua
    )
    _assert_eq "nvim launcher cross-account path: skips other launcher copies" \
      "cross-real:--headless src/app.lua" "$result"
  else
    _pass "nvim launcher cross-account path: timeout unavailable, skipped"
  fi

  # ---------------------------------------------------------------------------
  # Tests: sley launcher
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== sley launcher ==="

  SLEY_BIN="${DOT_TEST_HOST_HOME:-$HOME}/.local/bin/sley"

  result=$(cd "$TEST_HOME" && "$SLEY_BIN" 2>&1)
  _assert_exit "sley launcher help: no args exits 0" 0 "$?"
  _assert_contains "sley launcher help: no args prints usage" \
    "Usage: sley COMMAND" "$result"

  result=$(cd "$TEST_HOME" && "$SLEY_BIN" -h 2>&1)
  _assert_exit "sley launcher help: -h exits 0" 0 "$?"
  _assert_contains "sley launcher help: -h prints usage" \
    "Usage: sley COMMAND" "$result"

  result=$(cd "$TEST_HOME" && "$SLEY_BIN" --help 2>&1)
  _assert_exit "sley launcher help: --help exits 0" 0 "$?"
  _assert_contains "sley launcher help: --help prints usage" \
    "Usage: sley COMMAND" "$result"

  result=$(
    cd "$TEST_HOME" &&
      SLEY_BARE_REPO_GIT_DIR="$DOTFILES" SLEY_BARE_REPO_WORK_TREE="$TEST_HOME" \
        "$SLEY_BIN" status 2>&1 || true
  )
  _assert_not_contains "sley launcher base: detects git repo" \
    "unsupported repo" "$result"
  _assert_contains "sley launcher base: emits status header" "repo: git" "$result"
  _assert_contains "sley launcher base: root is the work tree (\$HOME)" \
    "root: $TEST_HOME_PHYSICAL" "$result"

  echo "untracked" >"$TEST_HOME/.launcher-untracked"
  result=$(
    cd "$TEST_HOME" &&
      SLEY_BARE_REPO_GIT_DIR="$DOTFILES" SLEY_BARE_REPO_WORK_TREE="$TEST_HOME" \
        "$SLEY_BIN" status --json 2>&1 || true
  )
  _assert_contains "sley launcher base: untracked walk skipped" \
    '"untracked":0' "$result"
  _assert_contains "sley launcher base: clean repo reports not dirty" \
    '"dirty":false' "$result"
  rm -f "$TEST_HOME/.launcher-untracked"

  mkdir -p "$TEST_HOME/.config/nvim" "$TEST_HOME/.config/zsh"
  echo "old nvim" >"$TEST_HOME/.config/nvim/init.lua"
  echo "old zsh" >"$TEST_HOME/.config/zsh/.zshrc"
  $GIT add .config/nvim/init.lua .config/zsh/.zshrc
  $GIT commit -m "add launcher scope files" >/dev/null 2>&1
  echo "new nvim" >"$TEST_HOME/.config/nvim/init.lua"
  echo "new zsh" >"$TEST_HOME/.config/zsh/.zshrc"
  result=$(
    cd "$TEST_HOME/.config/nvim" &&
      SLEY_BARE_REPO_GIT_DIR="$DOTFILES" SLEY_BARE_REPO_WORK_TREE="$TEST_HOME" \
        "$SLEY_BIN" changes 2>&1 || true
  )
  _assert_contains "sley launcher subdir: auto path includes cwd changes" \
    ".config/nvim/init.lua" "$result"
  _assert_not_contains "sley launcher subdir: auto path excludes sibling changes" \
    ".config/zsh/.zshrc" "$result"
  $GIT checkout -- .config/nvim/init.lua .config/zsh/.zshrc

  NORMAL_HOME_REPO="$TEST_HOME/git/project"
  mkdir -p "$NORMAL_HOME_REPO"
  NORMAL_HOME_REPO_PHYSICAL=$(cd "$NORMAL_HOME_REPO" && pwd -P)
  git -C "$NORMAL_HOME_REPO" init -q
  _git_set_test_identity git -C "$NORMAL_HOME_REPO"
  result=$(cd "$NORMAL_HOME_REPO" && "$SLEY_BIN" status --json 2>&1 || true)
  _assert_contains "sley launcher normal repo under home: uses nested repo" \
    "\"root\":\"$NORMAL_HOME_REPO_PHYSICAL\"" "$result"

  result=$(
    cd "$TEST_HOME/.config/nvim" &&
      GIT_DIR="$NORMAL_HOME_REPO/.git" GIT_WORK_TREE="$NORMAL_HOME_REPO" \
        "$SLEY_BIN" status --json 2>&1 || true
  )
  _assert_contains "sley launcher explicit env: uses provided repo" \
    "\"root\":\"$NORMAL_HOME_REPO_PHYSICAL\"" "$result"

  result=$("$BIN_DIR/dot" sley status 2>&1 || true)
  _assert_contains "sley removed: dot reports unknown command" \
    "unknown command: sley" "$result"
  _assert_contains "sley removed: dot suggests raw git fallback" \
    "git sley" "$result"
  _assert_not_contains "sley removed: does not run sley status" \
    "repo: git" "$result"

  echo ""
  echo "=== git launcher argument parsing ==="

  # Source the launcher in a subshell (DOT_GIT_LAUNCHER_SOURCED skips the exec
  # flow and contains the launcher's `set -u`), run the parser, and echo the
  # resolved subcommand so assertions stay in the main shell where the pass/fail
  # counters live. Regression: bare `--exec-path` takes no value, so it must not
  # swallow the following subcommand.
  _git_parse_cmd() {
    # shellcheck disable=SC2034  # read by the sourced launcher to skip its exec flow.
    local DOT_GIT_LAUNCHER_SOURCED=1
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/bin/git"
    _dot_git_parse_invocation "$@"
    # shellcheck disable=SC2154  # _dot_git_command is set by _dot_git_parse_invocation.
    printf '%s' "$_dot_git_command"
  }
  parsed=$(_git_parse_cmd --exec-path status)
  _assert_eq "git parse: bare --exec-path keeps subcommand" "status" "$parsed"
  parsed=$(_git_parse_cmd --exec-path=/custom/path status)
  _assert_eq "git parse: --exec-path=VALUE keeps subcommand" "status" "$parsed"
  parsed=$(_git_parse_cmd -c user.name=foo status)
  _assert_eq "git parse: -c consumes its value, keeps subcommand" "status" "$parsed"
  parsed=$(_git_parse_cmd --namespace ns status)
  _assert_eq "git parse: --namespace consumes its value, keeps subcommand" \
    "status" "$parsed"
}
