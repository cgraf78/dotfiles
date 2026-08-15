# shellcheck shell=bash
# cron.sh - cron merge and filter coverage.

dot_core_test_cron() {
  echo ""
  echo "=== Cron file install ==="

  # Source the cron merge hook so we can call merge() directly.
  _CRON_HOOK="$REAL_HOME/.local/lib/dot/core/merge-hooks/cron.sh"

  _run_cron_merge() {
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$_CRON_HOOK"
    merge
  }

  dot_fixture_mock_crontab
  mkdir -p \
    "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d" \
    "$TEST_HOME/.config/dot/merge-hooks.d/cron/path.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/path.d/10-defaults.txt" <<'EOF'
$HOME/.local/bin
$HOME/bin
$HOME/.local/share/mise/shims
$HOME/.atuin/bin
$HOME/.cargo/bin
/opt/homebrew/bin
/opt/homebrew/sbin
/usr/local/bin
/usr/local/sbin
/usr/bin
/usr/sbin
/bin
/sbin
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/path.d/20-legacy.pathlist" <<'EOF'
/usr/bin
EOF

  # No cron file → no-op
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_eq "no cron file: crontab empty" "" "$result"

  # Cron file with one entry → installed
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
# comment line
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "installs entry" "dot update --cron" "$result"
  _assert_contains "expands \$HOME" "$TEST_HOME" "$result"
  _assert_contains "injects PATH" "PATH=" "$result"
  _assert_contains "injects user bin before system bin" "PATH=$TEST_HOME/.local/bin" "$result"
  _assert_contains "has begin marker" "dot-managed-cron begin" "$result"
  _assert_contains "has end marker" "dot-managed-cron end" "$result"
  _assert_contains "preserves comments" "comment line" "$result"

  # Idempotent — running again doesn't duplicate
  _run_cron_merge 2>/dev/null
  count=$(crontab -l 2>/dev/null | grep -c "dot update --cron" || true)
  _assert_eq "idempotent: one entry" "1" "$count"

  # Cron file with multiple entries → all installed
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
0 3 * * * $HOME/.local/bin/cleanup
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "multi: dot entry" "dot update --cron" "$result"
  _assert_contains "multi: cleanup entry" "cleanup" "$result"

  # Preserves non-managed cron entries
  echo "0 6 * * * /usr/bin/other-job" | crontab -
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "preserves other jobs" "other-job" "$result"
  _assert_contains "installs managed entry" "dot update --cron" "$result"

  # cron.local entries are merged with cron entries
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron.local" <<'EOF'
0 4 * * * $HOME/.local/bin/backup
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "local: tracked entry present" "dot update --cron" "$result"
  _assert_contains "local: local entry present" "backup" "$result"
  count=$(crontab -l 2>/dev/null | grep -c "dot-managed-cron begin" || true)
  _assert_eq "local: single managed block" "1" "$count"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron.local"

  # cron/cron.d fragments are merged after the base cron file and before cron.local.
  : >"$MOCK_CRONTAB"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
0 1 * * * $HOME/.local/bin/base-cron
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/20-later.cron" <<'EOF'
0 3 * * * $HOME/.local/bin/later-fragment
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-earlier.cron" <<'EOF'
0 2 * * * $HOME/.local/bin/earlier-fragment
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron.local" <<'EOF'
0 4 * * * $HOME/.local/bin/local-cron
EOF
  old_lc_all="${LC_ALL-}"
  old_lc_all_set=0
  [[ ${LC_ALL+x} ]] && old_lc_all_set=1
  LC_ALL=POSIX
  _run_cron_merge 2>/dev/null
  _assert_eq "cron/cron.d: LC_ALL restored after sorting" "POSIX" "${LC_ALL-}"
  if [[ $old_lc_all_set -eq 1 ]]; then
    LC_ALL="$old_lc_all"
  else
    unset LC_ALL
  fi
  result=$(crontab -l 2>/dev/null)
  _assert_contains "cron/cron.d: base entry present" "base-cron" "$result"
  _assert_contains "cron/cron.d: earlier fragment present" "earlier-fragment" "$result"
  _assert_contains "cron/cron.d: later fragment present" "later-fragment" "$result"
  _assert_contains "cron/cron.d: local entry present" "local-cron" "$result"
  python3 - "$result" <<'PY'
import sys

text = sys.argv[1]
order = [
    text.index("base-cron"),
    text.index("earlier-fragment"),
    text.index("later-fragment"),
    text.index("local-cron"),
]
raise SystemExit(0 if order == sorted(order) else 1)
PY
  _assert_eq "cron/cron.d: source order is base, fragments, local" "0" "$?"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron.local"

  # cron/cron.d fragments work without the base cron file so personal overlays can
  # own all active entries on hosts where base only provides the hook.
  : >"$MOCK_CRONTAB"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-only.cron" <<'EOF'
0 2 * * * $HOME/.local/bin/fragment-only
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "cron/cron.d-only: entry installed" "fragment-only" "$result"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"

  # Hidden metadata files are ignored. On macOS especially, accidental .DS_Store
  # files should not be treated as cron source and installed into the crontab.
  : >"$MOCK_CRONTAB"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/.DS_Store" <<'EOF'
this is not cron syntax
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/README" <<'EOF'
this visible documentation file is not cron syntax
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-visible.cron" <<'EOF'
0 2 * * * $HOME/.local/bin/visible-fragment
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "cron/cron.d hidden: visible entry installed" "visible-fragment" "$result"
  _assert_not_contains "cron/cron.d hidden: dotfile ignored" "this is not cron syntax" "$result"
  _assert_not_contains "cron/cron.d hidden: visible non-cron file ignored" \
    "visible documentation file" "$result"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"

  # A .replace group selects one cron policy before parsing. This lets overlays
  # carry mutually-exclusive schedules without the cron hook knowing which
  # environment names, hosts, or repos are involved.
  : >"$MOCK_CRONTAB"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/50-schedule.replace"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/50-schedule.replace/10-loser.cron" <<'EOF'
0 1 * * * $HOME/.local/bin/replaced-cron
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/50-schedule.replace/80-winner.cron" <<'EOF'
0 2 * * * $HOME/.local/bin/selected-cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "cron/cron.d replace: losing fragment skipped" "replaced-cron" "$result"
  _assert_contains "cron/cron.d replace: winning fragment installed" "selected-cron" "$result"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"

  # cron.local alone (no tracked cron file) works
  : >"$MOCK_CRONTAB"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron.local" <<'EOF'
0 5 * * * $HOME/.local/bin/local-only
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "local-only: entry installed" "local-only" "$result"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron.local"

  # Restore cron file for remaining tests
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF

  # Empty cron file strips old managed block
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "pre-remove: entry exists" "dot update --cron" "$result"
  : >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "remove: old entries stripped" "dot update --cron" "$result"
  _assert_not_contains "remove: markers stripped" "dot-managed-cron" "$result"

  # Comments-only cron file installs the comments
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
# descriptive comment
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "comments-only: comment installed" "descriptive comment" "$result"
  _assert_contains "comments-only: markers present" "dot-managed-cron begin" "$result"

  # Empty cron file preserves non-managed entries
  echo "0 6 * * * /usr/bin/other-job" | crontab -
  : >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "empty file: preserves other jobs" "other-job" "$result"

  # ---------------------------------------------------------------------------
  # Tests: cron filter directives
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Cron filter directives ==="

  _current_host=$(hostname -s 2>/dev/null || hostname 2>/dev/null)
  _current_host="${_current_host,,}"
  _current_os=$(uname -s | tr '[:upper:]' '[:lower:]')
  if [[ "$_current_os" == "darwin" ]]; then _current_os="macos"; fi
  _current_user=$(id -un 2>/dev/null || printf '%s' "${USER:-}")

  # Entries before any filter default to all
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
*/30 * * * * $HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter default: entry included" "dot update --cron" "$result"

  # Filter skips non-matching host
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=nonexistent-host-xyz
*/30 * * * * \$HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter host miss: entry skipped" "dot update --cron" "$result"

  # Filter includes matching host
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=$_current_host
*/30 * * * * \$HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter host match: entry included" "dot update --cron" "$result"

  # Filter reset with `# filter: *`
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=nonexistent-host-xyz
0 3 * * * \$HOME/.local/bin/skipped
# filter: *
*/30 * * * * \$HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter reset: filtered entry skipped" "skipped" "$result"
  _assert_contains "filter reset: reset entry included" "dot update --cron" "$result"

  # Platform filtering skips non-matching platform
  : >"$MOCK_CRONTAB"
  if [[ "$_current_os" == "linux" ]]; then
    _wrong_plat="macos"
  else
    _wrong_plat="linux"
  fi
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: platforms=$_wrong_plat
0 3 * * * \$HOME/.local/bin/wrong-platform
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter platform miss: entry skipped" "wrong-platform" "$result"

  # User filtering skips non-matching account
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: users=nonexistent-user-xyz
0 3 * * * \$HOME/.local/bin/wrong-user
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter user miss: entry skipped" "wrong-user" "$result"

  # Filtered-out entries remove an existing managed block
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
0 3 * * * $HOME/.local/bin/remove-when-filtered
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter remove setup: entry installed" "remove-when-filtered" "$result"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<'EOF'
# filter: users=nonexistent-user-xyz
0 3 * * * $HOME/.local/bin/remove-when-filtered
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter remove: old entry stripped" "remove-when-filtered" "$result"
  _assert_not_contains "filter remove: markers stripped" "dot-managed-cron" "$result"

  # User filtering includes matching account
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: users=$_current_user
0 3 * * * \$HOME/.local/bin/right-user
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter user match: entry included" "right-user" "$result"

  # User filtering supports comma-separated include lists
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: users=nonexistent-user-xyz,$_current_user
0 3 * * * \$HOME/.local/bin/user-list-match
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter user list: current user included" "user-list-match" "$result"

  # AND logic: matching host + wrong platform excludes
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=$_current_host platforms=$_wrong_plat
0 3 * * * \$HOME/.local/bin/and-logic
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter AND: right host + wrong platform skipped" "and-logic" "$result"

  # AND logic includes user filters
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=$_current_host users=nonexistent-user-xyz
0 3 * * * \$HOME/.local/bin/host-user-skip
# filter: hosts=$_current_host users=$_current_user
0 4 * * * \$HOME/.local/bin/host-user-keep
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter AND user: right host + wrong user skipped" "host-user-skip" "$result"
  _assert_contains "filter AND user: right host + right user included" "host-user-keep" "$result"

  # Multiple filter directives: each replaces previous
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=nonexistent-host-xyz
0 1 * * * \$HOME/.local/bin/skipped-entry
# filter: hosts=$_current_host
0 2 * * * \$HOME/.local/bin/included-entry
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter replace: first section skipped" "skipped-entry" "$result"
  _assert_contains "filter replace: second section included" "included-entry" "$result"

  # Missing key defaults to * (hosts only → all platforms)
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=$_current_host
*/30 * * * * \$HOME/.local/bin/dot update --cron
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_contains "filter missing key: hosts only, all platforms" "dot update --cron" "$result"

  # cron.local filter state independent from cron
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=nonexistent-host-xyz
0 1 * * * \$HOME/.local/bin/cron-filtered
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron.local" <<'EOF'
0 2 * * * $HOME/.local/bin/local-unfiltered
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter independence: cron entry filtered" "cron-filtered" "$result"
  _assert_contains "filter independence: local entry unfiltered" "local-unfiltered" "$result"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron.local"

  # cron/cron.d filter state is independent per fragment. A restrictive filter in
  # one personal overlay fragment must not leak into the next fragment.
  : >"$MOCK_CRONTAB"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-filtered.cron" <<'EOF'
# filter: users=nonexistent-user-xyz
0 1 * * * $HOME/.local/bin/fragment-filtered
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/20-unfiltered.cron" <<'EOF'
0 2 * * * $HOME/.local/bin/fragment-unfiltered
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter independence: cron/cron.d filtered entry skipped" "fragment-filtered" "$result"
  _assert_contains "filter independence: next cron/cron.d fragment resets" "fragment-unfiltered" "$result"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"

  # cron.local honors its own filter directives
  : >"$MOCK_CRONTAB"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron.local" <<EOF
# filter: users=nonexistent-user-xyz
0 1 * * * \$HOME/.local/bin/local-filtered
# filter: users=$_current_user
0 2 * * * \$HOME/.local/bin/local-included
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter local: non-matching entry skipped" "local-filtered" "$result"
  _assert_contains "filter local: matching entry included" "local-included" "$result"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron.local"

  # Exclude syntax in filter
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: hosts=!$_current_host
0 3 * * * \$HOME/.local/bin/skip-this-host
# filter: hosts=!nonexistent-host-xyz
0 4 * * * \$HOME/.local/bin/keep-this-host
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter exclude: current host excluded" "skip-this-host" "$result"
  _assert_contains "filter exclude: other host not excluded" "keep-this-host" "$result"

  # Exclude syntax works for user filters
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: users=!$_current_user
0 3 * * * \$HOME/.local/bin/skip-this-user
# filter: users=!nonexistent-user-xyz
0 4 * * * \$HOME/.local/bin/keep-this-user
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter exclude: current user excluded" "skip-this-user" "$result"
  _assert_contains "filter exclude: other user not excluded" "keep-this-user" "$result"

  # Mixed user include/exclude filters apply exclusions first
  : >"$MOCK_CRONTAB"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-base.cron" <<EOF
# filter: users=$_current_user,!$_current_user
0 3 * * * \$HOME/.local/bin/mixed-skip-this-user
# filter: users=$_current_user,!nonexistent-user-xyz
0 4 * * * \$HOME/.local/bin/mixed-keep-this-user
EOF
  _run_cron_merge 2>/dev/null
  result=$(crontab -l 2>/dev/null)
  _assert_not_contains "filter user mixed: current user excluded first" "mixed-skip-this-user" "$result"
  _assert_contains "filter user mixed: current user included" "mixed-keep-this-user" "$result"

  echo "=== Agent integration ownership contract ==="

  agent_config_contract=$(
    REAL_HOME="$REAL_HOME" python3 <<'PY'
import json
import pathlib
import sys
import tomllib

root = pathlib.Path(__import__("os").environ["REAL_HOME"])
errors = []

# AgentGuard owns native lifecycle vocabulary and adapter behavior. Dotfiles
# intentionally retains only user policy plus the generic machinery that
# resolves and installs those assets. This negative contract keeps a future
# hook tweak from quietly recreating a second, drifting integration copy here.
config_root = root / ".config/dot/merge-hooks.d"
owned_dirs = [config_root / name for name in ("claude", "codex", "gemini", "muse", "opencode")]
for directory in owned_dirs:
    for path in directory.rglob("*"):
        if not path.is_file() or path.name == "README.md":
            continue
        text = path.read_text(encoding="utf-8")
        if "agent-hook-" in text or "AGENTGUARD_NAME=" in text:
            errors.append(f"{path.relative_to(root)}: contains provider-owned integration code")

for agent in ("claude", "muse"):
    policy = config_root / agent / "settings.d/20-permissions.json"
    if not policy.is_file():
        errors.append(f"{policy.relative_to(root)}: missing local permission policy")
        continue
    with policy.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if "permissions" not in data or "hooks" in data:
        errors.append(f"{policy.relative_to(root)}: must contain permissions without hooks")

codex_config = root / ".config/dot/merge-hooks.d/codex/config.d/10-settings.toml"
with codex_config.open("rb") as f:
    codex_data = tomllib.load(f)
if codex_data.get("features", {}).get("hooks") is not None or "hooks" in codex_data:
    errors.append(f"{codex_config.relative_to(root)}: contains provider-owned hook config")

# Bare Codex follows each machine's local model state. Deliberate model policy
# belongs only in explicitly selected profile overlays, not the shared base.
base_model_policy = {
    "model",
    "model_provider",
    "model_reasoning_effort",
    "model_reasoning_summary",
    "model_verbosity",
    "service_tier",
}
managed_model_policy = sorted(base_model_policy.intersection(codex_data))
if managed_model_policy:
    errors.append(
        f"{codex_config.relative_to(root)}: contains base model policy: "
        + ", ".join(managed_model_policy)
    )

gemini_json = list((config_root / "gemini/settings.d").glob("*.json"))
if gemini_json:
    errors.append("gemini/settings.d: local JSON integration fragment remains")

opencode_adapter = config_root / "opencode/agentguard.js"
if opencode_adapter.exists():
    errors.append(f"{opencode_adapter.relative_to(root)}: provider adapter remains in dotfiles")

if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
  )
  _assert_eq "agent integration ownership: dotfiles contains policy, not adapters" \
    "" "$agent_config_contract"
}
