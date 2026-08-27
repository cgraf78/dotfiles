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
