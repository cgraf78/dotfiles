# shellcheck shell=bash
# launchers.sh - always-active Git launcher coverage.

dot_core_test_launchers() {
  # The standalone repository owns dot command routing. This retained suite
  # covers the base Git launcher; editor and development launchers moved with
  # their owning public overlays.
  echo "tag-test" >"$TEST_HOME/.testrc"
  $GIT add .testrc
  $GIT commit -m "tag test" >/dev/null 2>&1

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
  _git_launcher_source=$(cat "$BIN_DIR/git")
  _assert_not_contains "git launcher: production code is independent of dot test" \
    "DOT_TEST_" "$_git_launcher_source"
  _assert_not_contains "git launcher: has no source-only test mode" \
    "DOT_GIT_LAUNCHER_SOURCED" "$_git_launcher_source"

  echo ""
  echo "=== git launcher real-git resolution ==="

  # Resolution skips this launcher (even through a symlink) and any other
  # launcher copy, publishes the result, and republishes only when the
  # resolved binary changes: PATH strings that differ but resolve the same
  # Git must not rewrite the shared cache on every call.
  _git_res_root=$(_tmpdir)
  _git_res_cache=$_git_res_root/cache
  _git_res_file=$_git_res_cache/dotfiles/git-real
  mkdir -p "$_git_res_root/a" "$_git_res_root/b" "$_git_res_root/copy" \
    "$_git_res_root/link" "$_git_res_root/cwd"
  for _git_res_label in a b cwd; do
    printf '%s\n' '#!/usr/bin/env bash' "printf 'real-$_git_res_label\\n'" \
      >"$_git_res_root/$_git_res_label/git"
    chmod +x "$_git_res_root/$_git_res_label/git"
  done
  printf '%s\n' '#!/bin/sh' '# Dotfiles-aware launcher for Git.' 'exit 99' \
    >"$_git_res_root/copy/git"
  chmod +x "$_git_res_root/copy/git"
  ln -s "$BIN_DIR/git" "$_git_res_root/link/git"
  _git_res_run() {
    (cd "$TEST_HOME" && XDG_CACHE_HOME="$_git_res_cache" PATH="$1" \
      "$BIN_DIR/git" --version 2>&1)
  }

  _git_res_path1="$BIN_DIR:$_git_res_root/link:$_git_res_root/copy:$_git_res_root/a:$_git_res_root/b:/usr/bin:/bin"
  _assert_eq "git launcher resolution: skips launcher symlinks and copies" \
    "real-a" "$(_git_res_run "$_git_res_path1")"
  _assert_file_content "git launcher resolution: publishes the resolved Git" \
    "$(printf '%s\n%s' "$_git_res_root/a/git" "$_git_res_path1")" "$_git_res_file"

  _git_res_path2="$BIN_DIR:$_git_res_root/a:/usr/bin:/bin"
  _assert_eq "git launcher resolution: another PATH resolves the same Git" \
    "real-a" "$(_git_res_run "$_git_res_path2")"
  _assert_file_content "git launcher resolution: same Git leaves the cache alone" \
    "$(printf '%s\n%s' "$_git_res_root/a/git" "$_git_res_path1")" "$_git_res_file"

  _git_res_path3="$BIN_DIR:$_git_res_root/b:$_git_res_root/a:/usr/bin:/bin"
  _assert_eq "git launcher resolution: follows a PATH that changes the Git" \
    "real-b" "$(_git_res_run "$_git_res_path3")"
  _assert_file_content "git launcher resolution: republishes a changed Git" \
    "$(printf '%s\n%s' "$_git_res_root/b/git" "$_git_res_path3")" "$_git_res_file"

  printf '%s\n%s\n' "$_git_res_root/copy/git" "$_git_res_path3" >"$_git_res_file"
  _assert_eq "git launcher resolution: rejects a cached launcher copy" \
    "real-b" "$(_git_res_run "$_git_res_path3")"
  _assert_file_content "git launcher resolution: replaces a rejected cache entry" \
    "$(printf '%s\n%s' "$_git_res_root/b/git" "$_git_res_path3")" "$_git_res_file"

  # An empty PATH entry names the current directory, as in command lookup.
  _git_res_cwd_result=$(cd "$_git_res_root/cwd" &&
    XDG_CACHE_HOME="$_git_res_root/cwd-cache" PATH="$BIN_DIR::/usr/bin:/bin" \
      "$BIN_DIR/git" --version 2>&1)
  _assert_eq "git launcher resolution: empty PATH entry is the current directory" \
    "real-cwd" "$_git_res_cwd_result"

  # A literal leading `~` in a PATH entry expands like command lookup does.
  mkdir -p "$_git_res_root/home/bin"
  cp "$_git_res_root/b/git" "$_git_res_root/home/bin/git"
  # shellcheck disable=SC2147 # The literal tilde is the PATH entry under test.
  _git_res_tilde_result=$(cd "$TEST_HOME" && HOME="$_git_res_root/home" \
    XDG_CACHE_HOME="$_git_res_root/tilde-cache" \
    PATH="$BIN_DIR:~/bin:$_git_res_root/a:/usr/bin:/bin" \
    DOT_TEST_HOST_HOME="${DOT_TEST_HOST_HOME:-}" "$BIN_DIR/git" --version 2>&1)
  _assert_eq "git launcher resolution: a literal ~ PATH entry expands" \
    "real-b" "$_git_res_tilde_result"

  echo ""
  echo "=== git launcher re-entry bound ==="

  # A Git wrapper that is not a launcher copy, such as a test fault-injection
  # stub that captured `command -v git` (this launcher) as its "real" Git, is
  # a valid resolution candidate. When it delegates back to the launcher, the
  # two would exec each other forever. Every case runs under a timeout so a
  # regression fails instead of hanging the suite.
  _git_loop_timeout=""
  if command -v timeout >/dev/null 2>&1; then
    _git_loop_timeout=$(command -v timeout)
  elif command -v gtimeout >/dev/null 2>&1; then
    _git_loop_timeout=$(command -v gtimeout)
  fi
  _git_loop_root=$(_tmpdir)
  mkdir -p "$_git_loop_root/stub" "$_git_loop_root/twice" "$_git_loop_root/real" \
    "$_git_loop_root/redispatch" "$TEST_HOME/git-loop-plain"
  cat >"$_git_loop_root/stub/git" <<'EOF'
#!/usr/bin/env bash
printf 'stub\n' >>"$GIT_LOOP_LOG"
exec "$GIT_LOOP_DELEGATE" "$@"
EOF
  # Calls back twice per level, so a depth bound alone costs 2^max launches.
  cat >"$_git_loop_root/twice/git" <<'EOF'
#!/usr/bin/env bash
printf 'stub\n' >>"$GIT_LOOP_LOG"
"$GIT_LOOP_DELEGATE" rev-parse --git-dir >/dev/null 2>&1
exec "$GIT_LOOP_DELEGATE" "$@"
EOF
  # A legitimate wrapper: drop its own directory from PATH and re-dispatch,
  # re-entering the launcher exactly once before real Git runs.
  cat >"$_git_loop_root/redispatch/git" <<'EOF'
#!/usr/bin/env bash
PATH=":$PATH:"
PATH=${PATH//:${0%/*}:/:}
PATH=${PATH#:}
PATH=${PATH%:}
exec git "$@"
EOF
  cat >"$_git_loop_root/real/git" <<'EOF'
#!/usr/bin/env bash
printf 'real-git:%s:%s\n' "${_DOT_LAUNCHER_HOPS_git:-unset}" "$*"
EOF
  chmod +x "$_git_loop_root"/{stub,twice,redispatch,real}/git
  # Usage: _git_loop_run LABEL CWD PATH [ENV=VALUE...]; runs
  # `git ${_git_loop_args[@]}` under a ${_git_loop_limit:-10s} timeout and sets
  # _git_loop_rc, _git_loop_out and _git_loop_hops (stub invocations). Context
  # inherited from a hook or `rebase -x` that runs the suite would change the
  # route or the count, so the run starts without it.
  _git_loop_args=(check-ref-format --branch main)
  _git_loop_run() {
    local label="$1" cwd="$2" path="$3"
    shift 3
    : >"$_git_loop_root/$label.log"
    _git_loop_out=$(
      cd "$cwd" &&
        env -u _DOT_LAUNCHER_HOPS_git -u GIT_DIR -u GIT_WORK_TREE -u DOT_GIT_REAL \
          XDG_CACHE_HOME="$_git_loop_root/$label-cache" PATH="$path" \
          GIT_LOOP_LOG="$_git_loop_root/$label.log" \
          GIT_LOOP_DELEGATE="$BIN_DIR/git" "$@" \
          "$_git_loop_timeout" "${_git_loop_limit:-10s}" "$BIN_DIR/git" \
          "${_git_loop_args[@]}" 2>&1
    )
    _git_loop_rc=$?
    _git_loop_hops=$(wc -l <"$_git_loop_root/$label.log" | tr -d ' ')
  }
  # Usage: _git_loop_assert_bounded LABEL WRAPPER MAX_HOPS
  _git_loop_assert_bounded() {
    _assert_eq "git launcher re-entry ($1): fails instead of looping" \
      "2" "$_git_loop_rc"
    _assert_contains "git launcher re-entry ($1): names the wrapper" \
      "$_git_loop_root/$2/git" "$_git_loop_out"
    _assert_eq "git launcher re-entry ($1): bounds wrapper hops" "true" \
      "$([[ "$_git_loop_hops" -ge 1 && "$_git_loop_hops" -le "$3" ]] && echo true || echo false)"
  }
  # Each case is LABEL|CWD|PATH-ORDER|DOT_GIT_REAL. DOT_GIT_REAL=1 makes the
  # loop a tight exec chain in one process. Without it, a HOME descendant also
  # runs the nested-worktree probe through the wrapper, handing off twice per
  # launch.
  for _git_loop_case in \
    "wrapper-first-real|$TEST_HOME/git-loop-plain|wrapper|1" \
    "launcher-first-real|$TEST_HOME/git-loop-plain|launcher|1" \
    "outside-home|$_git_loop_root|launcher|0" \
    "home-root|$TEST_HOME|wrapper|0" \
    "nested-probe|$TEST_HOME/git-loop-plain|launcher|0"; do
    IFS='|' read -r _git_loop_label _git_loop_cwd _git_loop_order _git_loop_real \
      <<<"$_git_loop_case"
    if [[ -z "$_git_loop_timeout" ]]; then
      _pass "git launcher re-entry ($_git_loop_label): timeout unavailable, skipped"
      continue
    fi
    if [[ "$_git_loop_order" == wrapper ]]; then
      _git_loop_path="$_git_loop_root/stub:$BIN_DIR:/usr/bin:/bin"
    else
      _git_loop_path="$BIN_DIR:$_git_loop_root/stub:/usr/bin:/bin"
    fi
    _git_loop_run "$_git_loop_label" "$_git_loop_cwd" "$_git_loop_path" \
      DOT_GIT_REAL="$_git_loop_real"
    _git_loop_assert_bounded "$_git_loop_label" stub 64
  done

  if [[ -n "$_git_loop_timeout" ]]; then
    # A HOME without a dotfiles repo (a scratch HOME, a fresh host) execs the
    # wrapper without GIT_DIR, so every re-entry probes again. Unless the
    # probe's own re-entry skips probing, the launches branch exponentially.
    mkdir -p "$_git_loop_root/bare-home/plain"
    _git_loop_run bare-home "$_git_loop_root/bare-home/plain" \
      "$BIN_DIR:$_git_loop_root/stub:/usr/bin:/bin" \
      HOME="$_git_loop_root/bare-home" DOT_TEST_HOST_HOME="${DOT_TEST_HOST_HOME:-}"
    _git_loop_assert_bounded "bare HOME probe" stub 64

    # The bound is on depth, so a wrapper calling back twice per level costs
    # about 2^max launches; the budget must stay small enough to finish.
    _git_loop_limit=60s
    _git_loop_run twice "$_git_loop_root" \
      "$BIN_DIR:$_git_loop_root/twice:/usr/bin:/bin" DOT_GIT_REAL=1
    _git_loop_limit=
    _git_loop_assert_bounded "two callbacks per level" twice 1024

    # A wrapper that re-enters once on its way to real Git must keep working,
    # including through the nested-worktree probe: a nested repo under HOME
    # must not fall back to the dotfiles repo.
    _git_loop_repo="$TEST_HOME/git/loop-redispatch"
    mkdir -p "$_git_loop_repo/sub"
    env -u GIT_DIR -u GIT_WORK_TREE git -C "$_git_loop_repo" init -q
    _git_loop_args=(rev-parse --show-toplevel)
    _git_loop_run redispatch "$_git_loop_repo/sub" \
      "$BIN_DIR:$_git_loop_root/redispatch:/usr/bin:/bin"
    _git_loop_args=(check-ref-format --branch main)
    _assert_eq "git launcher re-entry: a re-dispatching wrapper keeps nested repos" \
      "$(cd "$_git_loop_repo" && pwd -P)" "$_git_loop_out"

    # Hooks and other Git children that run the launcher again inherit the
    # count, so ordinary nesting and garbage values must still reach real Git.
    _git_loop_real_path="$BIN_DIR:$_git_loop_root/real:/usr/bin:/bin"
    _git_loop_run fresh "$_git_loop_root" "$_git_loop_real_path"
    _assert_eq "git launcher re-entry: real Git sees the first hop" \
      "real-git:1:check-ref-format --branch main" "$_git_loop_out"
    _git_loop_run nested "$_git_loop_root" "$_git_loop_real_path" _DOT_LAUNCHER_HOPS_git=4
    _assert_eq "git launcher re-entry: nested launches still reach real Git" \
      "real-git:5:check-ref-format --branch main" "$_git_loop_out"
    _git_loop_run garbage "$_git_loop_root" "$_git_loop_real_path" _DOT_LAUNCHER_HOPS_git=x9
    _assert_eq "git launcher re-entry: an invalid count restarts the budget" \
      "real-git:1:check-ref-format --branch main" "$_git_loop_out"
  fi

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
