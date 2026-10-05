# shellcheck shell=bash
# doctor.sh - always-active dotfiles doctor extension coverage.

dot_core_test_doctor() {
  local result expected doctor_bin doctor_crontab_log doctor_direct_tool
  local doctor_no_crontab_bin doctor_account_home_status doctor_account_scope_home
  local doctor_account_scope_status doctor_account_scope_command
  local doctor_termux_account_status doctor_termux_account_home
  local doctor_account_spoof_home doctor_account_spoof_bin
  local doctor_account_hash_spoof_status doctor_account_command_spoof_status
  local integ_home integ_bin integ_nz_bin integ_bare integ_poison
  local integ_poison_result integ_saved_home integ_saved_path
  local integ_shdeps_bin_unset integ_saved_shdeps_bin
  local integ_shdeps_dir_unset integ_saved_shdeps_dir
  local integ_healthy integ_missing integ_broken integ_noresolve integ_nozsh
  local integ_bare_result integ_healthy_status integ_bare_status
  local doctor_conf_home doctor_grok_home doctor_cron_file doctor_health_log
  local doctor_startup doctor_mc_home doctor_shell_status doctor_shell_err
  local doctor_nozsh_bin doctor_tool doctor_tool_path doctor_cron_status
  local doctor_oldbash_bin doctor_mode doctor_started doctor_status doctor_i
  local doctor_timeout_bin doctor_strays doctor_stray_pid doctor_deadline
  local doctor_held doctor_free doctor_try doctor_expect doctor_tmp
  local doctor_yq_log doctor_frag doctor_mc_state

  echo ""
  echo "=== Base doctor extensions ==="

  # The standalone suite owns core runtime/repository/overlay health. This
  # retained suite loads only the public extension API and client policy.
  # The versioned runtime keeps no engine health modules, and nothing below
  # calls them, so skip the legacy loader when it is absent.
  if declare -F _dot_doctor_load >/dev/null 2>&1; then
    _dot_doctor_load
  fi
  _test_load_dot_doctor_api "$TEST_HOME"
  # The list helpers are newer than some Dot releases this suite runs
  # against: default to the older API, and opt in per case with stubs.
  unset -f dot_doctor_item dot_doctor_hint
  # Print the live processes in this shell's process group that are neither
  # this shell nor its descendants, one PID per line, sorted: what a helper
  # leaves behind once its parent is gone. Orphans are re-parented away
  # from $$, so the parent walk tells them from work still in progress.
  _doctor_group_strays() {
    local group
    group=$(ps -o pgid= -p "$$" 2>/dev/null) || return 0
    ps -A -o pid=,ppid=,pgid=,stat= 2>/dev/null |
      awk -v self="$$" -v group="${group//[[:space:]]/}" '
        { parent[$1] = $2; pgid[$1] = $3; state[$1] = $4 }
        END {
          for (pid in pgid) {
            if (pgid[pid] != group || state[pid] ~ /^Z/ || pid == self) continue
            mine = 0
            for (up = parent[pid]; up in parent && up > 1; up = parent[up]) {
              if (up == self) { mine = 1; break }
            }
            if (!mine) print pid
          }
        }' | sort
  }
  # Succeed once PID is gone or a zombie, polling for up to two seconds: a
  # SIGKILLed process dies asynchronously, and an orphan's zombie waits for
  # whichever ancestor adopted it.
  _doctor_wait_gone() {
    local state tries
    for ((tries = 0; tries < 40; tries++)); do
      state=$(ps -o stat= -p "$1" 2>/dev/null) || return 0
      [[ -n ${state//[[:space:]]/} && $state != *Z* ]] || return 0
      sleep 0.05
    done
    return 1
  }
  _doctor_records() {
    local status=0
    : >"$DOT_DOCTOR_RESULT_FILE"
    "$@" || status=$?
    cat "$DOT_DOCTOR_RESULT_FILE"
    return "$status"
  }

  REPLY=
  doctor_account_home_status=0
  _dr_account_home || doctor_account_home_status=$?
  doctor_account_scope_home=$REPLY
  _assert_eq "doctor account scope: account HOME resolves" \
    "0" "$doctor_account_home_status"

  doctor_termux_account_status=0
  doctor_termux_account_home=$(dot_fixture_termux_account_home \
    "$REAL_HOME/.local/lib/dotfiles/doctor.d/lib/compat.sh" \
    _dr_account_home) || doctor_termux_account_status=$?
  if [[ "$doctor_termux_account_status" -eq 77 ]]; then
    echo "  - skipping doctor Termux account HOME check (mount namespace unavailable)"
  else
    _assert_eq "doctor account scope: Termux account HOME resolves" \
      "0" "$doctor_termux_account_status"
    _assert_eq "doctor account scope: Termux uses the fixed application HOME" \
      "/data/data/com.termux/files/home" "$doctor_termux_account_home"
  fi

  doctor_account_scope_status=0
  doctor_account_scope_command=$(
    env BASH_ENV='' HOME="$doctor_account_scope_home" DOT_TEST=0 \
      bash -s -- "$REAL_HOME/.local/lib/dotfiles/doctor.d/lib/compat.sh" <<'BASH'
dot_doctor_source() { return 0; }
dot_doctor_skip() { :; }
. "$1" || exit
_dr_account_scoped_command "account scope test" id "" || exit
printf '%s' "$REPLY"
BASH
  ) || doctor_account_scope_status=$?
  _assert_eq "doctor account scope: actual account HOME is accepted" \
    "0" "$doctor_account_scope_status"
  if [[ -n "$doctor_account_scope_command" && -x "$doctor_account_scope_command" ]]; then
    _pass "doctor account scope: production command resolves from PATH"
  else
    _fail "doctor account scope: production command resolves from PATH"
  fi

  doctor_account_spoof_home=$(_tmpdir)
  doctor_account_spoof_bin=$(_tmpdir)
  cat >"$doctor_account_spoof_bin/getent" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "passwd" && -n "${2:-}" ]] || exit 1
printf '%s:x:1:1::%s:/bin/sh\n' "$2" "$ACCOUNT_SPOOF_HOME"
SH
  chmod +x "$doctor_account_spoof_bin/getent"

  doctor_account_hash_spoof_status=0
  env BASH_ENV='' HOME="$doctor_account_spoof_home" DOT_TEST=0 \
    PATH="$doctor_account_spoof_bin:$PATH" \
    ACCOUNT_SPOOF_GETENT="$doctor_account_spoof_bin/getent" \
    ACCOUNT_SPOOF_HOME="$doctor_account_spoof_home" \
    bash -s -- "$REAL_HOME/.local/lib/dotfiles/doctor.d/lib/compat.sh" <<'BASH' || doctor_account_hash_spoof_status=$?
hash -p "$ACCOUNT_SPOOF_GETENT" getent
dot_doctor_source() { return 0; }
dot_doctor_skip() { :; }
. "$1" || exit
if _dr_account_scoped_command "account scope spoof" id ""; then
  exit 1
fi
BASH
  _assert_eq "doctor account scope: command hash cannot authorize a synthetic HOME" \
    "0" "$doctor_account_hash_spoof_status"

  doctor_account_command_spoof_status=0
  env BASH_ENV='' HOME="$doctor_account_spoof_home" DOT_TEST=0 \
    PATH="$doctor_account_spoof_bin:$PATH" \
    ACCOUNT_SPOOF_GETENT="$doctor_account_spoof_bin/getent" \
    ACCOUNT_SPOOF_HOME="$doctor_account_spoof_home" \
    bash -s -- "$REAL_HOME/.local/lib/dotfiles/doctor.d/lib/compat.sh" <<'BASH' || doctor_account_command_spoof_status=$?
# shellcheck disable=SC2329 # Invoked by the account resolver under test.
command() {
  if [[ "${1:-}" == "-p" && "${2:-}" == "getent" ]]; then
    shift 2
    "$ACCOUNT_SPOOF_GETENT" "$@"
    return
  fi
  builtin command "$@"
}
dot_doctor_source() { return 0; }
dot_doctor_skip() { :; }
. "$1" || exit
if _dr_account_scoped_command "account scope spoof" id ""; then
  exit 1
fi
BASH
  _assert_eq "doctor account scope: command function cannot authorize a synthetic HOME" \
    "0" "$doctor_account_command_spoof_status"

  doctor_bin=$(_tmpdir)
  mkdir -p "$doctor_bin" "$TEST_HOME/.config/opencode/plugins"
  cat >"$doctor_bin/opencode" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$doctor_bin/opencode"

  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d"
  printf '%s\n' '*/30 * * * * dot update --cron --force' \
    >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron"
  doctor_crontab_log=$(_tmpfile)
  cat >"$doctor_bin/crontab" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOT_TEST_CRONTAB_LOG"
printf '%s\n' '*/30 * * * * dot update --cron --force'
SH
  chmod +x "$doctor_bin/crontab"

  : >"$doctor_crontab_log"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_eq "doctor cron: test mode requires an explicit double" \
    "" "$(cat "$doctor_crontab_log")"
  _assert_contains "doctor cron: missing test double is reported" \
    "test crontab" "$result"

  : >"$doctor_crontab_log"
  result=$(DOT_TEST=0 HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_eq "doctor cron: non-account HOME skips the account crontab" \
    "" "$(cat "$doctor_crontab_log")"
  _assert_contains "doctor cron: non-account HOME is reported" \
    "account home" "$result"

  doctor_no_crontab_bin=$(_tmpdir)
  # Everything the cron renderer needs, but no crontab.
  for doctor_tool in cat id uname hostname realpath dirname basename mktemp rm \
    mv mkdir chmod sort tr sed awk date stat; do
    doctor_tool_path=$(type -P "$doctor_tool" 2>/dev/null) || continue
    ln -s "$doctor_tool_path" "$doctor_no_crontab_bin/$doctor_tool"
  done
  result=$(
    # shellcheck disable=SC2329 # Invoked indirectly by the Cron doctor check.
    _dr_account_home() {
      # shellcheck disable=SC2030 # A stub for this subshell only.
      REPLY=$HOME
    }
    DOT_TEST=0 HOME="$TEST_HOME" PATH="$doctor_no_crontab_bin" \
      _doctor_records _dr_check_cron
  )
  _assert_contains "doctor cron: missing crontab warns when entries apply" \
    $'warn\tcrontab not found' "$result"

  : >"$doctor_crontab_log"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_eq "doctor cron: explicit test double is invoked" \
    "-l" "$(cat "$doctor_crontab_log")"
  _assert_contains "doctor cron: an uninstalled tracked entry is missing" \
    $'warn\tmanaged cron block missing' "$result"
  _assert_contains "doctor cron: the missing row points at the update log" \
    "update.log" "$result"

  # crontab exits 1 both when the account has no crontab yet and when it
  # may not use crontab at all; only the second must not say "run 'dot
  # update'", which would fail the same way.
  cat >"$doctor_bin/crontab-refused" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOT_TEST_CRONTAB_LOG"
printf '%s\n' 'You (tester) are not allowed to use this program (crontab)' \
  'See crontab(1) for more information' >&2
exit 1
SH
  cat >"$doctor_bin/crontab-none" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'no crontab for tester' >&2
exit 1
SH
  cat >"$doctor_bin/crontab-busybox-none" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "crontab: can't open 'tester': No such file or directory" >&2
exit 1
SH
  cat >"$doctor_bin/crontab-silent-fail" <<'SH'
#!/usr/bin/env bash
exit 3
SH
  chmod +x "$doctor_bin"/crontab-refused "$doctor_bin"/crontab-none \
    "$doctor_bin"/crontab-busybox-none "$doctor_bin"/crontab-silent-fail
  : >"$doctor_crontab_log"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-refused" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_eq "doctor cron: a refused crontab runs once" \
    "-l" "$(cat "$doctor_crontab_log")"
  _assert_contains "doctor cron: a refused crontab names crontab's own reason" \
    $'warn\tcrontab is not usable by this account\tYou (tester) are not allowed to use this program (crontab); ask an administrator to allow crontab for this account (cron.allow or cron.deny, PAM, its setuid/setgid bit), then run \'dot update\'' \
    "$result"
  _assert_not_contains "doctor cron: a refused crontab is not a missing block" \
    "managed cron block missing" "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the check under test.
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
      DOT_TEST_CRONTAB="$doctor_bin/crontab-refused" \
      DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
      _doctor_records _dr_check_cron
  )
  _assert_contains "doctor cron: a newer Dot gets the refusal's step on its own line" \
    "$(printf '%s\n' $'warn\tcrontab is not usable by this account\tYou (tester) are not allowed to use this program (crontab)' \
      $'hint\task an administrator to allow crontab for this account (cron.allow or cron.deny, PAM, its setuid/setgid bit), then run \'dot update\'\t')" \
    "$result"
  # Doctor workers may run under errexit; the failing listing must not end
  # the check before it files its row.
  # (_doctor_records would call it under ||, where errexit is off.)
  result=$(
    set -e
    : >"$DOT_DOCTOR_RESULT_FILE"
    HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
      DOT_TEST_CRONTAB="$doctor_bin/crontab-refused" \
      DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
      _dr_check_cron
    cat "$DOT_DOCTOR_RESULT_FILE"
  )
  _assert_contains "doctor cron: a refused crontab is reported under errexit" \
    $'warn\tcrontab is not usable by this account' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-silent-fail" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a silent crontab failure names its status" \
    $'warn\tcrontab is not usable by this account\tcrontab -l exited 3; ' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-none" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: no crontab yet is a missing block" \
    $'warn\tmanaged cron block missing' "$result"
  _assert_not_contains "doctor cron: no crontab yet is not a refusal" \
    "not usable" "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-busybox-none" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: BusyBox's no crontab yet is a missing block" \
    $'warn\tmanaged cron block missing' "$result"
  # A refusal matters only when there is something to install.
  doctor_tmp=$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron
  printf '%s\n' '# filter: hosts=doctor-no-such-host' \
    '*/30 * * * * dot update --cron --force' >"$doctor_tmp"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-refused" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a refusal with nothing to install stays quiet" \
    $'ok\tno tracked cron entries apply to this host' "$result"
  printf '%s\n' '*/30 * * * * dot update --cron --force' >"$doctor_tmp"

  # Install the managed block with the real cron merge hook, then compare:
  # the doctor renders through that same hook, so a fresh install is current
  # and any tracked edit since is stale.
  doctor_cron_file=$(_tmpfile)
  cat >"$doctor_bin/crontab-file" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  -l) cat "$DOT_TEST_CRONTAB_FILE" ;;
  -) cat >"$DOT_TEST_CRONTAB_FILE" ;;
  -r) : >"$DOT_TEST_CRONTAB_FILE" ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$doctor_bin/crontab-file"
  : >"$doctor_cron_file"
  _doctor_cron_install() {
    _dr_hook_runtime_source || return 1
    dot_hook_source merge-hooks.d/cron.sh || return 1
    merge >/dev/null 2>&1
  }
  (
    HOME=$TEST_HOME PATH="$doctor_bin:$PATH" \
      DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
      DOT_TEST_CRONTAB_FILE="$doctor_cron_file" _doctor_cron_install
  ) || _fail "doctor cron: fixture install through the merge hook"
  _assert_contains "doctor cron: fixture install wrote the managed block" \
    "# dot-managed-cron begin" "$(cat "$doctor_cron_file")"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a fresh install is current" \
    $'ok\tmanaged cron block is current' "$result"
  # The listing keeps crontab's stdout and stderr apart from one run. Each
  # case prints the status, then what was listed (REPLY) or the message.
  cat >"$doctor_bin/crontab-noisy" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'crontab: a warning on stderr' >&2
