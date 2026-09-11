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

  echo ""
  echo "=== Base doctor extensions ==="

  # The standalone suite owns core runtime/repository/overlay health. This
  # retained suite loads only the public extension API and client policy.
  _dot_doctor_load
  _test_load_dot_doctor_api "$TEST_HOME"
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
  ln -s "$(command -v cat)" "$doctor_no_crontab_bin/cat"
  result=$(
    # shellcheck disable=SC2329 # Invoked indirectly by the Cron doctor check.
    _dr_account_home() {
      REPLY=$HOME
    }
    DOT_TEST=0 HOME="$TEST_HOME" PATH="$doctor_no_crontab_bin" \
      _doctor_records _dr_check_cron
  )
  _assert_contains "doctor cron: missing production crontab is reported" \
    "crontab not found" "$result"

  : >"$doctor_crontab_log"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    _doctor_records _dr_check_cron)
  _assert_eq "doctor cron: explicit test double is invoked" \
    "-l" "$(cat "$doctor_crontab_log")"
  _assert_contains "doctor cron: explicit test state is diagnosed" \
    "auto-update cron entry present" "$result"

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
  *) exit 1 ;;
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

  cp "$REAL_HOME/.local/lib/dotfiles/shell-loader.sh" \
    "$TEST_HOME/.local/lib/dotfiles/shell-loader.sh"
  mkdir -p "$TEST_HOME/.config/shell/env.d" \
    "$TEST_HOME/.config/shell/interactive.d" \
    "$TEST_HOME/.config/shdeps"
  # shellcheck disable=SC2016 # Fixture startup files retain literal HOME.
  printf '%s\n' \
    '. "$HOME/.local/lib/dotfiles/shell-loader.sh"' \
    '_shell_load_env bash' >"$TEST_HOME/.bashrc"
  # shellcheck disable=SC2016 # Fixture startup files retain literal HOME.
  printf '%s\n' '. "$HOME/.local/lib/dotfiles/shell-loader.sh"' \
    >"$TEST_HOME/.zshrc"
  # shellcheck disable=SC2016 # Fixture startup files retain literal HOME.
  printf '%s\n' \
    'export BASH_ENV="$HOME/.config/shell/env-noninteractive.sh"' \
    >"$TEST_HOME/.config/shell/env.d/50-core.sh"
  printf '%s\n' '# managed noninteractive shell fixture' \
    >"$TEST_HOME/.config/shell/env-noninteractive.sh"
  printf '%s\n' 'fixture/tool github:repo tool' \
    >"$TEST_HOME/.config/shdeps/deps.conf"

  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    "$DOT_SOURCE_ROOT/bin/dot" doctor 2>&1 || true)
  _assert_contains "doctor integration: renders the standalone title" \
    "dot doctor" "$result"
  _assert_contains "doctor integration: renders client repository health" \
    "Client repository" "$result"
  for expected in "Shell environment" "Tools" "Shell integrations" \
    "Agent rules" "Cron" "Worktrees"; do
    _assert_contains "doctor integration: renders base section $expected" \
      "$expected" "$result"
  done
  for absent in "Git hooks" "Agent hooks" "Hive Memory" "Neovim"; do
    _assert_not_contains "doctor integration: omits capability section $absent" \
      "$absent" "$result"
  done
  _assert_contains "doctor integration: validates managed BASH_ENV" \
    "BASH_ENV (~/.config/shell/env-noninteractive.sh)" "$result"
  _assert_contains "doctor integration: renders an aggregate summary" \
    "passed" "$result"

  rm -f "$TEST_HOME/.bashrc"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    "$DOT_SOURCE_ROOT/bin/dot" doctor 2>&1 || true)
  _assert_contains "doctor integration: flags a missing bash startup file" \
    ".bashrc missing" "$result"

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

  # A zsh-free PATH pins the skip verdict deterministically even on
  # hosts with zsh installed; bash must still answer from the asset.
  # Dropping the stub shdeps from that PATH pins the unresolvable
  # verdict without any host shdeps leaking in.
  integ_nz_bin=$(_tmpdir)
  ln -s "$(command -v bash)" "$integ_nz_bin/bash"
  ln -s "$(command -v cat)" "$integ_nz_bin/cat"
  ln -s "$(command -v mktemp)" "$integ_nz_bin/mktemp"
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

  unset -f _doctor_records
}
