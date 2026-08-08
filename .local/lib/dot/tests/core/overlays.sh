# shellcheck shell=bash
# overlays.sh - overlay coverage.

dot_core_test_overlays() {
  echo ""
  echo "=== Overlay discovery ==="

  # No overlays.d → empty
  _discover_overlays
  _assert_eq "no overlays dir: empty" "0" "${#OVERLAYS[@]}"

  overlay_target_rc=0
  overlay_target=$(
    # shellcheck disable=SC2123 # prove this helper has no command dependency.
    PATH=/nonexistent
    _overlay_link_target ".config/dot/example.conf" work
    printf '%s\n' "$REPLY"
  ) 2>/dev/null || overlay_target_rc=$?
  _assert_exit "overlay link target: uses no external path utilities" 0 "$overlay_target_rc"
  _assert_eq "overlay link target: preserves nested relative target" \
    "../../.dotfiles-work/home/.config/dot/example.conf" "$overlay_target"

  if _overlay_parse_manifest_record "nested//file"$'\t'"work"; then
    _fail "overlay manifest: rejects empty path components"
  else
    _pass "overlay manifest: rejects empty path components"
  fi
  if _overlay_parse_manifest_record "nested/file/"$'\t'"work"; then
    _fail "overlay manifest: rejects trailing separators"
  else
    _pass "overlay manifest: rejects trailing separators"
  fi

  # The first run with an XDG state root must retain cleanup authority from the
  # old HOME-default manifest. Otherwise a removed overlay leaves its symlink
  # and the base file's skip-worktree bit behind forever.
  legacy_manifest="$TEST_HOME/.local/state/dot/overlay-links"
  xdg_manifest="$TEST_HOME/xdg-state/dot/overlay-links"
  retired_overlay="$TEST_HOME/.dotfiles-retired"
  mkdir -p "${legacy_manifest%/*}" "$retired_overlay/home"
  printf 'base legacy value\n' >"$TEST_HOME/legacy-manifest-path"
  $GIT add legacy-manifest-path
  $GIT commit -m "add legacy manifest migration fixture" >/dev/null 2>&1
  printf 'retired overlay value\n' >"$retired_overlay/home/legacy-manifest-path"
  rm -f "$TEST_HOME/legacy-manifest-path"
  _overlay_link_target "legacy-manifest-path" retired
  ln -s "$REPLY" "$TEST_HOME/legacy-manifest-path"
  $GIT update-index --skip-worktree legacy-manifest-path
  printf 'legacy-manifest-path\tretired\n' >"$legacy_manifest"
  saved_manifest="$DOT_OVERLAY_MANIFEST"
  saved_legacy_manifest="$DOT_OVERLAY_LEGACY_MANIFEST"
  DOT_OVERLAY_MANIFEST="$xdg_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$legacy_manifest"
  _link_overlays >/dev/null 2>&1
  _assert_file_content "overlay manifest migration: restores stale tracked file" \
    "base legacy value" "$TEST_HOME/legacy-manifest-path"
  legacy_flag=$($GIT ls-files -v legacy-manifest-path 2>/dev/null | cut -c1)
  _assert_not_contains "overlay manifest migration: clears skip-worktree" "S" "$legacy_flag"
  _assert_file_exists "overlay manifest migration: writes selected XDG manifest" "$xdg_manifest"
  if [[ ! -e "$legacy_manifest" && ! -L "$legacy_manifest" ]]; then
    _pass "overlay manifest migration: removes adopted legacy manifest"
  else
    _fail "overlay manifest migration: removes adopted legacy manifest"
  fi

  failed_manifest="$TEST_HOME/failed-xdg-state/dot/overlay-links"
  printf 'failed-manifest-path\tretired\n' >"$legacy_manifest"
  printf 'base failed value\n' >"$TEST_HOME/failed-manifest-path"
  $GIT add failed-manifest-path
  $GIT commit -m "add failed manifest migration fixture" >/dev/null 2>&1
  printf 'retired failed value\n' >"$retired_overlay/home/failed-manifest-path"
  rm -f "$TEST_HOME/failed-manifest-path"
  _overlay_link_target "failed-manifest-path" retired
  ln -s "$REPLY" "$TEST_HOME/failed-manifest-path"
  $GIT update-index --skip-worktree failed-manifest-path
  DOT_OVERLAY_MANIFEST="$failed_manifest"
  # shellcheck disable=SC2329  # _link_overlays calls this failure fixture.
  mv() {
    if [[ "${2:-}" == "$DOT_OVERLAY_MANIFEST" ]]; then
      return 1
    fi
    command mv "$@"
  }
  if _link_overlays >/dev/null 2>&1; then
    _fail "overlay manifest migration: failed selected write propagates"
  else
    _pass "overlay manifest migration: failed selected write propagates"
  fi
  unset -f mv
  _assert_file_content "overlay manifest migration: failed write restores stale tracked file" \
    "base failed value" "$TEST_HOME/failed-manifest-path"
  failed_flag=$($GIT ls-files -v failed-manifest-path 2>/dev/null | cut -c1)
  _assert_not_contains "overlay manifest migration: failed write clears skip-worktree" \
    "S" "$failed_flag"
  _assert_file_content "overlay manifest migration: failed write retains cleanup authority" \
    $'failed-manifest-path\tretired' "$legacy_manifest"
  if [[ ! -e "$failed_manifest" && ! -L "$failed_manifest" ]]; then
    _pass "overlay manifest migration: failed write does not create selected manifest"
  else
    _fail "overlay manifest migration: failed write does not create selected manifest"
  fi
  _link_overlays >/dev/null 2>&1
  if [[ ! -e "$legacy_manifest" && ! -L "$legacy_manifest" ]]; then
    _pass "overlay manifest migration: retry removes retained legacy manifest"
  else
    _fail "overlay manifest migration: retry removes retained legacy manifest"
  fi
  DOT_OVERLAY_MANIFEST="$saved_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$saved_legacy_manifest"
  rm -rf "$retired_overlay" "$TEST_HOME/xdg-state"

  # Create overlays.d with a conf
  mkdir -p "$TEST_HOME/.config/dot/overlays.d"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@example.com:work.git
CONF
  _discover_overlays
  _assert_eq "one conf: one overlay" "1" "${#OVERLAYS[@]}"
  _assert_contains "one conf: name=work" "work|" "${OVERLAYS[0]}"
  _assert_contains "one conf: url" "git@example.com:work.git" "${OVERLAYS[0]}"
  _assert_contains "one conf: path" ".dotfiles-work" "${OVERLAYS[0]}"

  # Filesystem overlays use the normal descriptor directory but declare that
  # repository synchronization is external. Their configured path may contain
  # spaces and a leading ~/ is expanded without evaluating shell syntax.
  local_overlay_root="$TEST_HOME/local overlay"
  mkdir -p "$local_overlay_root/home"
  cat >"$TEST_HOME/.config/dot/overlays.d/15-filesystem.local.conf" <<'CONF'
sync=none
path=~/local overlay
CONF
  if _discover_overlays; then
    _pass "local descriptor: discovery succeeds"
  else
    _fail "local descriptor: discovery succeeds"
  fi
  _assert_eq "local descriptor: normal directory and local suffix preserve name" \
    "filesystem" "$(_overlay_name "15-filesystem.local.conf" none)"
  _assert_eq "local descriptor: record carries explicit sync type" \
    "filesystem|$local_overlay_root||$TEST_HOME/.config/dot/overlays.d/15-filesystem.local.conf|false||none" \
    "${OVERLAYS[1]}"
  if _preflight_local_overlays; then
    _pass "local descriptor: readable source passes preflight"
  else
    _fail "local descriptor: readable source passes preflight"
  fi

  printf '%s\n' "unreadable" >"$local_overlay_root/home/unreadable"
  chmod 000 "$local_overlay_root/home/unreadable"
  if [[ -r "$local_overlay_root/home/unreadable" ]]; then
    _pass "local descriptor: privileged runner bypasses unreadable fixture"
  elif _preflight_local_overlays >/dev/null 2>&1; then
    _fail "local descriptor: unreadable regular file fails preflight"
  else
    _pass "local descriptor: unreadable regular file fails preflight"
  fi
  chmod 600 "$local_overlay_root/home/unreadable"
  rm -f "$local_overlay_root/home/unreadable"

  ln -s missing-target "$local_overlay_root/home/dangling"
  if _preflight_local_overlays >/dev/null 2>&1; then
    _fail "local descriptor: dangling source symlink fails preflight"
  else
    _pass "local descriptor: dangling source symlink fails preflight"
  fi
  rm -f "$local_overlay_root/home/dangling"

  printf '%s\n' "readable target" >"$local_overlay_root/home/symlink-target"
  ln -s symlink-target "$local_overlay_root/home/readable-symlink"
  if _preflight_local_overlays; then
    _pass "local descriptor: readable source symlink passes preflight"
  else
    _fail "local descriptor: readable source symlink passes preflight"
  fi
  rm -f \
    "$local_overlay_root/home/readable-symlink" \
    "$local_overlay_root/home/symlink-target"

  # A source below HOME must not be able to map one of its files back into its
  # own home/ tree. Otherwise linking that destination would replace source
  # content and make later inventory/cleanup results depend on mutation order.
  mkdir -p "$local_overlay_root/home/local overlay/home"
  printf '%s\n' "source must survive" \
    >"$local_overlay_root/home/local overlay/home/recursive"
  if _preflight_local_overlays >/dev/null 2>&1; then
    _fail "local descriptor: self-targeting destination fails preflight"
  else
    _pass "local descriptor: self-targeting destination fails preflight"
  fi
  if _link_overlays >/dev/null 2>&1; then
    _fail "local descriptor: linker rejects self-targeting destination"
  else
    _pass "local descriptor: linker rejects self-targeting destination"
  fi
  _assert_file_content "local descriptor: rejected link leaves source intact" \
    "source must survive" "$local_overlay_root/home/local overlay/home/recursive"
  _assert_file_missing "local descriptor: rejected link writes no manifest" \
    "$DOT_OVERLAY_MANIFEST"
  rm -rf "$local_overlay_root/home/local overlay"

  mv "$local_overlay_root" "$local_overlay_root.missing"
  if _preflight_local_overlays >/dev/null 2>&1; then
    _fail "local descriptor: missing source fails preflight"
  else
    _pass "local descriptor: missing source fails preflight"
  fi
  mv "$local_overlay_root.missing" "$local_overlay_root"
  rm -f "$TEST_HOME/.config/dot/overlays.d/15-filesystem.local.conf"
  _discover_overlays

  # Multiple confs → sorted order
  cat >"$TEST_HOME/.config/dot/overlays.d/20-nas.conf" <<'CONF'
url=git@example.com:nas.git
CONF
  _discover_overlays
  _assert_eq "two confs: two overlays" "2" "${#OVERLAYS[@]}"
  _assert_contains "two confs: first is work" "work|" "${OVERLAYS[0]}"
  _assert_contains "two confs: second is nas" "nas|" "${OVERLAYS[1]}"

  # A legacy Git descriptor without a URL is skipped, preserving every valid
  # overlay already discovered around it.
  cat >"$TEST_HOME/.config/dot/overlays.d/30-bad.conf" <<'CONF'
platforms=linux
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _pass "missing url: discovery continues"
  else
    _fail "missing url: discovery continues"
  fi
  _assert_eq "missing url: valid overlays remain active" "2" "${#OVERLAYS[@]}"
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-bad.conf"
  _discover_overlays

  # Duplicate names → warned and skipped
  cat >"$TEST_HOME/.config/dot/overlays.d/99-work.conf" <<'CONF'
url=git@example.com:other-work.git
CONF
  discovery_log="$(_tmpdir)/unknown-git-key.log"
  _discover_overlays >"$discovery_log" 2>&1
  result=$(cat "$discovery_log")
  _assert_eq "duplicate: still two" "2" "${#OVERLAYS[@]}"
  _assert_contains "duplicate: warns" "duplicate overlay name" "$result"
  rm -f "$TEST_HOME/.config/dot/overlays.d/99-work.conf"

  # Name extraction
  _assert_eq "name: 10-work.conf" "work" "$(_overlay_name "10-work.conf")"
  _assert_eq "name: 20-my-nas.conf" "my-nas" "$(_overlay_name "20-my-nas.conf")"
  _assert_eq "name: work.conf" "work" "$(_overlay_name "work.conf")"
  _assert_eq "name: 5-x.conf" "x" "$(_overlay_name "5-x.conf")"
  _assert_eq "name: Git descriptor retains local suffix" \
    "work.local" "$(_overlay_name "10-work.local.conf")"
  _assert_eq "name: filesystem descriptor strips local suffix" \
    "work" "$(_overlay_name "10-work.local.conf" none)"
  # Regression: a name that looks like an echo flag (e.g. "-n") must survive.
  # _overlay_name uses printf, not echo, so the leading dash is not consumed.
  _assert_eq "name: leading-dash echo-flag-like" "-n" "$(_overlay_name "10--n.conf")"

  # Comments are skipped
  cat >"$TEST_HOME/.config/dot/overlays.d/30-commented.conf" <<'CONF'
# This is a comment
url=git@example.com:commented.git

# Another comment
CONF
  _discover_overlays
  _assert_eq "comments: three overlays" "3" "${#OVERLAYS[@]}"
  _assert_contains "comments: url parsed" "git@example.com:commented.git" "${OVERLAYS[2]}"
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-commented.conf"

  # Legacy Git descriptors keep their tolerant parser contract: unknown keys
  # warn, while recognized values still produce an active overlay.
  cat >"$TEST_HOME/.config/dot/overlays.d/30-typo.conf" <<'CONF'
url=git@example.com:typo.git
unknown_key=linux
CONF
  discovery_log="$(_tmpdir)/unknown-git-key.log"
  _discover_overlays >"$discovery_log" 2>&1
  result=$(cat "$discovery_log")
  _assert_eq "unknown Git key: descriptor remains active" "3" "${#OVERLAYS[@]}"
  _assert_contains "unknown Git key: warning is retained" "unknown key in" "$result"
  _assert_contains "unknown Git key: URL is retained" \
    "git@example.com:typo.git" "${OVERLAYS[2]}"
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-typo.conf"
  _discover_overlays

  cat >"$TEST_HOME/.config/dot/overlays.d/30-optional.conf" <<'CONF'
url=git@example.com:optional.git
optional=maybe
CONF
  discovery_log="$(_tmpdir)/invalid-git-optional.log"
  _discover_overlays >"$discovery_log" 2>&1
  result=$(cat "$discovery_log")
  _assert_eq "invalid Git optional: descriptor remains active" "3" "${#OVERLAYS[@]}"
  _assert_contains "invalid Git optional: warning is retained" \
    "unknown optional value" "$result"
  _assert_contains "invalid Git optional: value remains non-optional" \
    "|maybe||git" "${OVERLAYS[2]}"
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-optional.conf"

  cat >"$TEST_HOME/.config/dot/overlays.d/30-duplicate.conf" <<'CONF'
url=git@example.com:first.git
url=git@example.com:last.git
optional=false
optional=true
CONF
  _discover_overlays
  _assert_eq "duplicate Git keys: descriptor remains active" "3" "${#OVERLAYS[@]}"
  _assert_contains "duplicate Git keys: last URL wins" \
    "git@example.com:last.git" "${OVERLAYS[2]}"
  _assert_contains "duplicate Git keys: last optional value wins" \
    "|true||git" "${OVERLAYS[2]}"
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-duplicate.conf"
  _discover_overlays

  # Filesystem descriptor syntax is new and fail-closed. A typo must never be
  # reinterpreted as an intentional overlay removal.
  cat >"$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf" <<CONF
sync=none
path=$local_overlay_root
unknown_key=value
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _fail "invalid local key: discovery fails closed"
  else
    _pass "invalid local key: discovery fails closed"
  fi
  _assert_eq "invalid local key: partial overlays are discarded" "0" "${#OVERLAYS[@]}"

  cat >"$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf" <<'CONF'
sync=none
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _fail "missing local path: discovery fails closed"
  else
    _pass "missing local path: discovery fails closed"
  fi

  cat >"$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf" <<CONF
sync=none
path=$local_overlay_root
path=$local_overlay_root
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _fail "duplicate local path: discovery fails closed"
  else
    _pass "duplicate local path: discovery fails closed"
  fi

  cat >"$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf" <<'CONF'
sync=none
sync=git
url=git@example.com:wrong-mode.git
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _fail "duplicate sync mode: discovery fails closed"
  else
    _pass "duplicate sync mode: discovery fails closed"
  fi

  cat >"$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf" <<CONF
url=git@example.com:ambiguous.git
path=$local_overlay_root
CONF
  if _discover_overlays >/dev/null 2>&1; then
    _fail "local path without sync mode: discovery fails closed"
  else
    _pass "local path without sync mode: discovery fails closed"
  fi
  rm -f "$TEST_HOME/.config/dot/overlays.d/30-invalid.local.conf"
  _discover_overlays

  # Filtered duplicates must not leak their optional/key metadata into the
  # active overlay. The overlay name is the same after prefix stripping, but
  # only the parsed record that survived platform/host filters owns repo policy.
  _saved_shdeps_platform_match="$(declare -f shdeps_platform_match || true)"
  # shellcheck disable=SC2329  # invoked indirectly by _parse_overlay_conf.
  shdeps_platform_match() {
    [[ "$1" == "active-test-platform" ]]
  }
  cat >"$TEST_HOME/.config/dot/overlays.d/05-work.conf" <<'CONF'
url=git@example.com:filtered-work.git
platforms=filtered-test-platform
optional=true
CONF
  cat >"$TEST_HOME/.config/dot/overlays.d/05-work.ssh" <<'SSH'
Host github-dotfiles-filtered-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/filtered-work-deploy-test-nonexistent
SSH
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@example.com:active-work.git
platforms=active-test-platform
optional=false
CONF
  result=$(_discover_overlays 2>&1)
  _assert_eq "filtered duplicate: active overlay count unchanged" "2" "${#OVERLAYS[@]}"
  _assert_contains "filtered duplicate: active optional false survives" "|false|" "${OVERLAYS[0]}"
  _assert_not_contains "filtered duplicate: filtered ssh does not leak" \
    "05-work.ssh" "${OVERLAYS[0]}"
  _assert_not_contains "filtered duplicate: no duplicate warning for filtered conf" \
    "duplicate overlay name" "$result"
  rm -f \
    "$TEST_HOME/.config/dot/overlays.d/05-work.conf" \
    "$TEST_HOME/.config/dot/overlays.d/05-work.ssh"
  if [[ -n "$_saved_shdeps_platform_match" ]]; then
    eval "$_saved_shdeps_platform_match"
  else
    unset -f shdeps_platform_match
  fi

  # Clean up for remaining tests — keep only work
  rm -f "$TEST_HOME/.config/dot/overlays.d/20-nas.conf"

  # ---------------------------------------------------------------------------
  # Tests: overlay helpers
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Overlay helpers ==="

  # Create a local bare repo to serve as overlay origin.
  dot_fixture_file_origin OVERLAY_BARE "work-file" "work content"
  OVERLAY_DIR="$TEST_HOME/.dotfiles-work"

  # Update overlay conf to point at local bare repo
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
CONF

  # No overlay dir → clones automatically
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: clones missing overlay" "Cloning work dotfiles" "$result"
  if [[ -d "$OVERLAY_DIR/.git" ]]; then
    _pass "pull_overlays: overlay dir created"
  else
    _fail "pull_overlays: overlay dir created"
  fi

  # A configured path may contain user-owned files. Sync must report that
  # conflict rather than removing it before a re-clone.
  rm -rf "$OVERLAY_DIR"
  mkdir -p "$OVERLAY_DIR"
  printf 'keep me\n' >"$OVERLAY_DIR/sentinel"
  _pull_overlay "work" "$OVERLAY_DIR" "$OVERLAY_BARE" false ""
  _assert_eq "pull_overlay: existing non-worktree reports failure" "failed" "$REPLY_STATUS"
  _pull_overlays >/dev/null
  _assert_eq "pull_overlays: existing non-worktree is included in failures" "1" \
    "$DOT_PULL_OVERLAY_FAILED"
  if [[ -f "$OVERLAY_DIR/sentinel" && ! -e "$OVERLAY_DIR/.git" ]]; then
    _pass "pull_overlays: existing non-worktree remains untouched"
  else
    _fail "pull_overlays: existing non-worktree remains untouched"
  fi

  rm -rf "$OVERLAY_DIR"
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: clones after non-worktree is removed" \
    "Cloning work dotfiles" "$result"
  printf 'base managed content\n' >"$TEST_HOME/managed-before-replacement"
  $GIT add managed-before-replacement
  $GIT commit -m "add managed replacement fixture" >/dev/null 2>&1
  mkdir -p "$OVERLAY_DIR/home"
  printf 'managed before replacement\n' >"$OVERLAY_DIR/home/managed-before-replacement"
  printf 'untracked before replacement\n' >"$OVERLAY_DIR/home/untracked-before-replacement"
  _link_overlays >/dev/null
  if [[ -L "$TEST_HOME/managed-before-replacement" ]]; then
    _pass "overlay link: valid checkout establishes managed fixture"
  else
    _fail "overlay link: valid checkout establishes managed fixture"
  fi
  if [[ -L "$TEST_HOME/untracked-before-replacement" ]]; then
    _pass "overlay link: valid checkout establishes untracked managed fixture"
  else
    _fail "overlay link: valid checkout establishes untracked managed fixture"
  fi

  # Relative local URLs have a stable HOME-relative meaning. Git otherwise
  # records them relative to the clone process's cwd, which would make a valid
  # checkout fail identity validation when dot runs from another directory.
  RELATIVE_OVERLAY_BARE="$TEST_HOME/relative-origin.git"
  relative_staging=$(_tmpdir)
  printf 'relative origin\n' >"$relative_staging/relative-file"
  dot_fixture_seed_repo "$RELATIVE_OVERLAY_BARE" "$relative_staging"
  relative_name="relative-origin.git"
  relative_overlay="$TEST_HOME/.dotfiles-relative"
  pushd "$TEST_HOME/.config" >/dev/null || return 1
  _pull_overlay "relative" "$relative_overlay" "$relative_name" false ""
  _assert_eq "pull_overlay: relative local URL clones" "cloned" "$REPLY_STATUS"
  popd >/dev/null || return 1
  _pull_overlay "relative" "$relative_overlay" "$relative_name" false ""
  _assert_eq "pull_overlay: relative local URL remains valid from another cwd" \
    "current" "$REPLY_STATUS"
  _assert_eq "overlay origin: relative local URL is stored HOME-relative" \
    "$RELATIVE_OVERLAY_BARE" "$(git -C "$relative_overlay" config --get remote.origin.url)"
  rm -rf "$relative_overlay" "$RELATIVE_OVERLAY_BARE"

  # Converged policy checks must not rewrite every repository config on both
  # the pre-pull and finalization passes of a no-op update.
  _ensure_repo_config
  base_config_inode=$(stat -c '%i' "$DOTFILES/config" 2>/dev/null ||
    stat -f '%i' "$DOTFILES/config")
  overlay_config_inode=$(stat -c '%i' "$OVERLAY_DIR/.git/config" 2>/dev/null ||
    stat -f '%i' "$OVERLAY_DIR/.git/config")
  _ensure_repo_config
  _assert_eq "repo config: converged base config keeps its inode" \
    "$base_config_inode" \
    "$(stat -c '%i' "$DOTFILES/config" 2>/dev/null || stat -f '%i' "$DOTFILES/config")"
  _assert_eq "repo config: converged overlay config keeps its inode" \
    "$overlay_config_inode" \
    "$(stat -c '%i' "$OVERLAY_DIR/.git/config" 2>/dev/null || stat -f '%i' "$OVERLAY_DIR/.git/config")"
  git -C "$OVERLAY_DIR" config pull.rebase false
  _ensure_repo_config
  _assert_eq "repo config: mismatched overlay policy is repaired" \
    "true" "$(git -C "$OVERLAY_DIR" config --get pull.rebase)"
  git -C "$OVERLAY_DIR" config core.fsmonitor true
  _ensure_repo_config
  _assert_eq "repo config: overlay fsmonitor policy remains repo-owned" \
    "true" "$(git -C "$OVERLAY_DIR" config --get core.fsmonitor)"
  $GIT config core.fsmonitor true
  _ensure_repo_config
  _assert_eq "repo config: unsafe base fsmonitor policy is repaired" \
    "false" "$($GIT config --get core.fsmonitor)"

  # A Git checkout at the configured path is not sufficient evidence that it
  # is the configured overlay. Fail closed before pull so an unrelated repo is
  # never updated merely because it occupies ~/.dotfiles-<name>.
  dot_fixture_file_origin UNRELATED_OVERLAY_BARE "home/foreign-overlay-file" "keep unrelated"
  rm -rf "$OVERLAY_DIR"
  dot_fixture_clone_repo "$UNRELATED_OVERLAY_BARE" "$OVERLAY_DIR"
  unrelated_head=$(git -C "$OVERLAY_DIR" rev-parse HEAD)
  unrelated_origin=$(git -C "$OVERLAY_DIR" config --get remote.origin.url)
  _ui_begin 5
  result=$(
    if _dot_update_sync_repos 0 0 2>&1; then
      printf 'status=success\n'
    else
      printf 'status=failed\n'
    fi
  )
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED DOT_UI_STAGE_LABEL DOT_UI_STAGE_DETAIL
  unset DOT_UI_STAGE_STARTED DOT_UI_LIVE_ACTIVE
  _assert_contains "update sync: rejected replacement fails repository sync" \
    "status=failed" "$result"
  _assert_contains "update sync: dashboard reports the rejected replacement" \
    "overlay origin mismatch" "$result"
  _assert_file_content "update sync: rejected replacement restores tracked base content" \
    "base managed content" "$TEST_HOME/managed-before-replacement"
  managed_flag=$($GIT ls-files -v managed-before-replacement 2>/dev/null | cut -c1)
  _assert_not_contains "update sync: rejected replacement clears skip-worktree" \
    "S" "$managed_flag"
  if [[ ! -e "$TEST_HOME/untracked-before-replacement" &&
    ! -L "$TEST_HOME/untracked-before-replacement" ]]; then
    _pass "update sync: rejected replacement removes untracked managed link"
  else
    _fail "update sync: rejected replacement removes untracked managed link"
  fi
  _assert_not_contains "update sync: rejected replacement leaves no tracked ownership" \
    "managed-before-replacement" "$(cat "$DOT_OVERLAY_MANIFEST")"
  _assert_not_contains "update sync: rejected replacement leaves no untracked ownership" \
    "untracked-before-replacement" "$(cat "$DOT_OVERLAY_MANIFEST")"
  _ensure_repo_config
  _assert_eq "repo config: unrelated checkout origin is not rewritten" "$unrelated_origin" \
    "$(git -C "$OVERLAY_DIR" config --get remote.origin.url)"
  _repo_pull_all >/dev/null 2>&1
  _assert_eq "repo pull: unrelated checkout origin remains untouched" "$unrelated_origin" \
    "$(git -C "$OVERLAY_DIR" config --get remote.origin.url)"
  _link_overlays >/dev/null 2>&1
  if [[ ! -e "$TEST_HOME/foreign-overlay-file" && ! -L "$TEST_HOME/foreign-overlay-file" ]]; then
    _pass "overlay link: unrelated checkout content is excluded"
  else
    _fail "overlay link: unrelated checkout content is excluded"
  fi
  if [[ -f "$TEST_HOME/managed-before-replacement" &&
    ! -L "$TEST_HOME/managed-before-replacement" ]]; then
    _pass "overlay link: rejected replacement keeps the restored base file"
  else
    _fail "overlay link: rejected replacement keeps the restored base file"
  fi
  result=$(
    _pull_overlay "work" "$OVERLAY_DIR" "$OVERLAY_BARE" false "" 2>&1
    printf 'status=%s\n' "$REPLY_STATUS"
  )
  _assert_contains "pull_overlay: unrelated checkout reports failure" "status=failed" "$result"
  _assert_contains "pull_overlay: unrelated checkout reports expected origin" \
    "expected: $OVERLAY_BARE" "$result"
  _assert_contains "pull_overlay: unrelated checkout reports actual origin" \
    "found:    $UNRELATED_OVERLAY_BARE" "$result"
  _assert_contains "pull_overlay: unrelated checkout provides explicit adoption command" \
    "remote set-url origin" "$result"
  _assert_eq "pull_overlay: unrelated checkout is not updated" "$unrelated_head" \
    "$(git -C "$OVERLAY_DIR" rev-parse HEAD)"

  # A checkout with no origin is also ambiguous. Keep it untouched and explain
  # the same explicit adoption path rather than treating another remote as the
  # configured repository.
  git -C "$OVERLAY_DIR" remote remove origin
  result=$(
    _pull_overlay "work" "$OVERLAY_DIR" "$OVERLAY_BARE" false "" 2>&1
    printf 'status=%s\n' "$REPLY_STATUS"
  )
  _assert_contains "pull_overlay: missing origin reports failure" "status=failed" "$result"
  _assert_contains "pull_overlay: missing origin is named" "found:    <missing>" "$result"
  _assert_contains "pull_overlay: missing origin provides a working adoption operation" \
    "remote add origin" "$result"
  git -C "$OVERLAY_DIR" remote add origin "$OVERLAY_BARE"
  if _overlay_origin_matches "$OVERLAY_DIR" "$OVERLAY_BARE"; then
    _pass "overlay adoption: remote add repairs a missing origin"
  else
    _fail "overlay adoption: remote add repairs a missing origin"
  fi

  # Exact comparison intentionally accepts SSH aliases and local path spellings
  # without trying to canonicalize either one as a GitHub URL.
  alias_origin="github-dotfiles-work:cgraf78/dotfiles-work.git"
  git -C "$OVERLAY_DIR" remote set-url origin "$alias_origin"
  if _overlay_origin_matches "$OVERLAY_DIR" "$alias_origin"; then
    _pass "overlay origin: documented SSH alias spelling matches verbatim"
  else
    _fail "overlay origin: documented SSH alias spelling matches verbatim"
  fi

  redirected_overlay="$TEST_HOME/.dotfiles-redirected"
  redirected_worktree=$(_tmpdir)
  git init -q "$redirected_overlay"
  git -C "$redirected_overlay" remote add origin "$alias_origin"
  git -C "$redirected_overlay" config core.worktree "$redirected_worktree"
  mkdir -p "$redirected_overlay/home"
  if _overlay_checkout_matches "$redirected_overlay" "$alias_origin"; then
    _fail "overlay checkout: rejects a Git directory whose worktree is elsewhere"
  else
    _pass "overlay checkout: rejects a Git directory whose worktree is elsewhere"
  fi
  rm -rf "$redirected_overlay" "$redirected_worktree"

  git -C "$OVERLAY_DIR" config --add remote.origin.url "another-alias:work.git"
  if _overlay_origin_matches "$OVERLAY_DIR" "$alias_origin"; then
    _fail "overlay origin: multiple origin URLs are rejected"
  else
    _pass "overlay origin: multiple origin URLs are rejected"
  fi
  _assert_eq "overlay origin: ambiguous origin is named" "<multiple origin URLs>" "$REPLY"
  result=$(_pull_overlay "work" "$OVERLAY_DIR" "$alias_origin" false "" 2>&1)
  _assert_contains "pull_overlay: multiple origins provide a working adoption operation" \
    "config --replace-all remote.origin.url" "$result"
  git -C "$OVERLAY_DIR" config --replace-all remote.origin.url "$alias_origin"
  if _overlay_origin_matches "$OVERLAY_DIR" "$alias_origin"; then
    _pass "overlay adoption: replace-all repairs multiple origin URLs"
  else
    _fail "overlay adoption: replace-all repairs multiple origin URLs"
  fi

  rm -rf "$OVERLAY_DIR" "$UNRELATED_OVERLAY_BARE"
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: reclones configured overlay after mismatch fixture" \
    "Cloning work dotfiles" "$result"
  _assert_eq "pull_overlays: recloned checkout keeps configured origin" "$OVERLAY_BARE" \
    "$(git -C "$OVERLAY_DIR" config --get remote.origin.url)"

  # Linked worktrees use a `.git` file, not a directory, but are valid overlay
  # checkouts and should be synchronized rather than re-cloned.
  LINKED_OVERLAY_DIR="$TEST_HOME/.dotfiles-work-linked"
  git -C "$OVERLAY_DIR" worktree add --detach -q "$LINKED_OVERLAY_DIR"
  OVERLAYS=("linked|$LINKED_OVERLAY_DIR|$OVERLAY_BARE||false|")
  _pull_overlays >/dev/null
  _assert_eq "pull_overlays: linked worktree is scheduled" "1" "$DOT_PULL_OVERLAY_SKIPPED"
  if [[ -f "$LINKED_OVERLAY_DIR/.git" ]]; then
    _pass "pull_overlays: linked worktree remains in place"
  else
    _fail "pull_overlays: linked worktree remains in place"
  fi
  git -C "$OVERLAY_DIR" worktree remove --force "$LINKED_OVERLAY_DIR"
  _discover_overlays

  _parallel_overlay_state="$(_tmpdir)"
  mkdir -p "$_parallel_overlay_state"
  printf '0' >"$_parallel_overlay_state/active"
  printf '0' >"$_parallel_overlay_state/max"
  result=$(
    # shellcheck disable=SC2329  # _pull_overlays invokes this fixture by name.
    _pull_overlay_active() { return 0; }
    # shellcheck disable=SC2329  # _pull_overlays invokes this fixture by name.
    _pull_overlay() {
      local _lock="$_parallel_overlay_state/lock"
      local _active _max _tries=0
      while ! mkdir "$_lock" 2>/dev/null; do sleep 0.01; done
      _active=$(cat "$_parallel_overlay_state/active" 2>/dev/null || printf '0')
      _max=$(cat "$_parallel_overlay_state/max" 2>/dev/null || printf '0')
      _active=$((_active + 1))
      [[ "$_active" -le "$_max" ]] || _max="$_active"
      printf '%s' "$_active" >"$_parallel_overlay_state/active"
      printf '%s' "$_max" >"$_parallel_overlay_state/max"
      rmdir "$_lock"

      while :; do
        _max=$(cat "$_parallel_overlay_state/max" 2>/dev/null || printf '0')
        [[ "$_max" -ge 2 ]] && break
        _tries=$((_tries + 1))
        [[ "$_tries" -ge 100 ]] && break
        sleep 0.01
      done

      while ! mkdir "$_lock" 2>/dev/null; do sleep 0.01; done
      _active=$(cat "$_parallel_overlay_state/active" 2>/dev/null || printf '0')
      _active=$((_active - 1))
      printf '%s' "$_active" >"$_parallel_overlay_state/active"
      rmdir "$_lock"
      # shellcheck disable=SC2034  # read by _pull_overlays after worker capture.
      REPLY_STATUS=current
    }
    OVERLAYS=(
      "one|$TEST_HOME/.dotfiles-one|unused||false|"
      "two|$TEST_HOME/.dotfiles-two|unused||false|"
      "three|$TEST_HOME/.dotfiles-three|unused||false|"
    )
    export DOT_UPDATE_JOBS=2
    _pull_overlays
    printf 'reply=%s\n' "$REPLY"
    printf 'max=%s\n' "$(cat "$_parallel_overlay_state/max")"
    printf 'current=%s\n' "${DOT_PULL_OVERLAY_CURRENT:-0}"
  )
  _assert_contains "pull_overlays: uses DOT_UPDATE_JOBS for overlay sync concurrency" \
    "max=2" "$result"
  _assert_contains "pull_overlays: preserves discovery-order summary after parallel sync" \
    "reply=one current, two current, three current" "$result"
  _assert_contains "pull_overlays: tallies parallel overlay sync results" \
    "current=3" "$result"

  # Pull failure inside the update UI should not be followed by a misleading
  # "current" status row.
  missing_origin="$TEST_HOME/missing-overlay-origin"
  git -C "$OVERLAY_DIR" remote set-url origin "$missing_origin"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$missing_origin
CONF
  _discover_overlays
  _ui_begin 5
  result=$(_pull_overlays 2>&1)
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED
  _assert_contains "pull_overlays: ui pull failure warns" "warning  work dotfiles pull failed" "$result"
  _assert_not_contains "pull_overlays: ui pull failure is not ok" "ok       work dotfiles current" "$result"

  # Clone failure is graceful (bad URL)
  rm -rf "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@nonexistent-host-xyz:bad/repo.git
CONF
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: clone failure warns" "clone failed" "$result"

  cat >"$TEST_HOME/.config/dot/overlays.d/05-work.conf" <<'CONF'
url=git@example.com:filtered-work.git
platforms=definitely-not-this-platform
optional=true
CONF
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@nonexistent-host-xyz:bad/repo.git
optional=false
CONF
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: active required duplicate still warns" "clone failed" "$result"
  rm -f "$TEST_HOME/.config/dot/overlays.d/05-work.conf"

  # Optional private overlays try normal Git auth when available, but a failed
  # clone should not block unrelated dotfiles setup on machines without access.
  rm -rf "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@nonexistent-host-xyz:bad/repo.git
optional=true
CONF
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_eq "pull_overlays: optional clone failure skips silently" "" "$result"
  if [[ ! -d "$OVERLAY_DIR" ]]; then
    _pass "pull_overlays: optional clone failure leaves overlay absent"
  else
    _fail "pull_overlays: optional clone failure leaves overlay absent"
  fi

  # Required deploy-key overlays should fail fast when their key is missing.
  # Optional overlays are the explicit way to say "skip when not available".
  rm -rf "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
CONF
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host github-dotfiles-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/dotfiles-work-deploy-test-nonexistent
  IdentitiesOnly yes
SSH
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: required missing key warns" "deploy key missing" "$result"
  if [[ ! -d "$OVERLAY_DIR" ]]; then
    _pass "pull_overlays: required missing key avoids clone"
  else
    _fail "pull_overlays: required missing key avoids clone"
  fi

  # Key present → clone proceeds
  mkdir -p "$TEST_HOME/.ssh"
  touch "$TEST_HOME/.ssh/dotfiles-work-deploy-test-nonexistent"
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: clones when key present" "Cloning work dotfiles" "$result"
  rm -f "$TEST_HOME/.ssh/dotfiles-work-deploy-test-nonexistent"
  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.ssh"

  # Optional deploy-key overlays still respect the key gate. This avoids a
  # slow/noisy SSH attempt on personal machines that know about a work overlay
  # but intentionally do not have its key.
  rm -rf "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
optional=true
CONF
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host github-dotfiles-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/dotfiles-work-deploy-test-nonexistent
  IdentitiesOnly yes
SSH
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_eq "pull_overlays: optional deploy-key overlay skips when key missing" "" "$result"
  if [[ ! -d "$OVERLAY_DIR" ]]; then
    _pass "pull_overlays: optional missing key avoids clone"
  else
    _fail "pull_overlays: optional missing key avoids clone"
  fi
  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.ssh"

  # No .ssh file → clone proceeds (public repo)
  rm -rf "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
CONF
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: clones without ssh file" "Cloning work dotfiles" "$result"

  # Existing required overlay + missing deploy key is still a failure. The
  # checkout may be present, but the required overlay cannot be synchronized.
  git -C "$OVERLAY_DIR" remote set-url origin "$TEST_HOME/missing-overlay-origin"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host github-dotfiles-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/dotfiles-work-deploy-test-nonexistent
  IdentitiesOnly yes
SSH
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: existing required overlay missing key warns" \
    "deploy key missing" "$result"
  _assert_not_contains "pull_overlays: missing key avoids git pull failure" \
    "pull failed" "$result"

  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
optional=true
CONF
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_eq "pull_overlays: existing optional overlay skips when key missing" "" "$result"
  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.ssh"

  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=/missing-optional-origin
optional=true
CONF
  git -C "$OVERLAY_DIR" remote set-url origin /missing-optional-origin
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_eq "pull_overlays: optional existing overlay pull failure skips" "" "$result"

  # Restore conf with working URL for remaining tests
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
CONF
  git -C "$OVERLAY_DIR" remote set-url origin "$OVERLAY_BARE"
  _discover_overlays

  # Remove overlay dir so next section can recreate it
  rm -rf "$OVERLAY_DIR"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$OVERLAY_DIR"

  # Pull overlay succeeds
  _discover_overlays
  result=$(_pull_overlays 2>&1)
  _assert_contains "pull_overlays: shows pulling" "Pulling work" "$result"

  _overlay_branch=$(git -C "$OVERLAY_DIR" branch --show-current)
  git -C "$OVERLAY_DIR" checkout -b feature/no-upstream >/dev/null 2>&1
  result=$(
    _pull_overlays 2>&1
    printf 'reply=%s\n' "$REPLY"
  )
  git -C "$OVERLAY_DIR" checkout "$_overlay_branch" >/dev/null 2>&1
  _assert_contains "pull_overlays: skips feature branch without upstream" \
    "reply=work skipped" "$result"
  _assert_not_contains "pull_overlays: hides missing upstream error" \
    "There is no tracking information" "$result"

  export DOT_UI_FORCE_LIVE=1
  export DOT_UI_ASCII=1
  _ui_begin 5
  _ui_stage_start "Repos" "pulling repositories"
  # shellcheck disable=SC2034  # read by _pull_overlays when dashboard progress is active.
  DOT_REPO_PROGRESS_DONE=1
  # shellcheck disable=SC2034  # read by _pull_overlays when dashboard progress is active.
  DOT_REPO_PROGRESS_TOTAL=2
  result=$(_pull_overlays 2>&1)
  unset DOT_REPO_PROGRESS_DONE DOT_REPO_PROGRESS_TOTAL DOT_UI_FORCE_LIVE DOT_UI_ASCII
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED DOT_UI_STAGE_LABEL DOT_UI_STAGE_DETAIL DOT_UI_STAGE_STARTED DOT_UI_LIVE_ACTIVE
  _assert_contains "pull_overlays: dashboard progress names current overlay" \
    "work               [########] 2/2" "$result"

  rm -rf "$OVERLAY_DIR" "$OVERLAY_BARE"

  # ---------------------------------------------------------------------------
  # Tests: _link_overlay / _link_overlays
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Overlay linking ==="

  # No overlay dir → no-op
  _discover_overlays
  result=$(_link_overlays 2>&1)
  # (no output expected — overlay dir doesn't exist)

  # Create overlay dir with home/ structure
  OVERLAY_BARE=$(_tmpdir)
  git init --bare "$OVERLAY_BARE" >/dev/null 2>&1
  OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$OVERLAY_DIR"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$OVERLAY_BARE
CONF

  mkdir -p "$OVERLAY_DIR/home/.config/test"
  echo "work config" >"$OVERLAY_DIR/home/.config/test/config.conf"
  echo "work shell" >"$OVERLAY_DIR/home/.testrc_work"

  # Recovery publication is the transaction boundary for overlay linking. If
  # it fails, no link or index mutation may occur because there would be no
  # durable record authorizing a later cleanup.
  tempfail_saved_manifest="$DOT_OVERLAY_MANIFEST"
  tempfail_saved_legacy_manifest="$DOT_OVERLAY_LEGACY_MANIFEST"
  tempfail_legacy_manifest="$TEST_HOME/.local/state/dot/overlay-links"
  tempfail_manifest="$TEST_HOME/tempfail-xdg-state/dot/overlay-links"
  mkdir -p "${tempfail_legacy_manifest%/*}"
  printf 'retained-authority\tretired\n' >"$tempfail_legacy_manifest"
  echo "base temp failure" >"$TEST_HOME/.tempfail_tracked"
  $GIT add .tempfail_tracked
  $GIT commit -m "add manifest temp failure fixture" >/dev/null 2>&1
  echo "overlay temp failure" >"$OVERLAY_DIR/home/.tempfail_tracked"
  DOT_OVERLAY_MANIFEST="$tempfail_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$tempfail_legacy_manifest"
  _discover_overlays
  # shellcheck disable=SC2329  # _link_overlays calls this failure fixture.
  mktemp() {
    if [[ "${1:-}" == "${DOT_OVERLAY_MANIFEST}.pending.tmp.XXXXXX" ]]; then
      return 1
    fi
    command mktemp "$@"
  }
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery temp failure: propagates"
  else
    _pass "link recovery temp failure: propagates"
  fi
  unset -f mktemp
  if [[ ! -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "link recovery temp failure: creates no untracked link"
  else
    _fail "link recovery temp failure: creates no untracked link"
  fi
  _assert_file_content "link recovery temp failure: preserves tracked file" \
    "base temp failure" "$TEST_HOME/.tempfail_tracked"
  tempfail_flag=$($GIT ls-files -v .tempfail_tracked 2>/dev/null | cut -c1)
  _assert_not_contains "link recovery temp failure: does not set skip-worktree" \
    "S" "$tempfail_flag"
  _assert_file_content "link recovery temp failure: retains legacy authority" \
    $'retained-authority\tretired' "$tempfail_legacy_manifest"
  if [[ ! -e "$tempfail_manifest" && ! -L "$tempfail_manifest" ]]; then
    _pass "link recovery temp failure: creates no selected manifest"
  else
    _fail "link recovery temp failure: creates no selected manifest"
  fi

  _link_overlays >/dev/null 2>&1
  if [[ -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "link recovery temp failure: retry creates links"
  else
    _fail "link recovery temp failure: retry creates links"
  fi
  tempfail_flag=$($GIT ls-files -v .tempfail_tracked 2>/dev/null | cut -c1)
  _assert_eq "link recovery temp failure: retry sets skip-worktree" "S" "$tempfail_flag"
  _assert_file_exists "link recovery temp failure: retry writes selected manifest" \
    "$tempfail_manifest"
  if [[ ! -e "$tempfail_legacy_manifest" && ! -L "$tempfail_legacy_manifest" ]]; then
    _pass "link recovery temp failure: retry removes legacy authority"
  else
    _fail "link recovery temp failure: retry removes legacy authority"
  fi

  _unstash_overlay_overrides
  rm -f "$OVERLAY_DIR/home/.tempfail_tracked" \
    "$TEST_HOME/.config/test/config.conf" "$TEST_HOME/.testrc_work"
  DOT_OVERLAY_MANIFEST="$tempfail_saved_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$tempfail_saved_legacy_manifest"
  rm -rf "$TEST_HOME/tempfail-xdg-state"

  # Unsafe deterministic pending paths are never followed or replaced. A
  # recovery run must fail before linking and leave the suspicious object
  # untouched for explicit repair.
  safety_manifest="$TEST_HOME/safety-state/dot/overlay-links"
  safety_pending="${safety_manifest}.pending"
  safety_sentinel="$TEST_HOME/pending-sentinel"
  mkdir -p "${safety_manifest%/*}"
  printf 'sentinel\n' >"$safety_sentinel"
  DOT_OVERLAY_MANIFEST="$safety_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-safety-legacy"
  ln -s "$safety_sentinel" "$safety_pending"
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery safety: symlink pending fails closed"
  else
    _pass "link recovery safety: symlink pending fails closed"
  fi
  _assert_file_content "link recovery safety: symlink target is untouched" \
    "sentinel" "$safety_sentinel"
  if [[ ! -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "link recovery safety: unsafe pending creates no links"
  else
    _fail "link recovery safety: unsafe pending creates no links"
  fi

  # Pull must not continue after recovery authority fails validation. Otherwise
  # update could advance repositories before it knows how to restore paths left
  # by an interrupted linking phase.
  pull_probe="$TEST_HOME/unsafe-pending-pull-probe"
  result=$(
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _ensure_repo_config() { :; }
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _normalize_filtered() { :; }
    # shellcheck disable=SC2329  # must remain uncalled after recovery failure.
    _pull_base() { printf 'base\n' >>"$pull_probe"; }
    # shellcheck disable=SC2329  # must remain uncalled after recovery failure.
    _pull_overlays() { printf 'overlays\n' >>"$pull_probe"; }
    if _repo_pull_all >/dev/null 2>&1; then
      printf 'success\n'
    else
      printf 'failed\n'
    fi
  )
  _assert_eq "repo pull recovery safety: unsafe pending fails repository sync" \
    "failed" "$result"
  if [[ ! -e "$pull_probe" ]]; then
    _pass "repo pull recovery safety: unsafe pending prevents all pulls"
  else
    _fail "repo pull recovery safety: unsafe pending prevents all pulls"
  fi

  rm -f "$safety_pending"
  ln -s "$safety_sentinel" "$safety_manifest"
  selected_pull_probe="$TEST_HOME/unsafe-selected-pull-probe"
  result=$(
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _ensure_repo_config() { :; }
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _normalize_filtered() { :; }
    # shellcheck disable=SC2329  # must remain uncalled after authority failure.
    _pull_base() { printf 'base\n' >>"$selected_pull_probe"; }
    # shellcheck disable=SC2329  # must remain uncalled after authority failure.
    _pull_overlays() { printf 'overlays\n' >>"$selected_pull_probe"; }
    if _repo_pull_all >/dev/null 2>&1; then
      printf 'success\n'
    else
      printf 'failed\n'
    fi
  )
  _assert_eq "repo pull recovery safety: unsafe selected manifest fails sync" \
    "failed" "$result"
  if [[ ! -e "$selected_pull_probe" ]]; then
    _pass "repo pull recovery safety: unsafe selected manifest prevents all pulls"
  else
    _fail "repo pull recovery safety: unsafe selected manifest prevents all pulls"
  fi
  if [[ -L "$safety_manifest" && "$(readlink "$safety_manifest")" == "$safety_sentinel" ]]; then
    _pass "repo pull recovery safety: unsafe selected manifest is preserved"
  else
    _fail "repo pull recovery safety: unsafe selected manifest is preserved"
  fi
  _assert_file_content "repo pull recovery safety: selected symlink target is untouched" \
    "sentinel" "$safety_sentinel"
  rm -f "$safety_manifest"

  mkdir "$safety_pending"
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery safety: directory pending fails closed"
  else
    _pass "link recovery safety: directory pending fails closed"
  fi
  if [[ -d "$safety_pending" ]]; then
    _pass "link recovery safety: directory pending is preserved"
  else
    _fail "link recovery safety: directory pending is preserved"
  fi
  rmdir "$safety_pending"
  : >"$safety_pending"
  chmod 644 "$safety_pending"
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery safety: public pending fails closed"
  else
    _pass "link recovery safety: public pending fails closed"
  fi
  rm -f "$safety_pending"

  # A legacy path that was never accepted as authority is user-owned even when
  # a successful run commits a new selected manifest.
  safety_legacy="$TEST_HOME/safety-legacy"
  ln -s "$safety_sentinel" "$safety_legacy"
  DOT_OVERLAY_LEGACY_MANIFEST="$safety_legacy"
  _link_overlays >/dev/null 2>&1
  if [[ -L "$safety_legacy" && "$(readlink "$safety_legacy")" == "$safety_sentinel" ]]; then
    _pass "link recovery safety: unadopted legacy symlink is preserved"
  else
    _fail "link recovery safety: unadopted legacy symlink is preserved"
  fi
  _assert_file_content "link recovery safety: legacy symlink target is untouched" \
    "sentinel" "$safety_sentinel"
  rm -f "$TEST_HOME/.config/test/config.conf" "$TEST_HOME/.testrc_work" \
    "$safety_manifest" "$safety_legacy"

  # The inventory published to pending is also the sole mutation inventory. A
  # file appearing after enumeration must wait for the next run, never become
  # a link absent write-ahead authority.
  inventory_manifest="$TEST_HOME/inventory-state/dot/overlay-links"
  inventory_late="$OVERLAY_DIR/home/.inventory-late"
  DOT_OVERLAY_MANIFEST="$inventory_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-inventory-legacy"
  _discover_overlays
  # shellcheck disable=SC2329  # _overlay_prepare_inventories calls this fixture.
  find() {
    command find "$@"
    if [[ "${1:-}" == "$OVERLAY_DIR/home" && ! -e "$inventory_late" ]]; then
      printf 'late candidate\n' >"$inventory_late"
    fi
  }
  _link_overlays >/dev/null 2>&1
  unset -f find
  if [[ ! -e "$TEST_HOME/.inventory-late" && ! -L "$TEST_HOME/.inventory-late" ]]; then
    _pass "link recovery inventory: late candidate is not linked"
  else
    _fail "link recovery inventory: late candidate is not linked"
  fi
  _assert_not_contains "link recovery inventory: late candidate has no final authority" \
    ".inventory-late" "$(cat "$inventory_manifest")"
  if [[ ! -e "${inventory_manifest}.pending" && ! -L "${inventory_manifest}.pending" ]]; then
    _pass "link recovery inventory: successful run retires pending authority"
  else
    _fail "link recovery inventory: successful run retires pending authority"
  fi
  rm -f "$inventory_late" "$TEST_HOME/.config/test/config.conf" \
    "$TEST_HOME/.testrc_work" "$inventory_manifest"
  rm -rf "$TEST_HOME/inventory-state"

  # A recognized managed link is not safely unstashed until both the index bit
  # and worktree content are restored. Any Git restore failure must block pulls.
  restore_manifest="$TEST_HOME/restore-state/dot/overlay-links"
  printf 'base restore\n' >"$TEST_HOME/.restore-failure"
  $GIT add .restore-failure
  $GIT commit -m "add restore failure fixture" >/dev/null 2>&1
  printf 'overlay restore\n' >"$OVERLAY_DIR/home/.restore-failure"
  DOT_OVERLAY_MANIFEST="$restore_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-restore-legacy"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  restore_pull_probe="$TEST_HOME/restore-pull-probe"
  result=$(
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _ensure_repo_config() { :; }
    # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
    _normalize_filtered() { :; }
    # shellcheck disable=SC2329  # must remain uncalled after restore failure.
    _pull_base() { printf 'base\n' >>"$restore_pull_probe"; }
    # shellcheck disable=SC2329  # must remain uncalled after restore failure.
    _pull_overlays() { printf 'overlays\n' >>"$restore_pull_probe"; }
    # shellcheck disable=SC2329  # intercepts the checkout attempted by unstash.
    git() {
      local arg
      for arg in "$@"; do
        [[ "$arg" == "checkout" ]] && return 1
      done
      command git "$@"
    }
    if _repo_pull_all >/dev/null 2>&1; then
      printf 'success\n'
    else
      printf 'failed\n'
    fi
  )
  _assert_eq "repo pull recovery safety: Git restore failure blocks sync" \
    "failed" "$result"
  if [[ ! -e "$restore_pull_probe" ]]; then
    _pass "repo pull recovery safety: Git restore failure prevents all pulls"
  else
    _fail "repo pull recovery safety: Git restore failure prevents all pulls"
  fi
  $GIT update-index --no-skip-worktree .restore-failure
  $GIT checkout -- .restore-failure
  rm -f "$OVERLAY_DIR/home/.restore-failure" "$TEST_HOME/.config/test/config.conf" \
    "$TEST_HOME/.testrc_work" "$restore_manifest"
  rm -rf "$TEST_HOME/restore-state"

  # POSIX mv treats a directory destination as a container. Even if the
  # selected path changes type after the entry check, the exact prepared file
  # must be verified at that path before pending authority is retired.
  directory_race_manifest="$TEST_HOME/directory-race-state/dot/overlay-links"
  directory_race_pending="${directory_race_manifest}.pending"
  DOT_OVERLAY_MANIFEST="$directory_race_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-directory-race-legacy"
  _discover_overlays
  # shellcheck disable=SC2329  # _link_overlays calls this race fixture.
  mv() {
    if [[ "${2:-}" == "$DOT_OVERLAY_MANIFEST" ]]; then
      mkdir -p "$DOT_OVERLAY_MANIFEST"
    fi
    command mv "$@"
  }
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery publication: directory race propagates"
  else
    _pass "link recovery publication: directory race propagates"
  fi
  unset -f mv
  if [[ -d "$directory_race_manifest" ]]; then
    _pass "link recovery publication: replacement directory is preserved"
  else
    _fail "link recovery publication: replacement directory is preserved"
  fi
  _assert_file_exists "link recovery publication: pending authority remains" \
    "$directory_race_pending"
  rm -f "$TEST_HOME/.config/test/config.conf" "$TEST_HOME/.testrc_work"
  rm -rf "$TEST_HOME/directory-race-state"

  # A failed final commit may leave both old and new owners live. The published
  # union must recognize either exact generated target, plus new tracked and
  # untracked links that were never present in the selected manifest.
  recovery_manifest="$TEST_HOME/recovery-state/dot/overlay-links"
  recovery_pending="${recovery_manifest}.pending"
  recovery_legacy="$TEST_HOME/recovery-legacy/overlay-links"
  retired_overlay="$TEST_HOME/.dotfiles-retired"
  mkdir -p "${recovery_manifest%/*}" "${recovery_legacy%/*}" \
    "$retired_overlay/home"
  printf '.owner-a\tretired\n.owner-b\tretired\n' >"$recovery_manifest"
  printf '.legacy-only\tretired\n' >"$recovery_legacy"
  for recovery_path in .owner-a .owner-b .legacy-only; do
    printf 'retired\n' >"$retired_overlay/home/$recovery_path"
    _overlay_link_target "$recovery_path" retired
    ln -s "$REPLY" "$TEST_HOME/$recovery_path"
  done
  printf 'base recovery\n' >"$TEST_HOME/.recovery-tracked"
  $GIT add .recovery-tracked
  $GIT commit -m "add overlay recovery fixture" >/dev/null 2>&1
  printf 'overlay recovery\n' >"$OVERLAY_DIR/home/.recovery-tracked"
  printf 'untracked recovery\n' >"$OVERLAY_DIR/home/.recovery-untracked"
  printf 'work owner\n' >"$OVERLAY_DIR/home/.owner-a"
  printf 'work owner\n' >"$OVERLAY_DIR/home/.owner-b"
  DOT_OVERLAY_MANIFEST="$recovery_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$recovery_legacy"
  _discover_overlays
  # shellcheck disable=SC2329  # _link_overlays calls this failure fixture.
  mv() {
    if [[ "${2:-}" == "$DOT_OVERLAY_MANIFEST" ]]; then
      return 1
    fi
    command mv "$@"
  }
  if _link_overlays >/dev/null 2>&1; then
    _fail "link recovery final commit: failure propagates"
  else
    _pass "link recovery final commit: failure propagates"
  fi
  unset -f mv
  if [[ -L "$TEST_HOME/.recovery-tracked" ]]; then
    _pass "link recovery final commit: tracked link was created"
  else
    _fail "link recovery final commit: tracked link was created"
  fi
  if [[ -L "$TEST_HOME/.recovery-untracked" ]]; then
    _pass "link recovery final commit: untracked link was created"
  else
    _fail "link recovery final commit: untracked link was created"
  fi
  recovery_flag=$($GIT ls-files -v .recovery-tracked 2>/dev/null | cut -c1)
  _assert_eq "link recovery final commit: tracked path is hidden" "S" "$recovery_flag"
  _assert_file_exists "link recovery final commit: pending authority remains" \
    "$recovery_pending"
  recovery_mode=$(stat -c '%a' "$recovery_pending" 2>/dev/null ||
    stat -f '%Lp' "$recovery_pending" 2>/dev/null)
  _assert_eq "link recovery final commit: pending authority is private" "600" "$recovery_mode"
  recovery_authority=$(cat "$recovery_pending")
  _assert_contains "link recovery owner replacement: old owner retained" \
    $'.owner-a\tretired' "$recovery_authority"
  _assert_contains "link recovery owner replacement: new owner anticipated" \
    $'.owner-a\twork' "$recovery_authority"

  # Simulate interruption on either side of owner replacement: one path points
  # to the old owner and one remains linked to the new owner.
  rm -f "$TEST_HOME/.owner-a"
  _overlay_link_target ".owner-a" retired
  ln -s "$REPLY" "$TEST_HOME/.owner-a"
  rm -f "$OVERLAY_DIR/home/.recovery-tracked" \
    "$OVERLAY_DIR/home/.recovery-untracked" "$OVERLAY_DIR/home/.owner-a" \
    "$OVERLAY_DIR/home/.owner-b"
  _link_overlays >/dev/null 2>&1
  _assert_file_content "link recovery retry: tracked base restored" \
    "base recovery" "$TEST_HOME/.recovery-tracked"
  recovery_flag=$($GIT ls-files -v .recovery-tracked 2>/dev/null | cut -c1)
  _assert_not_contains "link recovery retry: tracked flag cleared" "S" "$recovery_flag"
  for recovery_path in .recovery-untracked .owner-a .owner-b .legacy-only; do
    if [[ ! -e "$TEST_HOME/$recovery_path" && ! -L "$TEST_HOME/$recovery_path" ]]; then
      _pass "link recovery retry: removes $recovery_path"
    else
      _fail "link recovery retry: removes $recovery_path"
    fi
  done
  if [[ ! -e "$recovery_pending" && ! -L "$recovery_pending" ]]; then
    _pass "link recovery retry: removes pending authority"
  else
    _fail "link recovery retry: removes pending authority"
  fi
  if [[ ! -e "$recovery_legacy" && ! -L "$recovery_legacy" ]]; then
    _pass "link recovery retry: removes adopted legacy authority"
  else
    _fail "link recovery retry: removes adopted legacy authority"
  fi

  # A real signal after the first link cannot run rollback code. The pending
  # file must survive process death and authorize the next run's cleanup.
  crash_overlay="$TEST_HOME/.dotfiles-crash"
  crash_manifest="$TEST_HOME/crash-state/dot/overlay-links"
  crash_pending="${crash_manifest}.pending"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$crash_overlay"
  mkdir -p "$crash_overlay/home"
  printf 'crash recovery\n' >"$crash_overlay/home/.crash-recovery"
  DOT_OVERLAY_MANIFEST="$crash_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-crash-legacy"
  OVERLAYS=("crash|$crash_overlay|$OVERLAY_BARE||false|")
  if {
    (
      # shellcheck disable=SC2329  # _link_overlays calls this signal fixture.
      ln() {
        command ln "$@" || return
        kill -TERM "$BASHPID"
      }
      _link_overlays
    )
  } >/dev/null 2>&1; then
    _fail "link recovery signal: interrupted run fails"
  else
    _pass "link recovery signal: interrupted run fails"
  fi
  if [[ -L "$TEST_HOME/.crash-recovery" ]]; then
    _pass "link recovery signal: mutation occurred before termination"
  else
    _fail "link recovery signal: mutation occurred before termination"
  fi
  _assert_file_exists "link recovery signal: pending authority survives" "$crash_pending"
  rm -f "$crash_overlay/home/.crash-recovery"
  OVERLAYS=()
  _link_overlays >/dev/null 2>&1
  if [[ ! -e "$TEST_HOME/.crash-recovery" && ! -L "$TEST_HOME/.crash-recovery" ]]; then
    _pass "link recovery signal: retry removes interrupted link"
  else
    _fail "link recovery signal: retry removes interrupted link"
  fi
  if [[ ! -e "$crash_pending" && ! -L "$crash_pending" ]]; then
    _pass "link recovery signal: retry removes pending authority"
  else
    _fail "link recovery signal: retry removes pending authority"
  fi

  rm -f "$TEST_HOME/.config/test/config.conf" "$TEST_HOME/.testrc_work"
  rm -rf "$TEST_HOME/safety-state" "$TEST_HOME/recovery-state" \
    "$TEST_HOME/recovery-legacy" "$TEST_HOME/crash-state" "$retired_overlay" \
    "$crash_overlay"
  DOT_OVERLAY_MANIFEST="$tempfail_saved_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$tempfail_saved_legacy_manifest"

  # Link overlay — creates symlinks
  parent_probe="$TEST_HOME/.config/parent-probe"
  mkdir -p "$OVERLAY_DIR/home/.config/parent-probe"
  printf 'parent probe\n' >"$OVERLAY_DIR/home/.config/parent-probe/config.conf"
  parent_mkdir_log=$(_tmpdir)/parent-mkdir.log
  : >"$parent_mkdir_log"
  # shellcheck disable=SC2329  # _link_overlays invokes this test seam.
  mkdir() {
    local arg last_arg=""
    for arg in "$@"; do
      last_arg="$arg"
    done
    printf '%s\n' "$last_arg" >>"$parent_mkdir_log"
    command mkdir "$@"
  }
  _discover_overlays
  parent_link_rc=0
  result=$(_link_overlays 2>&1) || parent_link_rc=$?
  _assert_eq "link parent creation: cold probe converges" "0" "$parent_link_rc"
  if grep -Fqx "$parent_probe" "$parent_mkdir_log"; then
    _pass "link parent creation: missing destination parent invokes mkdir"
  else
    _fail "link parent creation: missing destination parent invokes mkdir"
  fi
  : >"$parent_mkdir_log"
  parent_link_rc=0
  _link_overlays >/dev/null 2>&1 || parent_link_rc=$?
  unset -f mkdir
  _assert_eq "link idempotent: existing-parent probe converges" "0" "$parent_link_rc"
  if grep -Fqx "$parent_probe" "$parent_mkdir_log"; then
    _fail "link idempotent: avoids mkdir for existing destination parent"
  else
    _pass "link idempotent: avoids mkdir for existing destination parent"
  fi
  _assert_contains "link: shows stage" "Overlays" "$result"
  _assert_contains "link: reports new symlinks" "linked:" "$result"
  if [[ -L "$TEST_HOME/.config/test/config.conf" ]]; then
    _pass "link: symlink created for nested file"
  else
    _fail "link: symlink created for nested file"
  fi
  if [[ -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "link: symlink created for top-level file"
  else
    _fail "link: symlink created for top-level file"
  fi

  # Verify symlinks are relative
  target=$(readlink "$TEST_HOME/.testrc_work")
  _assert_contains "link: relative symlink" ".dotfiles-work/home" "$target"

  # A manual cutover replaces the Git descriptor with a same-name local
  # descriptor before one update. The existing manifest must transfer
  # authority directly: retained files move to the new source, removed files
  # disappear, and new files appear without a cleanup-only pass.
  cutover_git_root="$TEST_HOME/.dotfiles-cutover"
  cutover_local_root="$TEST_HOME/local cutover source"
  cutover_git_conf="$TEST_HOME/.config/dot/overlays.d/30-cutover.conf"
  cutover_local_conf="$TEST_HOME/.config/dot/overlays.d/30-cutover.local.conf"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$cutover_git_root"
  mkdir -p "$cutover_git_root/home" "$cutover_local_root/home"
  printf 'Git retained value\n' >"$cutover_git_root/home/.cutover-retained"
  printf 'Git removed value\n' >"$cutover_git_root/home/.cutover-removed"
  cat >"$cutover_git_conf" <<CONF
url=$OVERLAY_BARE
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  _assert_contains "local cutover: starts on Git source" \
    ".dotfiles-cutover/home/.cutover-retained" \
    "$(readlink "$TEST_HOME/.cutover-retained" 2>/dev/null || true)"

  printf 'local retained value\n' >"$cutover_local_root/home/.cutover-retained"
  printf 'local added value\n' >"$cutover_local_root/home/.cutover-added"
  rm -f "$cutover_git_conf"
  cat >"$cutover_local_conf" <<CONF
sync=none
path=$cutover_local_root
CONF
  _discover_overlays
  _preflight_local_overlays
  _unstash_overlay_overrides
  _link_overlays >/dev/null 2>&1
  _assert_eq "local cutover: one pass repoints retained link" \
    "$cutover_local_root/home/.cutover-retained" \
    "$(readlink "$TEST_HOME/.cutover-retained" 2>/dev/null || true)"
  _assert_eq "local cutover: one pass links new file" \
    "$cutover_local_root/home/.cutover-added" \
    "$(readlink "$TEST_HOME/.cutover-added" 2>/dev/null || true)"
  if [[ ! -e "$TEST_HOME/.cutover-removed" && ! -L "$TEST_HOME/.cutover-removed" ]]; then
    _pass "local cutover: one pass removes retired link"
  else
    _fail "local cutover: one pass removes retired link"
  fi

  rm -f "$cutover_local_conf"
  rm -rf "$cutover_git_root" "$cutover_local_root"
  _discover_overlays
  _link_overlays >/dev/null 2>&1

  # A filesystem overlay participates in the same ownership lifecycle without
  # becoming part of the synchronized repository set. Its link target records
  # the configured source exactly so path changes and descriptor removal are
  # safe even when the source tree later disappears.
  local_lifecycle_root="$TEST_HOME/local lifecycle source"
  local_lifecycle_next="$TEST_HOME/local lifecycle next"
  local_descriptor="$TEST_HOME/.config/dot/overlays.d/15-filesystem.local.conf"
  mkdir -p "$local_lifecycle_root/home"
  printf 'local lifecycle value\n' >"$local_lifecycle_root/home/.filesystem-local"
  printf 'base filesystem value\n' >"$TEST_HOME/.filesystem-tracked"
  $GIT add .filesystem-tracked
  $GIT commit -m "add filesystem overlay fixture" >/dev/null 2>&1
  printf 'local filesystem value\n' >"$local_lifecycle_root/home/.filesystem-tracked"
  cat >"$local_descriptor" <<CONF
sync=none
path=$local_lifecycle_root
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  _assert_eq "local link: preserves exact configured target" \
    "$local_lifecycle_root/home/.filesystem-local" \
    "$(readlink "$TEST_HOME/.filesystem-local" 2>/dev/null || true)"
  if [[ -L "$TEST_HOME/.filesystem-tracked" ]]; then
    _pass "local link: shadows a tracked base file"
  else
    _fail "local link: shadows a tracked base file"
  fi
  local_tracked_flag=$($GIT ls-files -v .filesystem-tracked 2>/dev/null | cut -c1)
  _assert_eq "local link: tracked base file is hidden" "S" "$local_tracked_flag"
  manifest_content=$(cat "$DOT_OVERLAY_MANIFEST")
  _assert_contains "local link: manifest records exact target" \
    $'.filesystem-local\tfilesystem\t'"$local_lifecycle_root/home/.filesystem-local" \
    "$manifest_content"

  # A filesystem-managed source must not replace a user-owned symlink, even
  # when the destination is untracked. Unlike a Git checkout, this source may
  # change outside dot between validation and linking, so ownership must be
  # established by an exact active or manifest-authorized target.
  local_real_target="$TEST_HOME/.filesystem-real-target"
  mkdir -p "$local_real_target"
  ln -s "$local_real_target" "$TEST_HOME/.filesystem-symdir"
  printf 'local symlink fixture\n' \
    >"$local_lifecycle_root/home/.filesystem-symdir"
  result=$(_link_overlays 2>&1)
  _assert_contains "local link: warns before replacing unmanaged symlink" \
    "would replace unmanaged symlink" "$result"
  _assert_eq "local link: preserves unmanaged symlink target" \
    "$local_real_target" \
    "$(readlink "$TEST_HOME/.filesystem-symdir" 2>/dev/null || true)"
  _assert_file_missing "local link: does not write through unmanaged symlink" \
    "$local_real_target/.filesystem-symdir"
  rm -f \
    "$local_lifecycle_root/home/.filesystem-symdir" \
    "$TEST_HOME/.filesystem-symdir"
  rm -rf "$local_real_target"

  manifest_before="$manifest_content"
  mv "$local_lifecycle_root" "$local_lifecycle_root.missing"
  if _link_overlays >/dev/null 2>&1; then
    _fail "local preflight: missing active source blocks linking"
  else
    _pass "local preflight: missing active source blocks linking"
  fi
  _assert_eq "local preflight: existing link is untouched" \
    "$local_lifecycle_root/home/.filesystem-local" \
    "$(readlink "$TEST_HOME/.filesystem-local" 2>/dev/null || true)"
  _assert_file_content "local preflight: manifest is untouched" \
    "$manifest_before" "$DOT_OVERLAY_MANIFEST"
  mv "$local_lifecycle_root.missing" "$local_lifecycle_root"

  mkdir -p "$local_lifecycle_next/home"
  printf 'new local lifecycle value\n' >"$local_lifecycle_next/home/.filesystem-local"
  printf 'new local filesystem value\n' >"$local_lifecycle_next/home/.filesystem-tracked"
  cat >"$local_descriptor" <<CONF
sync=none
path=$local_lifecycle_next
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  _assert_eq "local link: descriptor path change replaces owned link" \
    "$local_lifecycle_next/home/.filesystem-local" \
    "$(readlink "$TEST_HOME/.filesystem-local" 2>/dev/null || true)"

  rm -f "$local_lifecycle_next/home/.filesystem-local"
  _link_overlays >/dev/null 2>&1
  if [[ ! -e "$TEST_HOME/.filesystem-local" && ! -L "$TEST_HOME/.filesystem-local" ]]; then
    _pass "local link: removed source file removes managed link"
  else
    _fail "local link: removed source file removes managed link"
  fi

  printf 'remove with descriptor value\n' >"$local_lifecycle_next/home/.filesystem-remove"
  _link_overlays >/dev/null 2>&1
  rm -f "$local_descriptor"
  rm -rf "$local_lifecycle_next"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  if [[ ! -e "$TEST_HOME/.filesystem-remove" && ! -L "$TEST_HOME/.filesystem-remove" ]]; then
    _pass "local link: descriptor removal cleans links without source access"
  else
    _fail "local link: descriptor removal cleans links without source access"
  fi
  _assert_file_content "local link: descriptor removal restores tracked base file" \
    "base filesystem value" "$TEST_HOME/.filesystem-tracked"
  local_tracked_flag=$($GIT ls-files -v .filesystem-tracked 2>/dev/null | cut -c1)
  _assert_not_contains "local link: descriptor removal clears tracked index state" \
    "S" "$local_tracked_flag"

  mkdir -p "$local_lifecycle_root/home"
  printf 'replacement fixture\n' >"$local_lifecycle_root/home/.filesystem-replaced"
  cat >"$local_descriptor" <<CONF
sync=none
path=$local_lifecycle_root
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  rm -f "$TEST_HOME/.filesystem-replaced"
  printf 'user replacement\n' >"$TEST_HOME/.filesystem-replaced"
  rm -f "$local_descriptor"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  _assert_file_content "local link: descriptor removal preserves user replacement" \
    "user replacement" "$TEST_HOME/.filesystem-replaced"
  rm -f "$TEST_HOME/.filesystem-replaced"
  rm -rf "$local_lifecycle_root"

  # Read legacy two-column authority, then rewrite every surviving record in
  # the exact-target three-column format on the next successful link pass.
  legacy_build=$(mktemp "${DOT_OVERLAY_MANIFEST}.legacy.XXXXXX")
  awk -F '\t' '{ print $1 "\t" $2 }' "$DOT_OVERLAY_MANIFEST" >"$legacy_build"
  chmod 600 "$legacy_build"
  mv "$legacy_build" "$DOT_OVERLAY_MANIFEST"
  _link_overlays >/dev/null 2>&1
  if awk -F '\t' 'NF != 3 { exit 1 }' "$DOT_OVERLAY_MANIFEST"; then
    _pass "overlay manifest: legacy records migrate to exact targets"
  else
    _fail "overlay manifest: legacy records migrate to exact targets"
  fi

  # Result accounting must use structured state, not words in the display
  # label. Overlay names may contain spaces, including the word "linked".
  linked_name="status linked fixture"
  linked_dir="$TEST_HOME/.dotfiles-$linked_name"
  dot_fixture_clone_repo "$OVERLAY_BARE" "$linked_dir"
  mkdir -p "$linked_dir/home"
  printf 'linked-name fixture\n' >"$linked_dir/home/.linked-name-fixture"
  cat >"$TEST_HOME/.config/dot/overlays.d/99-$linked_name.conf" <<CONF
url=$OVERLAY_BARE
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1

  export DOT_UI_FORCE_LIVE=1
  export DOT_UI_ASCII=1
  _ui_begin 5
  result=$(_link_overlays 2>&1)
  unset DOT_UI_FORCE_LIVE DOT_UI_ASCII
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED DOT_UI_STAGE_LABEL DOT_UI_STAGE_DETAIL DOT_UI_STAGE_STARTED DOT_UI_LIVE_ACTIVE
  _assert_contains "link status: display words do not mark current overlays changed" \
    "2 overlays current" "$result"
  _assert_not_contains "link status: current overlay name is not parsed as state" \
    "overlay changed" "$result"

  rm -f "$TEST_HOME/.config/dot/overlays.d/99-$linked_name.conf"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  rm -rf "$linked_dir"

  # Idempotent: re-run produces no per-file output
  result=$(_link_overlays 2>&1)
  _assert_contains "link idempotent: stage still shown" "Overlays" "$result"
  _assert_not_contains "link idempotent: no per-file output" "linked:" "$result"

  export DOT_UI_FORCE_LIVE=1
  export DOT_UI_ASCII=1
  _ui_begin 5
  result=$(_link_overlays 2>&1)
  unset DOT_UI_FORCE_LIVE DOT_UI_ASCII
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED DOT_UI_STAGE_LABEL DOT_UI_STAGE_DETAIL DOT_UI_STAGE_STARTED DOT_UI_LIVE_ACTIVE
  _assert_contains "link dashboard: progress names current overlay" \
    "work               [########] 1/1" "$result"
  _assert_contains "link dashboard: summarizes overlays numerically" \
    "1 overlay current" "$result"
  _assert_not_contains "link dashboard: avoids named overlay summary" \
    "work overlay current" "$result"

  rm "$TEST_HOME/.testrc_work"
  export DOT_UI_FORCE_LIVE=1
  export DOT_UI_ASCII=1
  _ui_begin 5
  result=$(_link_overlays 2>&1)
  unset DOT_UI_FORCE_LIVE DOT_UI_ASCII
  unset DOT_UI_TOTAL DOT_UI_INDEX DOT_UI_STARTED DOT_UI_STAGE_LABEL DOT_UI_STAGE_DETAIL DOT_UI_STAGE_STARTED DOT_UI_LIVE_ACTIVE
  _assert_contains "link dashboard changed: marks overlays stage changed" \
    "Overlays   changed" "$result"
  _assert_contains "link dashboard changed: summarizes changed overlay count" \
    "1 overlay changed" "$result"
  _assert_contains "link dashboard changed: prints changed overlay detail" \
    "changed  work overlay linked 1" "$result"

  # Quiet mode: no output
  DOT_QUIET=1
  rm "$TEST_HOME/.testrc_work" # force re-link
  result=$(_link_overlays 2>&1)
  # shellcheck disable=SC2034  # read by sourced helpers
  DOT_QUIET=0
  _assert_eq "link quiet: no output" "" "$result"
  if [[ -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "link quiet: still creates symlink"
  else
    _fail "link quiet: still creates symlink"
  fi

  # Manifest is written
  _assert_file_exists "link: manifest written" "$TEST_HOME/.local/state/dot/overlay-links"
  manifest_content=$(cat "$TEST_HOME/.local/state/dot/overlay-links")
  _assert_contains "link: manifest has testrc_work" ".testrc_work" "$manifest_content"

  # Skip-worktree: overlay file shadowing a base-repo file
  echo "base version" >"$TEST_HOME/.testrc"
  $GIT add .testrc
  $GIT commit -m "add testrc" >/dev/null 2>&1
  echo "overlay version" >"$OVERLAY_DIR/home/.testrc"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  # Symlink should exist
  if [[ -L "$TEST_HOME/.testrc" ]]; then
    _pass "skip-worktree: symlink created for shadowed file"
  else
    _fail "skip-worktree: symlink created for shadowed file"
  fi
  # skip-worktree should be set
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_eq "skip-worktree: flag set" "S" "$sw_flag"

  # Unstash restores paths that the overlay manifest owns.
  _unstash_overlay_overrides
  if [[ -f "$TEST_HOME/.testrc" && ! -L "$TEST_HOME/.testrc" ]]; then
    _pass "unstash: manifest-owned base file restored"
  else
    _fail "unstash: manifest-owned base file restored"
  fi
  _assert_file_content "unstash: manifest-owned base content" \
    "base version" "$TEST_HOME/.testrc"
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_not_contains "unstash: manifest-owned flag cleared" "S" "$sw_flag"

  # An unrelated skip-worktree entry may belong to the user or another tool.
  # It is not in the overlay manifest, so unstash must preserve both its local
  # content and index flag.
  echo "committed lock value" >"$TEST_HOME/.manual_lock"
  $GIT add .manual_lock
  $GIT commit -m "add manual lock fixture" >/dev/null 2>&1
  echo "local lock value" >"$TEST_HOME/.manual_lock"
  $GIT update-index --skip-worktree .manual_lock
  _unstash_overlay_overrides
  _assert_file_content "unstash: unrelated content preserved" \
    "local lock value" "$TEST_HOME/.manual_lock"
  sw_flag=$($GIT ls-files -v .manual_lock 2>/dev/null | cut -c1)
  _assert_eq "unstash: unrelated flag preserved" "S" "$sw_flag"

  # Leave the unrelated fixture clean, then recreate the managed link for
  # current-ownership validation.
  $GIT update-index --no-skip-worktree .manual_lock
  $GIT checkout -- .manual_lock
  _link_overlays >/dev/null 2>&1

  # A manifest entry is historical evidence, not proof that the overlay still
  # owns the live path. Preserve a user replacement through both unstash and
  # relinking, including the skip-worktree bit that hides it from Git status.
  rm -f "$TEST_HOME/.testrc"
  echo "local replacement" >"$TEST_HOME/.testrc"
  unstash_log="$(_tmpdir)/unstash.log"
  _unstash_overlay_overrides >"$unstash_log" 2>&1
  result=$(cat "$unstash_log")
  _assert_contains "unstash: replaced managed path warns" \
    "preserving replaced overlay path: .testrc" "$result"
  _assert_file_content "unstash: replaced managed content preserved" \
    "local replacement" "$TEST_HOME/.testrc"
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_eq "unstash: replaced managed flag preserved" "S" "$sw_flag"
  result=$(_link_overlays 2>&1)
  _assert_contains "link: replaced managed path skipped" \
    "skip (would clobber modified tracked file): .testrc" "$result"
  _assert_file_content "link: replaced managed content preserved" \
    "local replacement" "$TEST_HOME/.testrc"
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_eq "link: replaced managed flag preserved" "S" "$sw_flag"

  # Clean the replacement and relink it before exercising missing-manifest
  # recovery. A live link matching an active overlay is sufficient proof even
  # when the generated manifest was lost.
  $GIT update-index --no-skip-worktree .testrc
  $GIT checkout -- .testrc
  _link_overlays >/dev/null 2>&1
  if [[ -L "$TEST_HOME/.testrc" ]]; then
    _pass "unstash: missing-manifest fixture is a managed link"
  else
    _fail "unstash: missing-manifest fixture is a managed link"
  fi
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_eq "unstash: missing-manifest fixture has owned flag" "S" "$sw_flag"
  rm -f "$DOT_OVERLAY_MANIFEST"
  _unstash_overlay_overrides
  _assert_file_content "unstash: missing manifest restores active overlay" \
    "base version" "$TEST_HOME/.testrc"
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_not_contains "unstash: missing manifest clears owned flag" "S" "$sw_flag"
  _link_overlays >/dev/null 2>&1

  # Clearing skip-worktree makes a local replacement visible to Git, but does
  # not authorize the linker to discard it.
  $GIT update-index --no-skip-worktree .testrc
  rm -f "$TEST_HOME/.testrc"
  echo "visible local replacement" >"$TEST_HOME/.testrc"
  result=$(_link_overlays 2>&1)
  _assert_contains "link: visible tracked replacement skipped" \
    "would clobber modified tracked file" "$result"
  _assert_file_content "link: visible tracked replacement preserved" \
    "visible local replacement" "$TEST_HOME/.testrc"

  # Stale cleanup applies the same validation when the overlay stops providing
  # a path, so a visible local replacement is not reset to the base version.
  $GIT checkout -- .testrc
  echo "base stale value" >"$TEST_HOME/.stale_local"
  $GIT add .stale_local
  $GIT commit -m "add stale local fixture" >/dev/null 2>&1
  echo "overlay stale value" >"$OVERLAY_DIR/home/.stale_local"
  _link_overlays >/dev/null 2>&1
  $GIT update-index --no-skip-worktree .stale_local
  rm -f "$TEST_HOME/.stale_local" "$OVERLAY_DIR/home/.stale_local"
  echo "visible stale replacement" >"$TEST_HOME/.stale_local"
  result=$(_link_overlays 2>&1)
  _assert_contains "cleanup: visible stale replacement skipped" \
    "stale overlay path has local content" "$result"
  _assert_file_content "cleanup: visible stale replacement preserved" \
    "visible stale replacement" "$TEST_HOME/.stale_local"
  $GIT checkout -- .stale_local

  # Recreate the overlay state expected by the stale-cleanup coverage below.
  _link_overlays >/dev/null 2>&1
  # Clean up the override
  rm -f "$OVERLAY_DIR/home/.testrc"

  # Last-wins: two overlays providing the same file
  OVERLAY_BARE2=$(_tmpdir)
  git init --bare "$OVERLAY_BARE2" >/dev/null 2>&1
  OVERLAY_DIR2="$TEST_HOME/.dotfiles-extra"
  dot_fixture_clone_repo "$OVERLAY_BARE2" "$OVERLAY_DIR2"
  mkdir -p "$OVERLAY_DIR2/home"
  echo "extra version" >"$OVERLAY_DIR2/home/.shared_file"
  echo "work version" >"$OVERLAY_DIR/home/.shared_file"
  echo "base last-owner value" >"$TEST_HOME/.last_owner"
  $GIT add .last_owner
  $GIT commit -m "add last-owner fixture" >/dev/null 2>&1
  echo "work last-owner value" >"$OVERLAY_DIR/home/.last_owner"
  echo "extra last-owner value" >"$OVERLAY_DIR2/home/.last_owner"
  cat >"$TEST_HOME/.config/dot/overlays.d/20-extra.conf" <<CONF
url=$OVERLAY_BARE2
CONF
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  # Last overlay (20-extra) should win
  link_target=$(readlink "$TEST_HOME/.shared_file")
  _assert_contains "last-wins: extra overlay wins" ".dotfiles-extra/home" "$link_target"

  # The manifest can contain the same path once per overlay. Its last record is
  # the live owner and must be retained for safe pre-pull restoration.
  rm -f "$OVERLAY_DIR/home/.last_owner" "$OVERLAY_DIR2/home/.last_owner"
  _unstash_overlay_overrides
  _assert_file_content "unstash: last manifest owner restores base content" \
    "base last-owner value" "$TEST_HOME/.last_owner"
  sw_flag=$($GIT ls-files -v .last_owner 2>/dev/null | cut -c1)
  _assert_not_contains "unstash: last manifest owner clears flag" "S" "$sw_flag"
  # Clean up
  rm -f "$TEST_HOME/.config/dot/overlays.d/20-extra.conf"
  rm -f "$OVERLAY_DIR/home/.shared_file"
  rm -rf "$OVERLAY_DIR2" "$OVERLAY_BARE2"

  # Validation: refuse to clobber an untracked real file at the destination.
  echo "untracked user data" >"$TEST_HOME/.untracked_real"
  echo "overlay wants this" >"$OVERLAY_DIR/home/.untracked_real"
  _discover_overlays
  result=$(_link_overlays 2>&1)
  _assert_contains "validate: warns on untracked clobber" "would clobber untracked file" "$result"
  if [[ -L "$TEST_HOME/.untracked_real" ]]; then
    _fail "validate: untracked real file must not be replaced by a symlink"
  else
    _pass "validate: untracked real file left as a regular file"
  fi
  _assert_file_content "validate: untracked content preserved" "untracked user data" "$TEST_HOME/.untracked_real"
  rm -f "$OVERLAY_DIR/home/.untracked_real" "$TEST_HOME/.untracked_real"

  # Validation: refuse to shadow when a real directory is in the way.
  mkdir -p "$TEST_HOME/.dir_in_way"
  echo "keep me" >"$TEST_HOME/.dir_in_way/keep"
  echo "overlay file" >"$OVERLAY_DIR/home/.dir_in_way"
  _discover_overlays
  result=$(_link_overlays 2>&1)
  _assert_contains "validate: warns on directory conflict" "directory in the way" "$result"
  if [[ -d "$TEST_HOME/.dir_in_way" && ! -L "$TEST_HOME/.dir_in_way" ]]; then
    _pass "validate: directory left intact"
  else
    _fail "validate: directory left intact"
  fi
  _assert_file_content "validate: directory contents preserved" "keep me" "$TEST_HOME/.dir_in_way/keep"
  rm -f "$OVERLAY_DIR/home/.dir_in_way"
  rm -rf "$TEST_HOME/.dir_in_way"

  # Validation: a symlink-to-directory destination is repointed, not descended
  # into (the -n / no-dereference guard). Without it, `ln` would create the new
  # link inside the target directory.
  mkdir -p "$TEST_HOME/.real_target_dir"
  ln -s "$TEST_HOME/.real_target_dir" "$TEST_HOME/.symdir_dst"
  echo "overlay file" >"$OVERLAY_DIR/home/.symdir_dst"
  _discover_overlays
  _link_overlays >/dev/null 2>&1
  if [[ -L "$TEST_HOME/.symdir_dst" && "$(readlink "$TEST_HOME/.symdir_dst")" == *".dotfiles-work/home/.symdir_dst" ]]; then
    _pass "validate: symlink-to-dir destination repointed"
  else
    _fail "validate: symlink-to-dir destination repointed (got: $(readlink "$TEST_HOME/.symdir_dst" 2>/dev/null))"
  fi
  if [[ -e "$TEST_HOME/.real_target_dir/.symdir_dst" ]]; then
    _fail "validate: symlink-to-dir must not create an entry inside the target dir"
  else
    _pass "validate: symlink-to-dir left the target dir untouched"
  fi
  rm -f "$OVERLAY_DIR/home/.symdir_dst" "$TEST_HOME/.symdir_dst"
  rm -rf "$TEST_HOME/.real_target_dir"

  # Stale symlink cleanup: remove overlay conf, re-link → symlinks removed
  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.conf"
  _discover_overlays
  result=$(_link_overlays 2>&1)
  _assert_contains "cleanup: removes stale" "Cleaning stale" "$result"
  if [[ ! -L "$TEST_HOME/.testrc_work" ]]; then
    _pass "cleanup: symlink removed"
  else
    _fail "cleanup: symlink removed"
  fi

  # Stale cleanup restores base repo version of shadowed file
  # (.testrc was shadowed by overlay, now overlay is gone)
  if [[ -f "$TEST_HOME/.testrc" && ! -L "$TEST_HOME/.testrc" ]]; then
    _pass "cleanup: base file restored"
    _assert_file_content "cleanup: base content" "base version" "$TEST_HOME/.testrc"
  else
    _fail "cleanup: base file restored"
  fi
  # skip-worktree should be cleared
  sw_flag=$($GIT ls-files -v .testrc 2>/dev/null | cut -c1)
  _assert_not_contains "cleanup: skip-worktree cleared" "S" "$sw_flag"

  # Restore conf for remaining tests
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@example.com:work.git
CONF

  rm -rf "$OVERLAY_DIR" "$OVERLAY_BARE"

  # ---------------------------------------------------------------------------
  # Tests: _merge_overlay_ssh_configs
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Overlay SSH config merge ==="

  SSH_DIR="$TEST_HOME/.ssh"
  SSH_CONFIG="$SSH_DIR/config"
  rm -rf "$SSH_DIR"

  # No .ssh files → no-op
  _merge_overlay_ssh_configs
  if [[ ! -f "$SSH_CONFIG" ]]; then
    _pass "overlay ssh: no .ssh files → no config created"
  else
    _fail "overlay ssh: no .ssh files → no config created"
  fi

  # Create a .ssh file → creates marked block
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host test-alias
  HostName example.com
  User git
  IdentityFile ~/.ssh/test-key
SSH
  _discover_overlays
  _merge_overlay_ssh_configs
  _assert_file_exists "overlay ssh: config created" "$SSH_CONFIG"
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "overlay ssh: host present" "Host test-alias" "$ssh_content"
  _assert_contains "overlay ssh: options present" "HostName example.com" "$ssh_content"
  _assert_contains "overlay ssh: begin marker" "dot-managed:overlay-ssh:10-work begin" "$ssh_content"
  _assert_contains "overlay ssh: end marker" "dot-managed:overlay-ssh:10-work end" "$ssh_content"
  _assert_contains "overlay ssh: DO NOT EDIT" "DO NOT EDIT" "$ssh_content"

  # Idempotent — running again doesn't duplicate
  _merge_overlay_ssh_configs
  count=$(grep -c "^Host test-alias" "$SSH_CONFIG")
  _assert_eq "overlay ssh: idempotent" "1" "$count"

  # Changed block → replaced
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host test-alias
  HostName changed.example.com
  User deploy
  IdentityFile ~/.ssh/new-key
SSH
  _merge_overlay_ssh_configs
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "overlay ssh: updated hostname" "changed.example.com" "$ssh_content"
  _assert_not_contains "overlay ssh: old hostname removed" "HostName example.com" "$ssh_content"
  count=$(grep -c "^Host test-alias" "$SSH_CONFIG")
  _assert_eq "overlay ssh: still one block" "1" "$count"

  # Preserves hand-managed entries above managed blocks
  cat >"$SSH_CONFIG" <<'EXISTING'
Host myserver
  HostName myserver.com
  User me
EXISTING
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host test-alias
  HostName example.com
  User git
SSH
  _merge_overlay_ssh_configs
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "overlay ssh: preserves existing" "Host myserver" "$ssh_content"
  _assert_contains "overlay ssh: adds new" "Host test-alias" "$ssh_content"
  # Hand-managed entries come first (SSH first-match-wins)
  first_host=$(grep -m1 '^Host ' "$SSH_CONFIG")
  _assert_contains "overlay ssh: hand-managed first" "myserver" "$first_host"

  # Permissions
  perms=$(stat -c '%a' "$SSH_CONFIG" 2>/dev/null || stat -f '%Lp' "$SSH_CONFIG" 2>/dev/null)
  _assert_eq "overlay ssh: config is 600" "600" "$perms"

  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.ssh"
  _discover_overlays
  _merge_overlay_ssh_configs
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "overlay ssh: source removal preserves hand-managed entries" \
    "Host myserver" "$ssh_content"
  _assert_not_contains "overlay ssh: source removal prunes managed alias" \
    "Host test-alias" "$ssh_content"
  _assert_not_contains "overlay ssh: source removal prunes managed marker" \
    "dot-managed:overlay-ssh:" "$ssh_content"

  # A filesystem source is controlled outside dot and may change between the
  # preflight inventory and the link loop. Both a vanished entry and a replaced
  # source root must fail closed without publishing a dangling or unvalidated
  # home link.
  source_race_saved_manifest="$DOT_OVERLAY_MANIFEST"
  source_race_saved_legacy="$DOT_OVERLAY_LEGACY_MANIFEST"
  _local_source_inventory_race() {
    local mode="$1"
    local race_root="$TEST_HOME/local source race $mode"
    local race_rel=".filesystem-race-$mode"
    local race_manifest="$TEST_HOME/local-source-race-$mode/dot/overlay-links"
    local race_pending="${race_manifest}.pending"
    local race_find_calls=0 race_rc=0

    mkdir -p "$race_root/home"
    printf '%s\n' "validated source" >"$race_root/home/$race_rel"
    DOT_OVERLAY_MANIFEST="$race_manifest"
    DOT_OVERLAY_LEGACY_MANIFEST="$TEST_HOME/no-local-source-race-legacy-$mode"
    OVERLAYS=("filesystem-race-$mode|$race_root|||||none")

    # shellcheck disable=SC2329  # source validation and inventory call this fixture.
    find() {
      command find "$@"
      if [[ "${1:-}" == "$race_root/home" ]]; then
        race_find_calls=$((race_find_calls + 1))
        if [[ "$race_find_calls" -eq 2 ]]; then
          case "$mode" in
            disappear)
              rm -f "$race_root/home/$race_rel"
              ;;
            replace)
              mv "$race_root/home" "$race_root/home.original"
              mkdir -p "$race_root/home"
              printf '%s\n' "unvalidated replacement" >"$race_root/home/$race_rel"
              ;;
          esac
        fi
      fi
    }
    _link_overlays >/dev/null 2>&1 || race_rc=$?
    unset -f find

    if [[ "$race_rc" -ne 0 ]]; then
      _pass "local source race ($mode): linking fails closed"
    else
      _fail "local source race ($mode): linking fails closed"
    fi
    if [[ ! -e "$TEST_HOME/$race_rel" && ! -L "$TEST_HOME/$race_rel" ]]; then
      _pass "local source race ($mode): no home link is published"
    else
      _fail "local source race ($mode): no home link is published"
    fi
    _assert_file_exists "local source race ($mode): pending authority is retained" \
      "$race_pending"

    rm -f "$TEST_HOME/$race_rel" "$race_manifest" "$race_pending"
    rm -rf "$race_root" "${race_manifest%/dot/overlay-links}"
  }
  _local_source_inventory_race disappear
  _local_source_inventory_race replace
  unset -f _local_source_inventory_race
  DOT_OVERLAY_MANIFEST="$source_race_saved_manifest"
  DOT_OVERLAY_LEGACY_MANIFEST="$source_race_saved_legacy"

  # An earlier overlay can create a symlinked destination parent that points
  # into a later local overlay's source. The later overlay must re-check the
  # physical parent at the mutation boundary instead of trusting the initial
  # all-overlay preflight snapshot.
  parent_overlay_root="$TEST_HOME/parent overlay source"
  child_overlay_root="$TEST_HOME/child overlay source"
  parent_overlay_conf="$TEST_HOME/.config/dot/overlays.d/15-parent.local.conf"
  child_overlay_conf="$TEST_HOME/.config/dot/overlays.d/16-child.local.conf"
  mkdir -p \
    "$parent_overlay_root/home" \
    "$child_overlay_root/home/redirect" \
    "$child_overlay_root/home/.revalidate-parent"
  ln -s "$child_overlay_root/home/redirect" \
    "$parent_overlay_root/home/.revalidate-parent"
  printf '%s\n' "source child" \
    >"$child_overlay_root/home/.revalidate-parent/child"
  cat >"$parent_overlay_conf" <<CONF
sync=none
path=$parent_overlay_root
CONF
  cat >"$child_overlay_conf" <<CONF
sync=none
path=$child_overlay_root
CONF
  _discover_overlays
  if _link_overlays >/dev/null 2>&1; then
    _fail "local mutation boundary: later overlay rejects redirected parent"
  else
    _pass "local mutation boundary: later overlay rejects redirected parent"
  fi
  _assert_file_missing "local mutation boundary: source tree remains unmodified" \
    "$child_overlay_root/home/redirect/child"
  _overlay_pending_manifest_path
  mutation_pending_manifest="$REPLY"
  rm -f \
    "$parent_overlay_conf" \
    "$child_overlay_conf" \
    "$TEST_HOME/.revalidate-parent" \
    "$DOT_OVERLAY_MANIFEST" \
    "$mutation_pending_manifest"

  # The inverse ordering is just as important: a local overlay may first link
  # a parent into its own source, then a later Git overlay may try to write
  # below that parent. Every writer must protect every active local source,
  # regardless of the writer's own synchronization mode.
  earlier_overlay_root="$TEST_HOME/earlier overlay source"
  later_overlay_root="$TEST_HOME/.dotfiles-later"
  later_overlay_origin="$TEST_HOME/later-overlay-origin"
  earlier_overlay_conf="$TEST_HOME/.config/dot/overlays.d/17-earlier.local.conf"
  later_overlay_conf="$TEST_HOME/.config/dot/overlays.d/18-later.conf"
  mkdir -p \
    "$earlier_overlay_root/home/redirect" \
    "$later_overlay_root/home/.revalidate-reverse"
  ln -s "$earlier_overlay_root/home/redirect" \
    "$earlier_overlay_root/home/.revalidate-reverse"
  printf '%s\n' "Git child" \
    >"$later_overlay_root/home/.revalidate-reverse/child"
  git init --bare -q "$later_overlay_origin"
  git init -q "$later_overlay_root"
  git -C "$later_overlay_root" remote add origin "$later_overlay_origin"
  cat >"$earlier_overlay_conf" <<CONF
sync=none
path=$earlier_overlay_root
CONF
  cat >"$later_overlay_conf" <<CONF
url=$later_overlay_origin
CONF
  _discover_overlays
  if _link_overlays >/dev/null 2>&1; then
    _fail "local mutation boundary: later Git overlay rejects earlier source redirect"
  else
    _pass "local mutation boundary: later Git overlay rejects earlier source redirect"
  fi
  if [[ ! -e "$earlier_overlay_root/home/redirect/child" &&
    ! -L "$earlier_overlay_root/home/redirect/child" ]]; then
    _pass "local mutation boundary: earlier source remains unmodified"
  else
    _fail "local mutation boundary: earlier source remains unmodified"
  fi
  _overlay_pending_manifest_path
  mutation_pending_manifest="$REPLY"
  rm -f \
    "$earlier_overlay_conf" \
    "$later_overlay_conf" \
    "$TEST_HOME/.revalidate-reverse" \
    "$DOT_OVERLAY_MANIFEST" \
    "$mutation_pending_manifest"

  # Stale cleanup can restore a tracked leaf that is currently missing. If an
  # active local overlay has redirected its parent into the local source, the
  # restore must fail before Git replaces that parent link and writes through
  # it.
  stale_guard_root="$TEST_HOME/stale guard source"
  stale_guard_conf="$TEST_HOME/.config/dot/overlays.d/19-stale-guard.local.conf"
  stale_guard_rel=".revalidate-stale/child"
  mkdir -p "$TEST_HOME/.revalidate-stale"
  printf '%s\n' "base child" >"$TEST_HOME/$stale_guard_rel"
  $GIT add "$stale_guard_rel"
  $GIT commit -m "add stale restore safety fixture" >/dev/null 2>&1
  $GIT update-index --skip-worktree "$stale_guard_rel"
  rm -rf "$TEST_HOME/.revalidate-stale"
  mkdir -p "$stale_guard_root/home/redirect"
  ln -s "$stale_guard_root/home/redirect" \
    "$stale_guard_root/home/.revalidate-stale"
  cat >"$stale_guard_conf" <<CONF
sync=none
path=$stale_guard_root
CONF
  _overlay_link_target "$stale_guard_rel" retired
  printf '%s\t%s\t%s\n' "$stale_guard_rel" retired "$REPLY" \
    >"$DOT_OVERLAY_MANIFEST"
  chmod 600 "$DOT_OVERLAY_MANIFEST"
  _discover_overlays
  if _link_overlays >/dev/null 2>&1; then
    _fail "local cleanup boundary: unsafe tracked restore fails closed"
  else
    _pass "local cleanup boundary: unsafe tracked restore fails closed"
  fi
  if [[ -L "$TEST_HOME/.revalidate-stale" ]]; then
    _pass "local cleanup boundary: active parent link remains intact"
  else
    _fail "local cleanup boundary: active parent link remains intact"
  fi
  if [[ ! -e "$stale_guard_root/home/redirect/child" &&
    ! -L "$stale_guard_root/home/redirect/child" ]]; then
    _pass "local cleanup boundary: local source remains unmodified"
  else
    _fail "local cleanup boundary: local source remains unmodified"
  fi

  # Clean up
  rm -rf "$SSH_DIR"
  rm -f \
    "$TEST_HOME/.config/dot/overlays.d/10-work.ssh" \
    "$parent_overlay_conf" \
    "$child_overlay_conf" \
    "$earlier_overlay_conf" \
    "$later_overlay_conf" \
    "$stale_guard_conf"
}