printf '%s\n\n\n' 'SHELL=/bin/sh' '0 4 * * * true'
SH
  chmod +x "$doctor_bin/crontab-noisy"
  # shellcheck disable=SC2031 # _cron_list sets REPLY in this shell.
  _doctor_cron_list() {
    local status=0
    DOT_TEST_CRONTAB_LOG=$doctor_crontab_log _cron_list "$1" || status=$?
    printf '%s|%s|%s' "$status" "$REPLY" "$_CRON_LIST_ERR"
  }
  _assert_eq "doctor cron: stderr stays out of a listing, trailing newlines go" \
    $'0|SHELL=/bin/sh\n\n\n0 4 * * * true|crontab: a warning on stderr' \
    "$(_doctor_cron_list "$doctor_bin/crontab-noisy")"
  _assert_eq "doctor cron: no crontab yet lists nothing, as status 1" \
    "1||no crontab for tester" "$(_doctor_cron_list "$doctor_bin/crontab-none")"
  _assert_eq "doctor cron: a refusal is status 2 with its message's first line" \
    "2||You (tester) are not allowed to use this program (crontab)" \
    "$(_doctor_cron_list "$doctor_bin/crontab-refused")"
  # A crontab that cannot run says "No such file or directory" too, but
  # not with status 1; dot update could not install the block either.
  printf '#!%s\n' "$TEST_HOME/no-such-interpreter" >"$doctor_bin/crontab-bad-interpreter"
  chmod +x "$doctor_bin/crontab-bad-interpreter"
  _assert_eq "doctor cron: a crontab that cannot run is unusable" \
    "2" "$(_doctor_cron_list "$doctor_bin/crontab-bad-interpreter" | cut -d'|' -f1)"
  # A failed listing is not judged, even when crontab printed something.
  cat >"$doctor_bin/crontab-partial" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '# dot-managed-cron begin'
printf '\n%s\n' 'crontab: read error' >&2
exit 4
SH
  chmod +x "$doctor_bin/crontab-partial"
  _assert_eq "doctor cron: a failed listing is empty and names its first message line" \
    "2||crontab: read error" "$(_doctor_cron_list "$doctor_bin/crontab-partial")"
  unset -f _doctor_cron_list
  printf '%s\n' '0 4 * * * echo nightly' \
    >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/20-nightly.cron"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a tracked edit makes the block stale" \
    $'warn\tmanaged cron block is stale' "$result"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/20-nightly.cron"

  # A crontab-wide SHELL runs every job; a missing program fails them all.
  printf '%s\n' "SHELL=$doctor_bin/crontab-file" >>"$doctor_cron_file"
  printf '%s\n' "SHELL=$TEST_HOME/missing-cron-shell" >>"$doctor_cron_file"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: an executable SHELL passes" \
    $'ok\tcron SHELL is executable' "$result"
  _assert_contains "doctor cron: a missing SHELL fails" \
    $'fail\tcron SHELL is not executable: ~/missing-cron-shell' "$result"
  _assert_not_contains "doctor cron: core's update-outcome row is not duplicated" \
    "auto-update cron entry present" "$result"
  result=$(
    _doctor_records _dr_cron_check_shell "SHELL='$doctor_bin/crontab-file'"$'\n'"SHELL=bash"
  )
  _assert_contains "doctor cron: a quoted SHELL is unquoted like cron does" \
    $'ok\tcron SHELL is executable' "$result"
  _assert_contains "doctor cron: a relative SHELL fails" \
    $'fail\tcron SHELL is not an absolute path: bash' "$result"

  # Managed jobs must name a program cron can start, judged by stat on the
  # PATH cron gives each job: the last PATH= line above it, or cron's
  # default /usr/bin:/bin.
  mkdir -p "$TEST_HOME/cron-bin"
  printf '%s\n' '#!/bin/sh' >"$TEST_HOME/cron-bin/cron-tool"
  chmod +x "$TEST_HOME/cron-bin/cron-tool"
  printf '%s\n' '#!/bin/sh' >"$TEST_HOME/cron-bin/not-exec"
  # shellcheck disable=SC2016 # Job lines carry literal shell syntax.
  result=$(HOME="$TEST_HOME" _doctor_records _dr_cron_check_commands "$(printf '%s\n' \
    '* * * * * outside-block-tool' \
    '# dot-managed-cron begin' \
    '# DO NOT EDIT' \
    "PATH=$TEST_HOME/cron-bin" \
    '' \
    'SHELL=/bin/sh' \
    '*/30 * * * * cron-tool --flag' \
    '@reboot DOT_X=1 OTHER=2 cron-tool' \
    "0 4 * * * $TEST_HOME/cron-bin/cron-tool >>log 2>&1" \
    '0 4 * * * cron-bin/cron-tool' \
    '0 4 * * * ~/cron-bin/cron-tool' \
    '0 4 * * * cd /tmp && anything' \
    '0 4 * * * "$HOME/quoted" arg' \
    '0 4 * * * $(which thing)' \
    '0 4 * * * missing-tool --now' \
    "0 5 * * * $TEST_HOME/cron-bin/not-exec" \
    '# dot-managed-cron end' \
    '* * * * * also-outside')" '# dot-managed-cron')
  # shellcheck disable=SC2088 # Rows carry tilde display paths.
  _assert_eq "doctor cron: jobs that cannot start are listed" \
    $'warn\t2 managed cron job(s) cannot start\tmissing-tool is not on the job\'s PATH; ~/cron-bin/not-exec is not an executable file; install the program or fix its entry under ~/.config/dot/merge-hooks.d/cron/cron.d, then run \'dot update\'' \
    "$result"
  result=$(HOME="$TEST_HOME" _doctor_records _dr_cron_check_commands "$(printf '%s\n' \
    '# dot-managed-cron begin' '0 4 * * * sh -c true' '0 4 * * * cron-tool' \
    '# dot-managed-cron end')" '# dot-managed-cron')
  _assert_contains "doctor cron: without PATH= cron's default PATH applies" \
    $'warn\t1 managed cron job(s) cannot start\tcron-tool is not on the job\'s PATH' "$result"
  result=$(HOME="$TEST_HOME" _doctor_records _dr_cron_check_commands "$(printf '%s\n' \
    "PATH=\"$TEST_HOME/cron-bin\"" '# dot-managed-cron begin' '0 4 * * * cron-tool' \
    '# dot-managed-cron end')" '# dot-managed-cron')
  _assert_eq "doctor cron: a quoted PATH above the block applies to it" "" "$result"
  result=$(HOME="$TEST_HOME/cron-bin" _doctor_records _dr_cron_check_commands "$(printf '%s\n' \
    '# dot-managed-cron begin' "PATH=$TEST_HOME/no-such-dir:" '0 4 * * * cron-tool' \
    '# dot-managed-cron end')" '# dot-managed-cron')
  _assert_eq "doctor cron: a trailing empty PATH entry searches HOME" "" "$result"

  # A host filter that excludes every entry: the hook removes the block,
  # and the doctor agrees there is nothing to install.
  printf '%s\n' '# filter: hosts=no-such-host' '*/30 * * * * dot update --cron --force' \
    >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a block no entry applies to is stale" \
    $'warn\tmanaged cron block is stale\tno tracked entry applies' "$result"
  (
    HOME=$TEST_HOME PATH="$doctor_bin:$PATH" \
      DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
      DOT_TEST_CRONTAB_FILE="$doctor_cron_file" _doctor_cron_install
  ) || _fail "doctor cron: fixture strip through the merge hook"
  _assert_not_contains "doctor cron: the hook strips a block no entry applies to" \
    "dot-managed-cron begin" "$(cat "$doctor_cron_file")"
  _assert_not_contains "doctor cron: the strip leaves no stray REPLY text" \
    "no-such-host" "$(cat "$doctor_cron_file")"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: nothing to install is ok" \
    $'ok\tno tracked cron entries apply to this host' "$result"
  printf '%s\n' '*/30 * * * * dot update --cron --force' \
    >"$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron"

  # With no tracked source at all the hook leaves an old block alone, so
  # the doctor must not promise that `dot update` removes it.
  (
    HOME=$TEST_HOME PATH="$doctor_bin:$PATH" \
      DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
      DOT_TEST_CRONTAB_FILE="$doctor_cron_file" _doctor_cron_install
  ) || _fail "doctor cron: fixture reinstall through the merge hook"
  mv "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron" \
    "$TEST_HOME/10-update.cron.off"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab-file" \
    DOT_TEST_CRONTAB_FILE="$doctor_cron_file" \
    _doctor_records _dr_check_cron)
  _assert_contains "doctor cron: a sourceless stale block names the manual fix" \
    "dot update keeps the old block; remove it with 'crontab -e'" "$result"
  mv "$TEST_HOME/10-update.cron.off" \
    "$TEST_HOME/.config/dot/merge-hooks.d/cron/cron.d/10-update.cron"
  unset -f _doctor_cron_install

  doctor_cron_status=0
  result=$(_doctor_records _dr_cron_check_shell $'SHELL=/no\tsuch-shell') ||
    doctor_cron_status=$?
  _assert_exit "doctor cron: a TAB in SHELL cannot abort the check" 0 "$doctor_cron_status"
  _assert_contains "doctor cron: a TAB in SHELL is displayed as a space" \
    $'fail\tcron SHELL is not executable: /no such-shell' "$result"

  cat >"$doctor_bin/shdeps" <<'SH'
#!/usr/bin/env bash
case ${1:-} in
  version) printf '%s\n' 'shdeps 0.0-test' ;;
  dep-links)
    case ${2:-} in
      cgraf78/emptydep) exit 0 ;;
      cgraf78/malformeddep) printf '%s\t%s\n' bad-row missing-target ;;
      cgraf78/directdep)
        printf '%s\t%s\t%s\n' direct-tool "$DOCTOR_DIRECT_TOOL" "$DOCTOR_DIRECT_TOOL"
        ;;
      *) exit 1 ;;
    esac
    ;;
  health)
    printf '%s\n' "${SHDEPS_CONF_DIR:-unset}" >>"${DOCTOR_HEALTH_LOG:-/dev/null}"
    case ${DOCTOR_HEALTH_MODE:-} in
      ok) exit 0 ;;
      warn)
        printf 'warn\tjdx/mise\tdangling-link\t%s\tremove it or run shdeps update\n' \
          "$HOME/.local/share/man/man1/mise.1"
        printf 'warn\t-\tdeferred-post\t-\trun shdeps update interactively\n'
        exit 1
        ;;
      fail)
        printf 'warn\tjdx/mise\tdangling-link\t-\tremove it\n'
        printf 'fail\tcgraf78/ds\tnot-executable\t%s\tchmod +x it\n' "$HOME/.local/bin/ds"
        exit 1
        ;;
      # Warnings first, as shdeps sorts by package, then a failure that a
      # sample of the first rows would hide.
      failfirst)
        printf 'warn\taaa/one\tdangling-link\t-\tremove it\n'
        printf 'warn\taaa/two\tdangling-link\t-\tremove it\n'
        printf 'warn\taaa/three\tdangling-link\t-\tremove it\n'
        printf 'warn\taaa/four\tdangling-link\t-\tremove it\n'
        printf 'fail\tzzz/last\tblocked-transition\t%s\tmove the record aside, then run dot update\n' \
          "$HOME/.local/state/shdeps/zzz.transition"
        exit 1
        ;;
      # An older shdeps repeated a blocked record's path in the detail.
      duppath)
        printf 'fail\tzzz/last\tblocked-transition\t%s\tremove the stale transition record at %s and retry\n' \
          "$HOME/.local/state/shdeps/zzz.json" "$HOME/.local/state/shdeps/zzz.json"
        exit 1
        ;;
      # A severity and kind this doctor has never heard of.
      future)
        printf 'notice\tnew/pkg\tfuture-kind\t-\tsomething new; do this\n'
        exit 1
        ;;
      empty1) exit 1 ;;
      incomplete)
        printf 'fail\t-\tunreadable-state\t-\tcheck permissions\n'
        exit 3
        ;;
      crash) exit 139 ;;
      # Really hang, as one process, so a deadline that fails to fire shows.
      hang) exec sleep 47 ;;
      gone) exit 127 ;;
      incomplete-empty) exit 3 ;;
      *)
        # Older shdeps: `health` is an unknown command.
        printf '%s\n' "error: unknown command 'health'" >&2
        exit 2
        ;;
    esac
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$doctor_bin/shdeps"
  doctor_direct_tool="$TEST_HOME/.local/bin/direct-tool"
  mkdir -p "$TEST_HOME/.local/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$doctor_direct_tool"
  chmod +x "$doctor_direct_tool"

  result=$(PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn emptydep)
  _assert_contains "doctor tools: empty dependency links are reported" \
    "emptydep bin links missing" "$result"
  result=$(PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn malformeddep)
  _assert_contains "doctor tools: malformed dependency links are reported" \
    "malformeddep bin links malformed" "$result"
  result=$(DOCTOR_DIRECT_TOOL="$doctor_direct_tool" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn directdep)
  _assert_contains "doctor tools: direct executable targets are accepted" \
    "directdep bin links" "$result"
  _assert_not_contains "doctor tools: direct targets are not forced to symlinks" \
    "direct-tool not linked" "$result"

  # shdeps health: one row for every installed package when the command
  # exists, the per-group link rows only on an older shdeps without it.
  unset _DR_SHDEPS_HEALTH_STATUS _DR_SHDEPS_HEALTH_OUTPUT
  doctor_health_log=$(_tmpfile)
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" _doctor_records _dr_check_tools)
  _assert_contains "doctor health: an older shdeps is a warning with the fix" \
    $'warn\tshdeps health unchecked\tthe installed shdeps cannot run \'shdeps health\'; run \'dot update\' to upgrade it' \
    "$result"
  _assert_not_contains "doctor health: an older shdeps gets no per-group rows" \
    "bin links" "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_no_crontab_bin" _doctor_records _dr_check_tools)
  _assert_contains "doctor health: no shdeps on PATH is a warning with the fix" \
    $'warn\tshdeps health unchecked\tshdeps is not on PATH; run \'dot update\'' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=ok \
    DOCTOR_HEALTH_LOG="$doctor_health_log" _doctor_records _dr_check_tools)
  _assert_contains "doctor health: a healthy report is one ok row" \
    $'ok\tshdeps health' "$result"
  _assert_not_contains "doctor health: per-tool link rows are gone" \
    "bin links" "$result"
  _assert_eq "doctor health: the dotfiles config dir is passed explicitly" \
    "$TEST_HOME/.config/shdeps" "$(cat "$doctor_health_log")"
  result=$(DOCTOR_DIRECT_TOOL="$doctor_direct_tool" PATH="$doctor_bin:$PATH" \
    DOCTOR_HEALTH_MODE=ok _doctor_records _dr_check_shdeps_bin_group warn directdep)
  _assert_eq "doctor health: the shared group check stands down" "" "$result"
  result=$(DOCTOR_DIRECT_TOOL="$doctor_direct_tool" PATH="$doctor_bin:$PATH" \
    DOCTOR_HEALTH_MODE=crash _doctor_records _dr_check_shdeps_bin_group warn directdep)
  _assert_eq "doctor health: a failing health command still covers groups" "" "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=warn \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: warn rows give one warning" \
    $'warn\tshdeps health: 2 problem(s)' "$result"
  _assert_contains "doctor health: problems carry display paths and shdeps' fix" \
    "jdx/mise: dangling-link ~/.local/share/man/man1/mise.1 — remove it or run shdeps update" \
    "$result"
  _assert_contains "doctor health: packageless rows render without a placeholder" \
    "; deferred-post — run shdeps update interactively" "$result"
  _assert_contains "doctor health: the row ends with the next step" \
    "follow the fix on each line; 'shdeps health' lists them all" "$result"
  # A failure sorted after four warnings is listed first, not folded into
  # "and N more" on a Dot without list items.
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=failfirst \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: a failure among warnings fails the row" \
    $'fail\tshdeps health: 5 problem(s), 1 failing\tzzz/last: blocked-transition ~/.local/state/shdeps/zzz.transition — move the record aside, then run dot update; aaa/one' \
    "$result"
  _assert_contains "doctor health: the rest fold behind the sample" \
    "; and 2 more; follow the fix" "$result"
  # With the list helpers, every problem is an item, failures first, and
  # the next step is a hint.
  result=$(
    # shellcheck disable=SC2329 # Probed by the check under test.
    dot_doctor_item() { _dot_doctor_record item "$1"; }
    # shellcheck disable=SC2329
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=failfirst \
      _doctor_records _dr_check_tools
  )
  _assert_eq "doctor health: list helpers get one item per problem, failures first" \
    "$(printf '%s\n' $'section\tTools\t' \
      $'fail\tshdeps health: 5 problem(s), 1 failing\t' \
      $'item\tzzz/last: blocked-transition ~/.local/state/shdeps/zzz.transition — move the record aside, then run dot update\t' \
      $'item\taaa/one: dangling-link — remove it\t' \
      $'item\taaa/two: dangling-link — remove it\t' \
      $'item\taaa/three: dangling-link — remove it\t' \
      $'item\taaa/four: dangling-link — remove it\t' \
      $'hint\tfollow the fix on each line; \'shdeps health\' lists them all\t')" \
    "$result"
  # The path column stays when the detail only names a longer path that
  # starts or ends with it.
  REPLY=
  _dr_shdeps_health_item pkg kind /a/b 'see /a/b.old and /x/a/b; then retry'
  _assert_eq "doctor health: a longer path in the detail keeps the column" \
    'pkg: kind /a/b — see /a/b.old and /x/a/b; then retry' "$REPLY"
  _dr_shdeps_health_item pkg kind /a/b 'remove the record at /a/b.'
  _assert_eq "doctor health: a path ending a sentence is the same path" \
    'pkg: kind — remove the record at /a/b.' "$REPLY"
  # Version skew: an older shdeps names the record in the detail too, so
  # the item leaves its path column out rather than print the path twice.
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=duppath \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: a path the detail repeats is printed once" \
    $'fail\tshdeps health: 1 problem(s)\tzzz/last: blocked-transition — remove the stale transition record at '"$TEST_HOME"$'/.local/state/shdeps/zzz.json and retry; ' \
    "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=future \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: an unknown severity and kind render as a warning" \
    $'warn\tshdeps health: 1 problem(s)\tnew/pkg: future-kind — something new; do this' \
    "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=fail \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: any fail row fails the report" \
    $'fail\tshdeps health: 2 problem(s)' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=empty1 \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: problems without rows are an error" \
    $'fail\tshdeps health failed (exit 1)' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=incomplete \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: an incomplete report fails" \
    $'fail\tshdeps health: 1 problem(s)' "$result"
  _assert_contains "doctor health: an incomplete report says more may be wrong" \
    "some shdeps state could not be read" "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=crash \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: an unexpected status is an error" \
    $'fail\tshdeps health failed (exit 139)' "$result"
  # The health call is bounded, with timeout(1) and, where none is
  # installed, with the builtin watchdog; neither leaves the stub behind.
  for doctor_mode in timeout watchdog; do
    doctor_started=$SECONDS
    if [[ $doctor_mode == timeout ]]; then
      result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=hang \
        _DR_SHDEPS_HEALTH_DEADLINE=1 _doctor_records _dr_check_tools)
    else
      result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=hang \
        _DR_SHDEPS_HEALTH_DEADLINE=1 _DR_TIMEOUT_BIN='' _doctor_records _dr_check_tools)
    fi
    _assert_contains "doctor health: a hung command times out ($doctor_mode)" \
      $'fail\tshdeps health timed out' "$result"
    if ((SECONDS - doctor_started < 10)); then
      _pass "doctor health: the deadline returns promptly ($doctor_mode)"
    else
      _fail "doctor health: the deadline returns promptly ($doctor_mode, $((SECONDS - doctor_started))s)"
    fi
    _assert_eq "doctor health: the hung command does not outlive it ($doctor_mode)" "" \
      "$(
        # shellcheck disable=SC2009 # pgrep -x matches names, not full args.
        ps -A -o args= 2>/dev/null | grep -x 'sleep 47' || true
      )"
  done
  # The builtin watchdog itself: it passes output and status through, a
  # grandchild cannot hold a capture past the deadline, and quick commands
  # leave none of its sleeps behind.
  doctor_started=$SECONDS
  doctor_status=0
  result=$(_DR_TIMEOUT_BIN='' _dr_run_bounded 1 bash -c 'sleep 7; echo late') ||
    doctor_status=$?
  _assert_exit "deadline: a grandchild is stopped with its parent" 124 "$doctor_status"
  _assert_eq "deadline: the stopped grandchild printed nothing" "" "$result"
  if ((SECONDS - doctor_started < 5)); then
    _pass "deadline: a grandchild cannot hold the capture open"
  else
    _fail "deadline: a grandchild cannot hold the capture open ($((SECONDS - doctor_started))s)"
  fi
  doctor_status=0
  result=$(_DR_TIMEOUT_BIN='' _dr_run_bounded 5 bash -c 'echo fine; exit 3') ||
    doctor_status=$?
  _assert_exit "deadline: the command's status passes through" 3 "$doctor_status"
  _assert_eq "deadline: the command's output passes through" "fine" "$result"
  result=$(printf 'from stdin' | _DR_TIMEOUT_BIN='' _dr_run_bounded 5 cat)
  _assert_eq "deadline: the caller's stdin reaches the command" "from stdin" "$result"
  # Nothing the watchdog starts outlives the call, on either path: Dot's
  # supervisor refuses to tear down a suite or doctor worker on macOS
  # while a live member sits outside the leader's process group. The
  # stray scan covers the watchdog, which runs in the caller's group; the
  # command's own group is covered by the straggler cases below. The
  # commands run long enough for the watchdog to be waiting on its clock,
  # and each run must also remove its private directory.
  if [[ $(ps -o pgid= -p "$$" 2>/dev/null) =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]; then
    _pass "deadline: ps reports process groups for the leftover checks"
  else
    _fail "deadline: ps reports process groups for the leftover checks"
  fi
  doctor_strays=$(_doctor_group_strays)
  doctor_tmp=$(_tmpdir)
  for ((doctor_i = 0; doctor_i < 5; doctor_i++)); do
    TMPDIR=$doctor_tmp _DR_TIMEOUT_BIN='' _dr_run_bounded 13 sleep 0.2 || true
  done
  TMPDIR=$doctor_tmp _DR_TIMEOUT_BIN='' _dr_run_bounded 1 sleep 9 || true
  for ((doctor_try = 0; doctor_try < 40; doctor_try++)); do
    [[ -n $(comm -13 <(printf '%s\n' "$doctor_strays") <(_doctor_group_strays)) ]] || break
    sleep 0.05
  done
  _assert_eq "deadline: no watchdog process outlives the call" "" \
    "$(comm -13 <(printf '%s\n' "$doctor_strays") <(_doctor_group_strays))"
  _assert_eq "deadline: the private directory is removed" "" "$(ls -A "$doctor_tmp")"
  # Stragglers in the command's group, from a command that exits on its
  # own and from one the deadline stops with TERM while its child ignores
  # TERM. Each is stopped with the command: one that keeps the capture's
  # pipe cannot hold the capture open, and one that let go of it does not
  # outlive the call. The command prints the straggler's PID.
  for doctor_mode in quick term-proof; do
    if [[ $doctor_mode == quick ]]; then
      doctor_deadline=9 doctor_expect=0
      # shellcheck disable=SC2016 # The child expands its own variables.
      doctor_held='sleep 29 & echo "$!"'
      # shellcheck disable=SC2016
      doctor_free='sleep 29 </dev/null >/dev/null 2>&1 & echo "$!"'
    else
      doctor_deadline=1 doctor_expect=124
      # shellcheck disable=SC2016
      doctor_held='(trap "" TERM; exec sleep 29) & echo "$!"; exec sleep 29'
      # shellcheck disable=SC2016
      doctor_free='(trap "" TERM; exec sleep 29) </dev/null >/dev/null 2>&1 & echo "$!"; exec sleep 29'
    fi
    doctor_started=$SECONDS
    doctor_status=0
    result=$(_DR_TIMEOUT_BIN='' _dr_run_bounded "$doctor_deadline" bash -c "$doctor_held") ||
      doctor_status=$?
    _assert_exit "deadline: the status survives a straggler ($doctor_mode)" \
      "$doctor_expect" "$doctor_status"
    if ((SECONDS - doctor_started < 5)); then
      _pass "deadline: a straggler cannot hold the capture open ($doctor_mode)"
    else
      _fail "deadline: a straggler cannot hold the capture open ($doctor_mode, $((SECONDS - doctor_started))s)"
    fi
    doctor_stray_pid=$(_DR_TIMEOUT_BIN='' _dr_run_bounded "$doctor_deadline" bash -c "$doctor_free")
    if [[ $doctor_stray_pid =~ ^[0-9]+$ ]] && _doctor_wait_gone "$doctor_stray_pid"; then
      _pass "deadline: a straggler does not outlive the call ($doctor_mode)"
    else
      _fail "deadline: a straggler does not outlive the call ($doctor_mode, pid ${doctor_stray_pid:-none})"
      [[ ! $doctor_stray_pid =~ ^[0-9]+$ ]] || kill -KILL "$doctor_stray_pid" 2>/dev/null
    fi
  done
  # A TERM to the caller's process group stops the watchdog with it; the
  # command, in a group of its own, must not be left running without a
  # deadline. The call runs as its own job so the signal stays off this
  # shell's group; the command writes its PID before it hangs.
  doctor_tmp=$(_tmpdir)
  doctor_stray_pid=$(
    set -m
    # shellcheck disable=SC2016 # The child expands its own variables.
    TMPDIR=$doctor_tmp _DR_TIMEOUT_BIN='' _dr_run_bounded 29 \
      bash -c 'echo "$$" >"$1"; exec sleep 29' doctor-hang "$doctor_tmp/pid" \
      </dev/null >/dev/null 2>&1 &
    doctor_try=$!
    set +m
    for ((doctor_i = 0; doctor_i < 100; doctor_i++)); do
      [[ ! -s $doctor_tmp/pid ]] || break
      sleep 0.05
    done
    kill -TERM -- "-$doctor_try" 2>/dev/null
    wait "$doctor_try" 2>/dev/null
    cat "$doctor_tmp/pid" 2>/dev/null
  )
  if [[ $doctor_stray_pid =~ ^[0-9]+$ ]] && _doctor_wait_gone "$doctor_stray_pid"; then
    _pass "deadline: a signal to the caller stops the command"
  else
    _fail "deadline: a signal to the caller stops the command (pid ${doctor_stray_pid:-none})"
    [[ ! $doctor_stray_pid =~ ^[0-9]+$ ]] || kill -KILL "$doctor_stray_pid" 2>/dev/null
  fi
  rm -f "$doctor_tmp/pid"
  _assert_eq "deadline: a signal to the caller removes the private directory" "" \
    "$(ls -A "$doctor_tmp")"
  # Descriptors the caller passes on reach the command (Dot hands its
  # session lease to children by number); the watchdog's clock does not.
  doctor_tmp=$(_tmpdir)
  (
    exec 3>"$doctor_tmp/fd3"
    _DR_TIMEOUT_BIN='' _dr_run_bounded 5 bash -c 'echo passed >&3' 2>/dev/null
  )
  _assert_eq "deadline: the caller's descriptor 3 reaches the command" "passed" \
    "$(cat "$doctor_tmp/fd3" 2>/dev/null)"
  # A deadline the watchdog cannot honor fails before the command runs:
  # a malformed duration, no private directory, or no FIFO.
  doctor_tmp=$(_tmpdir)
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$doctor_tmp/mkfifo"
  chmod +x "$doctor_tmp/mkfifo"
  for doctor_mode in duration directory fifo; do
    doctor_status=0
    case $doctor_mode in
      duration)
        _DR_TIMEOUT_BIN='' _dr_run_bounded 5s touch "$doctor_tmp/ran" || doctor_status=$?
        ;;
      directory)
        TMPDIR=$doctor_tmp/missing _DR_TIMEOUT_BIN='' \
          _dr_run_bounded 5 touch "$doctor_tmp/ran" || doctor_status=$?
        ;;
      fifo)
        PATH="$doctor_tmp:$PATH" TMPDIR=$doctor_tmp _DR_TIMEOUT_BIN='' \
          _dr_run_bounded 5 touch "$doctor_tmp/ran" || doctor_status=$?
        ;;
    esac
    _assert_exit "deadline: an unusable $doctor_mode returns 125" 125 "$doctor_status"
    if [[ -e $doctor_tmp/ran ]]; then
      _fail "deadline: an unusable $doctor_mode does not run the command"
      rm -f "$doctor_tmp/ran"
    else
      _pass "deadline: an unusable $doctor_mode does not run the command"
    fi
  done
  _assert_eq "deadline: a failed FIFO leaves no private directory" "mkfifo" \
    "$(ls -A "$doctor_tmp")"
  # Only a coreutils timeout(1) is trusted for its 124 status; BusyBox's
  # reports a deadline as a SIGTERM death, so the watchdog runs instead.
  doctor_timeout_bin=$(_tmpdir)
  printf '%s\n' '#!/bin/sh' 'echo "BusyBox v1.37.0 multi-call binary."; exit 1' \
    >"$doctor_timeout_bin/timeout"
  chmod +x "$doctor_timeout_bin/timeout"
  _assert_eq "deadline: a BusyBox timeout falls back to the watchdog" "" \
    "$(
      unset _DR_TIMEOUT_BIN
      PATH="$doctor_timeout_bin:$PATH" _dr_timeout_resolve
      printf '%s' "$_DR_TIMEOUT_BIN"
    )"
  printf '%s\n' '#!/bin/sh' 'echo "timeout (GNU coreutils) 9.5"' \
    >"$doctor_timeout_bin/timeout"
  _assert_eq "deadline: a coreutils timeout is used" "$doctor_timeout_bin/timeout" \
    "$(
      unset _DR_TIMEOUT_BIN
      PATH="$doctor_timeout_bin:$PATH" _dr_timeout_resolve
      printf '%s' "$_DR_TIMEOUT_BIN"
    )"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=ok \
    _DR_TIMEOUT_BIN='' _doctor_records _dr_check_tools)
  _assert_contains "doctor health: a healthy report passes through the watchdog" \
    $'ok\tshdeps health' "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=gone \
    _DR_TIMEOUT_BIN='' _doctor_records _dr_check_tools)
  _assert_contains "doctor health: exit 127 is unsupported through the watchdog" \
    $'warn\tshdeps health unchecked' "$result"

  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=gone \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: exit 127 counts as unsupported" \
    $'warn\tshdeps health unchecked' "$result"
  _assert_not_contains "doctor health: exit 127 gives no per-group rows" \
    "bin links" "$result"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=incomplete-empty \
    _doctor_records _dr_check_tools)
  _assert_contains "doctor health: exit 3 without rows fails" \
    $'fail\tshdeps health report incomplete' "$result"
  _assert_not_contains "doctor tools: core's runtime rows are not duplicated" \
    $'ok\tgit\t' "$result"

  # Managed configuration: fragments parse, pre-sync extensions load, and
  # interrupted atomic writes left nothing behind.
  dot_doctor_source doctor.d/lib/managed-config.sh ||
    _fail "doctor managed config: module loads"
  doctor_mc_home=$(_tmpdir)
  doctor_frag=$doctor_mc_home/.config/dot/merge-hooks.d
  mkdir -p "$doctor_frag/app/settings.d" "$doctor_frag/app/config.d" \
    "$doctor_frag/vscode/extensions.d" "$doctor_mc_home/.config/muse" \
    "$doctor_mc_home/ext/pre-sync.d" "$doctor_mc_home/bin"
  # A stand-in for mikefarah yq: a file holding BROKEN does not parse, and
  # every call is logged, so the cases below see which files it was given.
  doctor_yq_log=$doctor_mc_home/yq.log
  cat >"$doctor_mc_home/bin/yq" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  echo 'yq (https://github.com/mikefarah/yq/) version v4.99.0'
  exit 0
fi
printf '%s\n' "$*" >>"$DOCTOR_YQ_LOG"
status=0
for file; do
  [[ -f $file ]] || continue
  if grep -q BROKEN "$file"; then
    echo "Error: bad file '$file'" >&2
    status=1
  fi
done
exit "$status"
SH
  chmod +x "$doctor_mc_home/bin/yq"
  printf '%s\n' '{"a": 1}' >"$doctor_frag/app/settings.d/10-good.json"
  printf '%s\n' '// comments are fine in JSONC' '{"a": 1}' \
    >"$doctor_frag/app/settings.d/20-keys.jsonc"
  result=$(HOME="$doctor_mc_home" _doctor_records _dr_check_fragments)
  _assert_contains "doctor managed config: valid fragments pass" \
    $'ok\tmerge-hook fragments parse\t1 JSON file(s)' "$result"
  printf '%s\n' '{"a": 1,}' >"$doctor_frag/app/settings.d/30-bad.json"
  result=$(HOME="$doctor_mc_home" _doctor_records _dr_check_fragments)
  _assert_contains "doctor managed config: a broken fragment warns" \
    $'warn\t1 merge-hook fragment(s) do not parse' "$result"
  # shellcheck disable=SC2088 # Rows carry tilde display paths.
  _assert_contains "doctor managed config: the broken fragment is named" \
    "~/.config/dot/merge-hooks.d/app/settings.d/30-bad.json" "$result"
  # The vscode hook strips comments from its .json fragments itself.
  mkdir -p "$doctor_frag/vscode/settings.d"
  printf '%s\n' '// editor settings' '{"a": 1}' \
    >"$doctor_frag/vscode/settings.d/10-settings.json"
  result=$(HOME="$doctor_mc_home" _doctor_records _dr_check_fragments)
  _assert_not_contains "doctor managed config: vscode fragments may carry comments" \
    "vscode/settings.d" "$result"
  # A truncated file followed by its missing half must not pass as a pair.
  rm -f "$doctor_frag/app/settings.d/30-bad.json"
  printf '%s' '{"a":' >"$doctor_frag/app/settings.d/40-head.json"
  printf '%s\n' '1}' >"$doctor_frag/app/settings.d/41-tail.json"
  result=$(HOME="$doctor_mc_home" _doctor_records _dr_check_fragments)
  _assert_contains "doctor managed config: each fragment parses on its own" \
    $'warn\t2 merge-hook fragment(s) do not parse' "$result"
  rm -f "$doctor_frag/app/settings.d/40-head.json" "$doctor_frag/app/settings.d/41-tail.json"

  # TOML and YAML fragments go through mikefarah yq, as their hooks do:
  # one call per format while they parse, and a second pass only to name
  # every broken file. The vscode family's TOML joins the yq call only
  # when python3 has no tomllib: this stand-in python3 is one that lacks
  # it (exit 2, as the probe exits on ImportError).
  mkdir -p "$doctor_mc_home/no-tomllib"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 2' >"$doctor_mc_home/no-tomllib/python3"
  chmod +x "$doctor_mc_home/no-tomllib/python3"
  printf '%s\n' 'a = 1' >"$doctor_frag/app/config.d/10-settings.toml"
  printf '%s\n' 'b = 2' >"$doctor_frag/vscode/extensions.d/50-default.toml"
  printf '%s\n' 'c: 3' >"$doctor_frag/app/config.d/10-config.yml"
  : >"$doctor_yq_log"
  result=$(HOME="$doctor_mc_home" \
    PATH="$doctor_mc_home/no-tomllib:$doctor_mc_home/bin:$PATH" \
    DOCTOR_YQ_LOG="$doctor_yq_log" _doctor_records _dr_check_fragments)
  _assert_contains "doctor managed config: TOML and YAML fragments are counted" \
    $'ok\tmerge-hook fragments parse\t1 JSON, 2 TOML, 1 YAML file(s)' "$result"
  _assert_eq "doctor managed config: one yq call per format while they parse" \
    "2" "$(wc -l <"$doctor_yq_log" | tr -d '[:space:]')"
  _assert_contains "doctor managed config: without tomllib, the TOML call reads every TOML fragment" \
    "eval-all -p toml -o json select(false) " "$(grep -e "10-settings.toml" "$doctor_yq_log" | grep -e "50-default.toml")"
  _assert_contains "doctor managed config: the YAML call reads the YAML fragment" \
    "eval-all -p yaml -o json select(false) $doctor_frag/app/config.d/10-config.yml" \
    "$(cat "$doctor_yq_log")"
  printf '%s\n' 'BROKEN [' >"$doctor_frag/app/config.d/20-broken.toml"
  printf '%s\n' 'BROKEN: [' >"$doctor_frag/app/config.d/20-broken.yaml"
  result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/bin:$PATH" \
    DOCTOR_YQ_LOG="$doctor_yq_log" _doctor_records _dr_check_fragments)
  # shellcheck disable=SC2088 # Rows carry tilde display paths.
  _assert_contains "doctor managed config: broken TOML and YAML fragments warn" \
    $'warn\t2 merge-hook fragment(s) do not parse\t~/.config/dot/merge-hooks.d/app/config.d/20-broken.toml; ~/.config/dot/merge-hooks.d/app/config.d/20-broken.yaml; dot update skips them' \
    "$result"
  # Without mikefarah yq (another yq answers --version differently), TOML
  # and YAML are reported unchecked while JSON is still checked.
  mkdir -p "$doctor_mc_home/other-yq"
  printf '%s\n' '#!/usr/bin/env bash' 'echo "yq 3.4.3"' >"$doctor_mc_home/other-yq/yq"
  chmod +x "$doctor_mc_home/other-yq/yq"
  result=$(HOME="$doctor_mc_home" \
    PATH="$doctor_mc_home/no-tomllib:$doctor_mc_home/other-yq:$PATH" \
    _doctor_records _dr_check_fragments)
  _assert_contains "doctor managed config: no mikefarah yq leaves TOML and YAML unchecked" \
    $'skip\tmerge-hook TOML and YAML fragments unchecked\tmikefarah yq not installed' "$result"
  rm -f "$doctor_frag/app/config.d/20-broken.toml" "$doctor_frag/app/config.d/20-broken.yaml"
  # Unless python3 proves it ran the probe (exit 0 and its closing line),
  # the vscode manifests fall back to yq, which names a broken one: a
  # python3 that lacks tomllib (exit 2), fails some other way (exit 3), or
  # exits 0 without running the script must not pass them unchecked.
  printf '%s\n' 'BROKEN [' >"$doctor_frag/vscode/extensions.d/70-broken.toml"
  for doctor_mode in 0 2 3; do
    mkdir -p "$doctor_mc_home/python-exit-$doctor_mode"
    printf '%s\n' '#!/usr/bin/env bash' "exit $doctor_mode" \
      >"$doctor_mc_home/python-exit-$doctor_mode/python3"
    chmod +x "$doctor_mc_home/python-exit-$doctor_mode/python3"
    result=$(HOME="$doctor_mc_home" \
      PATH="$doctor_mc_home/python-exit-$doctor_mode:$doctor_mc_home/bin:$PATH" \
      DOCTOR_YQ_LOG="$doctor_yq_log" _doctor_records _dr_check_fragments)
    # shellcheck disable=SC2088 # Rows carry tilde display paths.
    _assert_contains "doctor managed config: python3 exit $doctor_mode falls back to yq for vscode manifests" \
      $'warn\t1 merge-hook fragment(s) do not parse\t~/.config/dot/merge-hooks.d/vscode/extensions.d/70-broken.toml;' \
      "$result"
  done
  rm -f "$doctor_frag/vscode/extensions.d/70-broken.toml"
  # The real parser, where the host has one: a truncated TOML file fails
  # even when a valid one follows it in the same call.
  if doctor_tmp=$(type -P yq 2>/dev/null) &&
    [[ $("$doctor_tmp" --version 2>/dev/null) == *mikefarah* ]]; then
    doctor_tmp=${doctor_tmp%/*}
    printf '%s\n' '[table' >"$doctor_frag/app/config.d/05-truncated.toml"
    result=$(HOME="$doctor_mc_home" PATH="$doctor_tmp:$PATH" \
      _doctor_records _dr_check_fragments)
    _assert_contains "doctor managed config: real yq rejects a truncated TOML fragment" \
      "05-truncated.toml" "$result"
    _assert_not_contains "doctor managed config: real yq accepts the valid ones" \
      "10-settings.toml" "$result"
    rm -f "$doctor_frag/app/config.d/05-truncated.toml"
  else
    echo "  - skipping real yq fragment check (mikefarah yq not installed)"
  fi

  # The vscode family's TOML fragments are extension manifests that the
  # vscode-exts provider reads with Python's tomllib, so they are judged by
  # tomllib where python3 has it: a duplicate key, which yq accepts but
  # makes the provider reject the manifest, is named. Other TOML stays
  # with yq, the parser its hooks use, so the same mistake there is not.
  if python3 -c 'import tomllib' >/dev/null 2>&1; then
    printf '%s\n' '[bundle.common]' 'extensions = ["a"]' 'extensions = ["b"]' \
      >"$doctor_frag/vscode/extensions.d/60-duplicate.toml"
    printf '%s\n' 'a = 1' 'a = 2' >"$doctor_frag/app/config.d/30-duplicate.toml"
    : >"$doctor_yq_log"
    result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/bin:$PATH" \
      DOCTOR_YQ_LOG="$doctor_yq_log" _doctor_records _dr_check_fragments)
    # shellcheck disable=SC2088 # Rows carry tilde display paths.
    _assert_contains "doctor managed config: tomllib names a duplicate key in a vscode manifest" \
      $'warn\t1 merge-hook fragment(s) do not parse\t~/.config/dot/merge-hooks.d/vscode/extensions.d/60-duplicate.toml;' \
      "$result"
    _assert_contains "doctor managed config: the hint gives a tomllib command" \
      'python3 -c "import sys, tomllib; tomllib.load(sys.stdin.buffer)" < <file>' "$result"
    _assert_not_contains "doctor managed config: other TOML is still judged by yq" \
      "30-duplicate.toml" "$result"
    _assert_not_contains "doctor managed config: vscode manifests are not given to yq" \
      "vscode" "$(cat "$doctor_yq_log")"
    rm -f "$doctor_frag/vscode/extensions.d/60-duplicate.toml" \
      "$doctor_frag/app/config.d/30-duplicate.toml"
    # Without mikefarah yq the manifests are still checked and counted.
    result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/other-yq:$PATH" \
      _doctor_records _dr_check_fragments)
    _assert_contains "doctor managed config: tomllib checks vscode manifests without yq" \
      $'ok\tmerge-hook fragments parse\t1 JSON, 1 TOML file(s)' "$result"
    _assert_contains "doctor managed config: other TOML and YAML stay unchecked without yq" \
      $'skip\tmerge-hook TOML and YAML fragments unchecked\tmikefarah yq not installed' "$result"
    # The skip row names only what went unchecked.
    mv "$doctor_frag/app/config.d/10-settings.toml" "$doctor_mc_home/10-settings.toml"
    result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/other-yq:$PATH" \
      _doctor_records _dr_check_fragments)
    _assert_contains "doctor managed config: the skip row omits TOML that tomllib checked" \
      $'skip\tmerge-hook YAML fragments unchecked\tmikefarah yq not installed' "$result"
    mv "$doctor_frag/app/config.d/10-config.yml" "$doctor_mc_home/10-config.yml"
    result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/other-yq:$PATH" \
      _doctor_records _dr_check_fragments)
    _assert_not_contains "doctor managed config: no skip row when tomllib checked everything" \
      $'skip\t' "$result"
    mv "$doctor_mc_home/10-settings.toml" "$doctor_frag/app/config.d/10-settings.toml"
    mv "$doctor_mc_home/10-config.yml" "$doctor_frag/app/config.d/10-config.yml"
    # Only what vscode-exts reads goes to tomllib: TOML elsewhere in the
    # vscode family stays with yq.
    mkdir -p "$doctor_frag/vscode/other.d"
    printf '%s\n' 'a = 1' >"$doctor_frag/vscode/other.d/10-other.toml"
    : >"$doctor_yq_log"
    result=$(HOME="$doctor_mc_home" PATH="$doctor_mc_home/bin:$PATH" \
      DOCTOR_YQ_LOG="$doctor_yq_log" _doctor_records _dr_check_fragments)
    _assert_contains "doctor managed config: vscode TOML outside extensions.d goes to yq" \
      "vscode/other.d/10-other.toml" "$(cat "$doctor_yq_log")"
    _assert_not_contains "doctor managed config: extension manifests still skip yq" \
      "vscode/extensions.d" "$(cat "$doctor_yq_log")"
    rm -rf "$doctor_frag/vscode/other.d"
  else
    echo "  - skipping tomllib fragment check (python3 has no tomllib)"
  fi

  printf '%s\n' 'prepare() {' '  :' '}' >"$doctor_mc_home/ext/pre-sync.d/10-good.sh"
  result=$(DOT_EXTENSIONS_DIR="$doctor_mc_home/ext" \
    _doctor_records _dr_check_pre_sync_extensions)
  _assert_contains "doctor managed config: loadable pre-sync extensions pass" \
    $'ok\tpre-sync extensions load\t1 extension(s)' "$result"
  printf '%s\n' 'function prepare {' '  :' '}' >"$doctor_mc_home/ext/pre-sync.d/15-keyword.sh"
  result=$(DOT_EXTENSIONS_DIR="$doctor_mc_home/ext" \
    _doctor_records _dr_check_pre_sync_extensions)
  _assert_contains "doctor managed config: a keyword-style prepare counts" \
    $'ok\tpre-sync extensions load\t2 extension(s)' "$result"
  printf '%s\n' 'prepare() {' '  if' '}' >"$doctor_mc_home/ext/pre-sync.d/20-broken.sh"
  printf '%s\n' 'setup() { :; }' >"$doctor_mc_home/ext/pre-sync.d/30-entryless.sh"
  result=$(DOT_EXTENSIONS_DIR="$doctor_mc_home/ext" \
    _doctor_records _dr_check_pre_sync_extensions)
  _assert_contains "doctor managed config: broken pre-sync extensions fail" \
    $'fail\tpre-sync extensions are broken: 20-broken.sh (syntax error); 30-entryless.sh (no prepare function)' \
    "$result"
  _assert_contains "doctor managed config: the pre-sync hint says where the files are" \
    "they are in $doctor_mc_home/ext/pre-sync.d: check each with 'bash -n <file>'" "$result"

  # Leftover temporaries: base checks the destinations of its own merge
  # hooks, by every name the writers use, past the in-flight window.
  mkdir -p "$doctor_mc_home/.ssh" "$doctor_mc_home/.codex" "$doctor_mc_home/.claude" \
    "$doctor_mc_home/.llms/rules" "$doctor_mc_home/.toolcache.tmp"
  printf 'Host *\n' >"$doctor_mc_home/.ssh/config.tmp.Ab12Cd"
  printf 'Host *\n' >"$doctor_mc_home/.ssh/config.tmp.Fresh1"
  # Claude Code's own `.tmp.<pid>.<hex>` beside ~/.claude.json, a 7-digit
  # PID suffix, a plain `.tmp`, a hidden HOME file, and a realize scratch.
  printf '{}\n' >"$doctor_mc_home/.claude.json.tmp.4164451.7a8298303801"
  printf 'x\n' >"$doctor_mc_home/.codex/config.toml.tmp.4194301"
  printf 'x\n' >"$doctor_mc_home/.codex/hooks.json.tmp"
  printf 'x\n' >"$doctor_mc_home/.ignore.tmp.Qq11Ww"
  printf 'x\n' >"$doctor_mc_home/.codex/.dm.realize.Ee22Rr"
  # Not leftovers: a directory, a symlink, and other folders' files.
  ln -s "$doctor_mc_home/.ssh/config.tmp.Ab12Cd" "$doctor_mc_home/.ssh/link.tmp.Zz00Zz"
  printf '{}\n' >"$doctor_mc_home/.config/muse/settings.json.tmp.Mu5e00"
  printf '{}\n' >"$doctor_mc_home/.claude/settings.json.tmp.Cl4ude"
  # A visible file directly in HOME is the user's own, whatever its name.
  printf 'x\n' >"$doctor_mc_home/notes.tmp"
  for doctor_tmp in .ssh/config.tmp.Ab12Cd .claude.json.tmp.4164451.7a8298303801 \
    .codex/config.toml.tmp.4194301 .codex/hooks.json.tmp .ignore.tmp.Qq11Ww \
    .codex/.dm.realize.Ee22Rr .config/muse/settings.json.tmp.Mu5e00 \
    .claude/settings.json.tmp.Cl4ude notes.tmp; do
    touch -t 202001010000 "$doctor_mc_home/$doctor_tmp"
  done
  result=$(HOME="$doctor_mc_home" XDG_STATE_HOME='' \
    _doctor_records _dr_check_base_config_temporaries)
  _assert_contains "doctor managed config: old temporaries warn" \
    $'warn\t6 leftover config temporary file(s)' "$result"
  for doctor_tmp in .ssh/config.tmp.Ab12Cd .claude.json.tmp.4164451.7a8298303801 \
    .codex/config.toml.tmp.4194301 .codex/hooks.json.tmp .ignore.tmp.Qq11Ww \
    .codex/.dm.realize.Ee22Rr; do
    # shellcheck disable=SC2088 # Rows carry tilde display paths.
    _assert_contains "doctor managed config: a leftover is listed ($doctor_tmp)" \
      "~/$doctor_tmp" "$(
        # shellcheck disable=SC2329 # Probed by the check under test.
        dot_doctor_item() { _dot_doctor_record item "$1"; }
        # shellcheck disable=SC2329
        dot_doctor_hint() { _dot_doctor_record hint "$1"; }
        HOME="$doctor_mc_home" XDG_STATE_HOME='' \
          _doctor_records _dr_check_base_config_temporaries
      )"
  done
  _assert_not_contains "doctor managed config: an in-flight temporary is ignored" \
    "Fresh1" "$result"
  _assert_not_contains "doctor managed config: a symlink is not a leftover" \
    "Zz00Zz" "$result"
  _assert_not_contains "doctor managed config: a directory is not a leftover" \
    ".toolcache.tmp" "$result"
  _assert_not_contains "doctor managed config: agent folders are the dev overlay's" \
    "Mu5e00" "$result"
  _assert_not_contains "doctor managed config: a visible file in HOME is not a leftover" \
    "notes.tmp" "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the check under test.
    dot_doctor_item() { _dot_doctor_record item "$1"; }
    # shellcheck disable=SC2329
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    HOME="$doctor_mc_home" XDG_STATE_HOME='' \
      _doctor_records _dr_check_base_config_temporaries
  )
  _assert_contains "doctor managed config: the list helpers get a next step" \
    $'hint\tan interrupted write left them; delete them when neither \'dot update\' nor the program that owns the file is running' \
    "$result"
  # An agent-rules target recorded in the update's manifest is a base
  # destination too.
  doctor_mc_state=$doctor_mc_home/state
  mkdir -p "$doctor_mc_state/dot"
  printf 'rule\t%s\ntarget-file\t%s\n' "$doctor_mc_home/rules/001-a.md" \
    "$doctor_mc_home/.llms/rules/AGENTS.md" >"$doctor_mc_state/dot/agent-rules-sync-manifest-v1.tsv"
  printf 'x\n' >"$doctor_mc_home/.llms/rules/AGENTS.md.tmp.Ab12Cd34"
  touch -t 202001010000 "$doctor_mc_home/.llms/rules/AGENTS.md.tmp.Ab12Cd34"
  result=$(HOME="$doctor_mc_home" XDG_STATE_HOME="$doctor_mc_state" \
    _doctor_records _dr_check_base_config_temporaries)
  _assert_contains "doctor managed config: agent-rules targets are checked" \
    $'warn\t7 leftover config temporary file(s)' "$result"
  # Overlay contract: an overlay passes its own folders, relative to HOME or
  # absolute; folders base checks, and repeats, are dropped.
  result=$(HOME="$doctor_mc_home" XDG_STATE_HOME="$doctor_mc_state" \
    _doctor_records _dr_check_config_temporaries .claude "$doctor_mc_home/.claude/" \
    .config/muse .codex "$doctor_mc_home/.ssh" .llms/rules no-such-dir)
  _assert_contains "doctor managed config: an overlay's folders are checked" \
    $'warn\t2 leftover config temporary file(s)\t~/.claude/settings.json.tmp.Cl4ude; ~/.config/muse/settings.json.tmp.Mu5e00; an interrupted write' \
    "$result"
  result=$(HOME="$doctor_mc_home" XDG_STATE_HOME="$doctor_mc_state" \
    _doctor_records _dr_check_config_temporaries .codex .ssh)
  _assert_eq "doctor managed config: base folders passed by an overlay are not repeated" \
    "" "$result"

  # Agent rules: a Dot without the public hook runtime cannot answer, which
  # is a skip, not a policy failure.
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$doctor_bin/agent-rules-sync"
  chmod +x "$doctor_bin/agent-rules-sync"
  result=$(DOT_TEST_AGENT_RULES_CHECK=1 DOT_SOURCE_ROOT="$doctor_mc_home/no-dot" \
    PATH="$doctor_bin:$PATH" _doctor_records _dr_check_agent_rules)
  _assert_contains "doctor agent rules: a missing hook runtime is a skip" \
    $'skip\tgenerated policy check skipped' "$result"
  rm -f "$doctor_bin/agent-rules-sync"

  # The shdeps configuration and curl are tracked files and a host tool:
  # core's repository rows cover the first, and Tools reports neither.
  doctor_conf_home=$(_tmpdir)
  result=$(HOME="$doctor_conf_home" PATH="$doctor_bin:$PATH" DOCTOR_HEALTH_MODE=ok \
    _doctor_records _dr_check_tools)
  _assert_eq "doctor tools: one row, for shdeps health, without a config dir" \
    "$(printf '%s\n' $'section\tTools\t' \
      $'ok\tshdeps health\tinstalled dependencies, links, and state are consistent')" \
    "$result"

  # Doctor reports a vendor installer block but never rewrites the
  # tracked loaders; the grok-rc merge hook owns the strip.
  doctor_grok_home=$(_tmpdir)
  # The installed helper sits where the old in-doctor strip looked for it.
  mkdir -p "$doctor_grok_home/.local/lib/dotfiles"
  cp "$REAL_HOME/.local/lib/dotfiles/shell-grok-rc.sh" \
    "$doctor_grok_home/.local/lib/dotfiles/shell-grok-rc.sh"
  # shellcheck disable=SC2016 # The vendor block keeps a literal HOME.
  printf '%s\n' '# thin loader' '' '# >>> grok installer >>>' \
    'export PATH="$HOME/.grok/bin:$PATH"' '# <<< grok installer <<<' \
    >"$doctor_grok_home/.zshrc"
  printf '%s\n' '# thin loader' >"$doctor_grok_home/.bashrc"
  cp "$doctor_grok_home/.zshrc" "$doctor_grok_home/zshrc.before"
  result=$(HOME="$doctor_grok_home" _doctor_records _dr_check_shell)
  _assert_contains "doctor shell: a Grok installer block warns" \
    $'warn\tGrok installer block in ~/.zshrc' "$result"
  _assert_contains "doctor shell: the warning names the repair" \
    "run 'dot update' to strip it" "$result"
  _assert_eq "doctor shell: the tracked loader is left untouched" \
    "$(cat "$doctor_grok_home/zshrc.before")" "$(cat "$doctor_grok_home/.zshrc")"
  printf '%s\n' '# thin loader' '# >>> grok installer >>>' 'export KEEP_ME=1' \
    >"$doctor_grok_home/.zshrc"
  result=$(HOME="$doctor_grok_home" _doctor_records _dr_check_shell)
  _assert_contains "doctor shell: an unterminated block asks for a manual edit" \
    $'warn\tunterminated Grok installer block in ~/.zshrc' "$result"
  _assert_contains "doctor shell: an unterminated block is not sent to dot update" \
    "edit the file by hand" "$result"
  printf '%s\n' '# thin loader' >"$doctor_grok_home/.zshrc"
  result=$(HOME="$doctor_grok_home" _doctor_records _dr_check_shell)
  _assert_not_contains "doctor shell: clean loaders report no Grok row" \
    "Grok" "$result"

  cp "$REAL_HOME/.local/lib/dotfiles/shell-loader.sh" \
    "$TEST_HOME/.local/lib/dotfiles/shell-loader.sh"
  mkdir -p "$TEST_HOME/.config/shell/env.d" \
    "$TEST_HOME/.config/shell/interactive.d" \
    "$TEST_HOME/.config/shdeps"
  # Use the managed startup files: the probes start real shells, and a
  # synthetic loader would hide what each startup path actually does.
  for doctor_startup in .bashrc .bash_profile .zshrc .zshenv .zprofile \
    .config/shell/env-noninteractive.sh .config/shell/env.d/50-core.sh \
    .config/shell/env.d/90-path.sh; do
    cp "$REAL_HOME/$doctor_startup" "$TEST_HOME/$doctor_startup"
  done
  printf '%s\n' 'fixture/tool github:repo tool' \
    >"$TEST_HOME/.config/shdeps/deps.conf"

  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    "$(_test_dot_bin "$DOT_SOURCE_ROOT")" doctor 2>&1 || true)
  _assert_contains "doctor integration: renders the standalone title" \
    "dot doctor" "$result"
  _assert_contains "doctor integration: renders client repository health" \
    "Client repository" "$result"
  for expected in "Shell environment" "Tools" "Shell integrations" \
    "Agent rules" "Managed configuration" "Cron" "Worktrees"; do
    _assert_contains "doctor integration: renders base section $expected" \
      "$expected" "$result"
  done
  for absent in "Git hooks" "Agent hooks" "Agent tooling" "Hive Memory" "Neovim"; do
    _assert_not_contains "doctor integration: omits capability section $absent" \
      "$absent" "$result"
  done
  _assert_contains "doctor integration: login bash loads the environment" \
    "bash login loads the shell environment" "$result"
  _assert_contains "doctor integration: BASH_ENV bash loads the environment" \
    "bash -c (BASH_ENV) loads the shell environment" "$result"
  _assert_contains "doctor integration: renders an aggregate summary" \
    "passed" "$result"

  # A developer's ZDOTDIR would point zsh at the real startup files.
  unset ZDOTDIR
  _doctor_shell() {
    HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
      _doctor_records _dr_check_shell
  }
  doctor_shell_status=0
  doctor_shell_err=$({ _doctor_shell >/dev/null; } 2>&1) || doctor_shell_status=$?
  _assert_exit "doctor shell: the check returns success" 0 "$doctor_shell_status"
  _assert_eq "doctor shell: the check prints nothing out of band" "" "$doctor_shell_err"
  if command -v zsh >/dev/null 2>&1; then
    result=$(_doctor_shell)
    _assert_contains "doctor shell: non-login zsh loads the environment" \
      $'ok\tzsh -c loads the shell environment' "$result"
    _assert_contains "doctor shell: login zsh loads the environment" \
      $'ok\tzsh login loads the shell environment' "$result"
  fi

  # Startup output on stderr corrupts every tool that runs a shell.
  printf '%s\n' 'printf "noisy fragment\n" >&2' \
    >"$TEST_HOME/.config/shell/env.d/95-noise.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: stderr from startup fails login bash" \
    $'fail\tbash login startup prints to stderr\tnoisy fragment' "$result"
  _assert_contains "doctor shell: stderr from startup fails BASH_ENV bash" \
    $'fail\tbash -c (BASH_ENV) startup prints to stderr' "$result"
  if command -v zsh >/dev/null 2>&1; then
    _assert_contains "doctor shell: stderr from startup fails zsh" \
      $'fail\tzsh -c startup prints to stderr' "$result"
  fi
  doctor_shell_status=0
  doctor_shell_err=$({ _doctor_shell >/dev/null; } 2>&1) || doctor_shell_status=$?
  _assert_exit "doctor shell: failing probes still return success" 0 "$doctor_shell_status"
  _assert_eq "doctor shell: failing probes print nothing out of band" "" "$doctor_shell_err"
  # Startup text on stdout corrupts scp, rsync, and command substitution.
  printf '%s\n' 'printf "welcome banner\n"' \
    >"$TEST_HOME/.config/shell/env.d/95-noise.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: stdout from startup fails" \
    $'fail\tbash -c (BASH_ENV) startup prints to stdout\twelcome banner' "$result"
  rm -f "$TEST_HOME/.config/shell/env.d/95-noise.sh"

  # The probes run without the caller's ~/.local/bin, so startup must add it.
  mv "$TEST_HOME/.config/shell/env.d/90-path.sh" "$TEST_HOME/90-path.sh.off"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: startup that never adds ~/.local/bin fails" \
    $'fail\tbash login leaves ~/.local/bin off PATH' "$result"
  mv "$TEST_HOME/90-path.sh.off" "$TEST_HOME/.config/shell/env.d/90-path.sh"

  # Without zsh on PATH the zsh flavors are skipped, not failed.
  doctor_nozsh_bin=$(_tmpdir)
  for doctor_tool in bash cat mktemp mkfifo rm timeout dirname; do
    doctor_tool_path=$(type -P "$doctor_tool" 2>/dev/null) || continue
    ln -s "$doctor_tool_path" "$doctor_nozsh_bin/$doctor_tool"
  done
  result=$(HOME="$TEST_HOME" PATH="$doctor_nozsh_bin" _doctor_records _dr_check_shell)
  _assert_contains "doctor shell: a missing zsh is skipped" \
    $'skip\tzsh startup\tzsh not installed' "$result"

  # Login flavors must take the authoritative path, the -c flavors the
  # fill-only one, exactly as the real shells do.
  # shellcheck disable=SC2016 # The fragment expands its own variables.
  printf '%s\n' '[ "${_SHELL_ENV_MODE:-}" = fill ] || printf "authoritative load\n" >&2' \
    >"$TEST_HOME/.config/shell/env.d/95-mode.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: the bash login probe is authoritative" \
    $'fail\tbash login startup prints to stderr\tauthoritative load' "$result"
  _assert_contains "doctor shell: the BASH_ENV probe is fill-only" \
    $'ok\tbash -c (BASH_ENV) loads the shell environment' "$result"
  if command -v zsh >/dev/null 2>&1; then
    _assert_contains "doctor shell: the zsh login probe is authoritative" \
      $'fail\tzsh login startup prints to stderr\tauthoritative load' "$result"
    _assert_contains "doctor shell: the zsh -c probe is fill-only" \
      $'ok\tzsh -c loads the shell environment' "$result"
  fi
  # Stderr text is one record line: TABs become spaces.
  printf '%s\n' 'printf "tab\there\n" >&2' >"$TEST_HOME/.config/shell/env.d/95-mode.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: a TAB in startup stderr is displayed as a space" \
    $'startup prints to stderr\ttab here' "$result"
  rm -f "$TEST_HOME/.config/shell/env.d/95-mode.sh"

  # A startup file that hangs is reported, not waited on forever, with
  # timeout(1) and with the builtin watchdog alike.
  printf '%s\n' 'while :; do :; done' >"$TEST_HOME/.config/shell/env.d/95-hang.sh"
  for doctor_mode in timeout watchdog; do
    doctor_started=$SECONDS
    if [[ $doctor_mode == timeout ]]; then
      result=$(_DR_SHELL_DEADLINE=1 _doctor_shell)
    else
      result=$(_DR_SHELL_DEADLINE=1 _DR_TIMEOUT_BIN='' _doctor_shell)
    fi
    _assert_contains "doctor shell: a hung login probe times out ($doctor_mode)" \
      $'fail\tbash login startup timed out' "$result"
    _assert_contains "doctor shell: a hung BASH_ENV probe times out ($doctor_mode)" \
      $'fail\tbash -c (BASH_ENV) startup timed out' "$result"
    if ((SECONDS - doctor_started < 10)); then
      _pass "doctor shell: hung probes return promptly ($doctor_mode)"
    else
      _fail "doctor shell: hung probes return promptly ($doctor_mode, $((SECONDS - doctor_started))s)"
    fi
  done
  rm -f "$TEST_HOME/.config/shell/env.d/95-hang.sh"

  # A probe whose deadline cannot be set up says nothing about the
  # startup files: the BASH_ENV query must not read as unconfigured.
  doctor_tmp=$(_tmpdir)
  printf '%s\n' '#!/bin/sh' 'exit 1' >"$doctor_tmp/mkfifo"
  chmod +x "$doctor_tmp/mkfifo"
  result=$(HOME="$TEST_HOME" PATH="$doctor_tmp:$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    _DR_TIMEOUT_BIN='' _doctor_records _dr_check_shell)
  _assert_contains "doctor shell: an unusable deadline fails the BASH_ENV probe" \
    $'fail\tbash -c (BASH_ENV) startup failed' "$result"
  _assert_not_contains "doctor shell: an unusable deadline is not unconfigured BASH_ENV" \
    "startup not configured" "$result"

  # The first bash on PATH is what `/usr/bin/env bash` scripts get.
  doctor_oldbash_bin=$(_tmpdir)
  printf '%s\n' '#!/bin/sh' \
    'printf "dot-doctor-probe marker=%s pid=%s local_bin=1 bash=3\n" "$$" "$$"' \
    >"$doctor_oldbash_bin/bash"
  chmod +x "$doctor_oldbash_bin/bash"
  result=$(HOME="$TEST_HOME" PATH="$doctor_oldbash_bin:$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    _doctor_records _dr_check_shell)
  _assert_contains "doctor shell: a first bash older than 4 warns" \
    $'warn\tfirst bash on PATH is version 3' "$result"

  rm -f "$TEST_HOME/.config/shell/env-noninteractive.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: a missing BASH_ENV target fails" \
    $'fail\tbash -c (BASH_ENV) does not load the shell environment' "$result"
  if command -v zsh >/dev/null 2>&1; then
    _assert_contains "doctor shell: non-login zsh without its loader fails" \
      $'fail\tzsh -c does not load the shell environment' "$result"
  fi
  cp "$REAL_HOME/.config/shell/env-noninteractive.sh" \
    "$TEST_HOME/.config/shell/env-noninteractive.sh"

  rm -f "$TEST_HOME/.config/shell/env.d/50-core.sh"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: startup that never exports BASH_ENV warns" \
    $'warn\tbash -c (BASH_ENV) startup not configured' "$result"

  rm -f "$TEST_HOME/.bashrc"
  result=$(_doctor_shell)
  _assert_contains "doctor shell: login bash without ~/.bashrc fails" \
    $'fail\tbash login does not load the shell environment' "$result"
  _assert_not_contains "doctor shell: presence rows are gone" \
    "sources shared loader" "$result"
  unset -f _doctor_shell

  echo ""
  echo "=== Shell integrations ==="

  # Fixture HOME with the real loader chain (shell-loader, shdeps
  # assets adapter, 53-termnav) resolving through a stub shdeps to a
  # fixture termnav asset. Both the full-boot probe and the direct
  # asset probe answer from this same fixture.
  integ_home=$(_tmpdir)
  integ_bin=$(_tmpdir)
  mkdir -p "$integ_home/.local/lib/dotfiles" \
    "$integ_home/.config/shell/interactive.d" \
    "$integ_home/.config/shdeps" "$integ_home/share"
  cp "$REAL_HOME/.local/lib/dotfiles/shell-loader.sh" \
    "$integ_home/.local/lib/dotfiles/shell-loader.sh"
  cp "$REAL_HOME/.local/lib/dotfiles/shdeps-assets.sh" \
    "$integ_home/.local/lib/dotfiles/shdeps-assets.sh"
  cp "$REAL_HOME/.config/shell/interactive.d/53-termnav.sh" \
    "$integ_home/.config/shell/interactive.d/53-termnav.sh"
  printf '%s\n' 'TERMNAV_SHELL_LOADED=1' \
    >"$integ_home/share/termnav-asset.sh"
  cat >"$integ_bin/shdeps" <<SH
#!/usr/bin/env bash
if [[ "\${1:-}" == dep-file && "\${2:-}" == cgraf78/termnav && "\${3:-}" == share/termnav/shell.sh ]]; then
  printf '%s\n' "$integ_home/share/termnav-asset.sh"
  exit 0
fi
exit 1
SH
  chmod +x "$integ_bin/shdeps"
  # Pin shdeps resolution to the stub: ambient SHDEPS_BIN hints must not
  # leak a host shdeps into the fixture probes.
  if [[ -z ${SHDEPS_BIN+x} ]]; then
    integ_shdeps_bin_unset=1
  else
    integ_shdeps_bin_unset=0
    integ_saved_shdeps_bin=$SHDEPS_BIN
  fi
  if [[ -z ${SHDEPS_BIN_DIR+x} ]]; then
    integ_shdeps_dir_unset=1
  else
    integ_shdeps_dir_unset=0
    integ_saved_shdeps_dir=$SHDEPS_BIN_DIR
  fi
  unset SHDEPS_BIN SHDEPS_BIN_DIR
  integ_saved_home=$HOME
  integ_saved_path=$PATH
  HOME=$integ_home
  PATH=$integ_bin:$PATH
  export HOME PATH
  _doctor_records _dr_check_shell_integrations \
    >"$integ_home/healthy.txt" 2>/dev/null
  integ_healthy_status=$?
  mv "$integ_home/share/termnav-asset.sh" "$integ_home/share/termnav-asset.sh.off"
  _doctor_records _dr_check_shell_integrations \
    >"$integ_home/missing.txt" 2>/dev/null
  printf '%s\n' ':' >"$integ_home/share/termnav-asset.sh"
  _doctor_records _dr_check_shell_integrations \
    >"$integ_home/broken.txt" 2>/dev/null
  rm "$integ_home/share/termnav-asset.sh"
  mv "$integ_home/share/termnav-asset.sh.off" "$integ_home/share/termnav-asset.sh"
  HOME=$integ_saved_home
  PATH=$integ_saved_path
  export HOME PATH
  integ_healthy=$(cat "$integ_home/healthy.txt")
  integ_missing=$(cat "$integ_home/missing.txt")
  integ_broken=$(cat "$integ_home/broken.txt")
  _assert_exit "integrations: healthy check exits 0" 0 \
    "$integ_healthy_status"
  _assert_contains "integrations: healthy bash reports ok" \
    $'ok\ttermnav bash integration' "$integ_healthy"
  _assert_contains "integrations: missing asset warns for bash" \
    $'warn\ttermnav bash integration unavailable' "$integ_missing"
  _assert_contains "integrations: markerless asset warns for bash" \
    $'warn\ttermnav bash integration unavailable' "$integ_broken"
  if command -v zsh >/dev/null 2>&1; then
    _assert_contains "integrations: healthy zsh reports ok" \
      $'ok\ttermnav zsh integration' "$integ_healthy"
    _assert_contains "integrations: missing asset warns for zsh" \
      $'warn\ttermnav zsh integration unavailable' "$integ_missing"
  else
    _assert_contains "integrations: missing zsh skips the zsh check" \
      $'skip\ttermnav zsh integration' "$integ_healthy"
  fi

  # An asset that hangs is cut off at the deadline, with timeout(1) and
  # with the builtin watchdog, and nothing it started outlives the check.
  cp "$integ_home/share/termnav-asset.sh" "$integ_home/share/termnav-asset.sh.ok"
  # A sleep length unique to this run, so the leftover check below cannot
  # match another suite's process.
  printf '%s\n' "sleep 31.$$" >"$integ_home/share/termnav-asset.sh"
  integ_saved_home=$HOME
  integ_saved_path=$PATH
  HOME=$integ_home
  PATH=$integ_bin:$PATH
  export HOME PATH
  for doctor_mode in timeout watchdog; do
    doctor_started=$SECONDS
    if [[ $doctor_mode == timeout ]]; then
      _DR_TERMNAV_DEADLINE=1 _doctor_records _dr_check_shell_integrations \
        >"$integ_home/hang.txt" 2>/dev/null
    else
      _DR_TERMNAV_DEADLINE=1 _DR_TIMEOUT_BIN='' _doctor_records _dr_check_shell_integrations \
        >"$integ_home/hang.txt" 2>/dev/null
    fi
    _assert_contains "integrations: a hanging asset times out ($doctor_mode)" \
      $'warn\ttermnav bash integration timed out' "$(cat "$integ_home/hang.txt")"
    if ((SECONDS - doctor_started < 8)); then
      _pass "integrations: the deadline returns promptly ($doctor_mode)"
    else
      _fail "integrations: the deadline returns promptly ($doctor_mode, $((SECONDS - doctor_started))s)"
    fi
  done
  HOME=$integ_saved_home
  PATH=$integ_saved_path
  export HOME PATH
  _assert_eq "integrations: the hung asset does not outlive the check" "" \
    "$(
      # shellcheck disable=SC2009 # pgrep -x matches names, not full args.
      ps -A -o args= 2>/dev/null | grep -x "sleep 31.$$" || true
    )"
  mv "$integ_home/share/termnav-asset.sh.ok" "$integ_home/share/termnav-asset.sh"

  # A zsh-free PATH pins the skip verdict deterministically even on
  # hosts with zsh installed; bash must still answer from the asset.
  # Dropping the stub shdeps from that PATH pins the unresolvable
  # verdict without any host shdeps leaking in.
  integ_nz_bin=$(_tmpdir)
  ln -s "$(command -v bash)" "$integ_nz_bin/bash"
  ln -s "$(command -v cat)" "$integ_nz_bin/cat"
  ln -s "$(command -v mktemp)" "$integ_nz_bin/mktemp"
  # The builtin watchdog bounds the probes where timeout(1) is not on PATH.
  ln -s "$(command -v mkfifo)" "$integ_nz_bin/mkfifo"
  ln -s "$(command -v rm)" "$integ_nz_bin/rm"
  ln -s "$(command -v sort)" "$integ_nz_bin/sort"
  integ_saved_home=$HOME
  integ_saved_path=$PATH
  HOME=$integ_home
  PATH=$integ_bin:$integ_nz_bin
  export HOME PATH
  _doctor_records _dr_check_shell_integrations \
    >"$integ_home/nozsh.txt" 2>/dev/null
  PATH=$integ_nz_bin
  export PATH
  _doctor_records _dr_check_shell_integrations \
    >"$integ_home/noresolve.txt" 2>/dev/null
  HOME=$integ_saved_home
  PATH=$integ_saved_path
  export HOME PATH
  integ_nozsh=$(cat "$integ_home/nozsh.txt")
  integ_noresolve=$(cat "$integ_home/noresolve.txt")
  _assert_contains "integrations: zsh-free PATH reports bash ok" \
    $'ok\ttermnav bash integration' "$integ_nozsh"
  _assert_contains "integrations: zsh-free PATH skips zsh" \
    $'skip\ttermnav zsh integration' "$integ_nozsh"
  _assert_contains "integrations: unresolvable asset warns for bash" \
    $'warn\ttermnav bash integration unavailable' "$integ_noresolve"

  # The narrow probe never sources interactive startup: a poison file
  # that would abort a full boot must not change the verdict.
  integ_poison=$(_tmpdir)
  cp -r "$integ_home/." "$integ_poison/"
  printf '%s\n' 'exit 1' \
    >"$integ_poison/.config/shell/interactive.d/99-poison.sh"
  HOME=$integ_poison
  PATH=$integ_bin:$PATH
  export HOME PATH
  _doctor_records _dr_check_shell_integrations \
    >"$integ_poison/run.txt" 2>/dev/null
  HOME=$integ_saved_home
  PATH=$integ_saved_path
  export HOME PATH
  integ_poison_result=$(cat "$integ_poison/run.txt")
  _assert_contains "integrations: probe ignores interactive startup" \
    $'ok\ttermnav bash integration' "$integ_poison_result"

  # A bare HOME (no loader chain at all) warns instead of failing.
  integ_bare=$(_tmpdir)
  integ_saved_home=$HOME
  HOME=$integ_bare
  export HOME
  _doctor_records _dr_check_shell_integrations \
    >"$integ_bare/run.txt" 2>/dev/null
  integ_bare_status=$?
  HOME=$integ_saved_home
  export HOME
  integ_bare_result=$(cat "$integ_bare/run.txt")
  if ((integ_shdeps_bin_unset == 1)); then
    unset SHDEPS_BIN
  else
    SHDEPS_BIN=$integ_saved_shdeps_bin
    export SHDEPS_BIN
  fi
  if ((integ_shdeps_dir_unset == 1)); then
    unset SHDEPS_BIN_DIR
  else
    SHDEPS_BIN_DIR=$integ_saved_shdeps_dir
    export SHDEPS_BIN_DIR
  fi
  _assert_exit "integrations: bare HOME exits 0" 0 "$integ_bare_status"
  _assert_contains "integrations: bare HOME warns for bash" \
    $'warn\ttermnav bash integration unavailable' "$integ_bare_result"
  _assert_contains "integrations: the bare HOME warning carries its next step" \
    $'warn\ttermnav bash integration unavailable\tsourcing the termnav shell asset in bash did not load it; run \'dot update\'' \
    "$integ_bare_result"

  # _dr_hint_row: the next step is a hint line on a Dot that has
  # dot_doctor_hint, and joins the detail after "; " on one that does not.
  result=$(_doctor_records _dr_hint_row warn "row" "the cause" "do this")
  _assert_eq "doctor hint row: an older Dot gets the step in the detail" \
    $'warn\trow\tthe cause; do this' "$result"
  result=$(_doctor_records _dr_hint_row fail "row" "" "do this")
  _assert_eq "doctor hint row: a step alone is the detail on an older Dot" \
    $'fail\trow\tdo this' "$result"
  # An info row reads as ok on a Dot without the info kind.
  result=$(_doctor_records _dr_hint_row info "row" "the cause" "")
  _assert_eq "doctor hint row: no step leaves the detail alone" \
    $'ok\trow\tthe cause' "${result/#info/ok}"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_hint_row warn "row" $'the\tcause' $'do\nthis'
  )
  _assert_eq "doctor hint row: a newer Dot gets a separate one-line hint" \
    "$(printf '%s\n' $'warn\trow\tthe cause' $'hint\tdo this\t')" "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_hint_row warn "row" "the cause" ""
  )
  _assert_eq "doctor hint row: an empty step files no hint" \
    $'warn\trow\tthe cause' "$result"
  doctor_status=0
  _dr_hint_row bogus "row" "" "" 2>/dev/null || doctor_status=$?
  _assert_eq "doctor hint row: an unknown level is refused" 2 "$doctor_status"
  doctor_status=0
  _dr_hint_row warn "row" "detail" 2>/dev/null || doctor_status=$?
  _assert_eq "doctor hint row: a missing hint argument is refused" 2 "$doctor_status"

  # _dr_row: detail, steps, and items in one row. An older Dot joins them
  # in that order (detail, sampled items, steps); a newer one keeps the
  # detail on the row and gives each item and step its own line.
  result=$(_doctor_records _dr_row info "row" "why" 0 a b c d e)
  _assert_eq "doctor row: an older Dot joins the detail before the sampled items" \
    $'info\trow\twhy; a; b; c; and 2 more' "$result"
  result=$(_doctor_records _dr_row warn "row" "" 2 "step one" "step two" a)
  _assert_eq "doctor row: an older Dot joins every step after the items" \
    $'warn\trow\ta; step one; step two' "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_item() { _dot_doctor_record item "$1"; }
    # shellcheck disable=SC2329
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_row info "row" $'the\twhy' 0 a b
  )
  _assert_eq "doctor row: a newer Dot keeps the detail on the row and files no step" \
    "$(printf '%s\n' $'info\trow\tthe why' $'item\ta\t' $'item\tb\t')" "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_item() { _dot_doctor_record item "$1"; }
    # shellcheck disable=SC2329
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_row warn "row" "" 3 "step one" "" $'step\ntwo' a
  )
  _assert_eq "doctor row: a newer Dot gives each non-empty step its own line" \
    "$(printf '%s\n' $'warn\trow\t' $'item\ta\t' $'hint\tstep one\t' $'hint\tstep two\t')" \
    "$result"
  doctor_status=0
  _dr_row warn "row" "" 2 "only one step" 2>/dev/null || doctor_status=$?
  _assert_eq "doctor row: fewer steps than counted are refused" 2 "$doctor_status"
  doctor_status=0
  _dr_row warn "row" "" x 2>/dev/null || doctor_status=$?
  _assert_eq "doctor row: a non-numeric step count is refused" 2 "$doctor_status"
  doctor_status=0
  _dr_row bogus "row" "" 0 2>/dev/null || doctor_status=$?
  _assert_eq "doctor row: an unknown level is refused" 2 "$doctor_status"
  # _dr_list_row is _dr_row without a detail and with one step.
  result=$(_doctor_records _dr_list_row warn "row" "do this" a b c d)
  _assert_eq "doctor list row: an older Dot folds the tail before the step" \
    $'warn\trow\ta; b; c; and 1 more; do this' "$result"
  result=$(
    # shellcheck disable=SC2329 # Probed by the helper under test.
    dot_doctor_item() { _dot_doctor_record item "$1"; }
    # shellcheck disable=SC2329
    dot_doctor_hint() { _dot_doctor_record hint "$1"; }
    _doctor_records _dr_list_row warn "row" "" a
  )
  _assert_eq "doctor list row: an empty step files no hint" \
    "$(printf '%s\n' $'warn\trow\t' $'item\ta\t')" "$result"
  doctor_status=0
  _dr_list_row warn "row" 2>/dev/null || doctor_status=$?
  _assert_eq "doctor list row: a missing hint argument is refused" 2 "$doctor_status"

  # A probe that cannot create its temporary directory says what to check.
  result=$(TMPDIR=/nonexistent/doctor-tmp HOME="$TEST_HOME" \
    _doctor_records _dr_check_shell_integrations 2>/dev/null)
  _assert_contains "doctor temp: a missing TMPDIR names itself as the next step" \
    "could not create a temporary directory; check that the temporary directory (TMPDIR, else /tmp) exists, is writable, and has free space, then rerun 'dot doctor'" \
    "$result"

  unset -f _doctor_records
}
