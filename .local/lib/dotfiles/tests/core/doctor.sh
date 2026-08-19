# shellcheck shell=bash
# doctor.sh - dotfiles-owned doctor extension coverage.

dot_core_test_doctor() {
  local result expected drift doctor_bin doctor_crontab_log doctor_direct_tool doctor_hm_bin
  local doctor_no_hm_bin doctor_nvim_log doctor_real_bash doctor_shell_marker
  local dependency root cmd

  echo ""
  echo "=== Dotfiles doctor extensions ==="

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

  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains "doctor: warns when OpenCode AgentGuard plugin is absent" \
    "OpenCode AgentGuard plugin missing" "$result"

  printf '%s\n' 'export const userOwned = true' \
    >"$TEST_HOME/.config/opencode/plugins/dotfiles-agentguard.js"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains "doctor: warns when OpenCode AgentGuard plugin is unmanaged" \
    "OpenCode AgentGuard plugin unmanaged" "$result"

  cat >"$TEST_HOME/.config/opencode/plugins/dotfiles-agentguard.js" <<'PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({});
PLUGIN
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_opencode_agentguard)
  _assert_contains "doctor: accepts the managed OpenCode AgentGuard plugin" \
    "OpenCode AgentGuard plugin installed" "$result"

  drift=$(_dr_lsp_policy_diff "bashls neocmake vtsls" "bashls neocmake vtsls")
  expected="$(printf 'missing=\nstale=')"
  _assert_eq "doctor: lsp policy no drift" "$expected" "$drift"
  drift=$(_dr_lsp_policy_diff "bashls neocmake pyright vtsls" "bashls jsonls neocmake")
  expected="$(printf 'missing=pyright,vtsls\nstale=jsonls')"
  _assert_eq "doctor: lsp policy reports sorted missing and stale entries" \
    "$expected" "$drift"

  doctor_nvim_log=$(_tmpdir)/health.txt
  cat >"$doctor_nvim_log" <<'HEALTH'
Snacks.image ~
- WARNING setup {disabled}
- ERROR None of the tools found: 'magick', 'convert'
- ERROR Tool not found: 'gs'

Snacks.input ~
- OK setup {enabled}
- ERROR `vim.ui.input` is not set to `Snacks.input`

Snacks.notifier ~
- OK setup {enabled}
- ERROR is not ready

Snacks.picker ~
- ERROR picker broke
HEALTH
  _assert_eq "doctor: ignores disabled Snacks and headless UI health noise" \
    "1 4" "$(_dr_nvim_health_error_counts "$doctor_nvim_log")"

  cat >"$doctor_bin/shdeps" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  version)
    printf '%s\n' 'shdeps 0.0-test'
    ;;
  dep-links)
    case "${2:-}" in
      cgraf78/emptydep)
        exit 0
        ;;
      cgraf78/malformeddep)
        printf '%s\t%s\n' bad-row missing-target
        ;;
      cgraf78/directdep)
        printf '%s\t%s\t%s\n' direct-tool "$DOCTOR_DIRECT_TOOL" "$DOCTOR_DIRECT_TOOL"
        ;;
      *)
        root="$HOME/.local/share/${2:-}"
        [[ -d $root/bin ]] || exit 1
        for target in "$root"/bin/*; do
          [[ -f $target && -x $target ]] || continue
          printf '%s\t%s/.local/bin/%s\t%s\n' \
            "${target##*/}" "$HOME" "${target##*/}" "$target"
        done
        ;;
    esac
    ;;
  dep-file)
    path="$HOME/.local/share/${2:-}/${3:-}"
    [[ -f $path ]] || exit 1
    printf '%s\n' "$path"
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$doctor_bin/shdeps"
  doctor_direct_tool="$TEST_HOME/.local/bin/direct-tool"
  mkdir -p "$TEST_HOME/.local/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$doctor_direct_tool"
  chmod +x "$doctor_direct_tool"

  result=$(PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn emptydep)
  _assert_contains "doctor: empty shdeps dep-links rows are reported" \
    "emptydep bin links missing" "$result"
  result=$(PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn malformeddep)
  _assert_contains "doctor: malformed shdeps dep-links rows are reported" \
    "malformeddep bin links malformed" "$result"
  result=$(DOCTOR_DIRECT_TOOL="$doctor_direct_tool" PATH="$doctor_bin:$PATH" \
    _doctor_records _dr_check_shdeps_bin_group warn directdep)
  _assert_contains "doctor: direct executable command targets are accepted" \
    "directdep bin links" "$result"
  _assert_not_contains "doctor: direct executable target is not forced to symlink" \
    "direct-tool not linked" "$result"

  doctor_hm_bin=$(_tmpdir)
  cat >"$doctor_hm_bin/hm" <<'SH'
#!/usr/bin/env bash
if [[ ${DOCTOR_HM_SKEW:-0} == 1 ]]; then
  printf 'warning: unknown config key: defaults.context_strategy\n' >&2
fi
printf '[]\n'
SH
  chmod +x "$doctor_hm_bin/hm"
  result=$(DOCTOR_HM_SKEW=1 PATH="$doctor_hm_bin:$PATH" \
    _doctor_records _dr_check_hive_memory)
  _assert_contains "doctor: hm config skew is reported" \
    "hm binary behind configured keys" "$result"
  _assert_contains "doctor: hm config skew names the key" \
    "defaults.context_strategy" "$result"
  result=$(PATH="$doctor_hm_bin:$PATH" _doctor_records _dr_check_hive_memory)
  _assert_contains "doctor: hm without skew passes" \
    "hm understands configured keys" "$result"
  doctor_no_hm_bin=$(_tmpdir)
  result=$(PATH="$doctor_no_hm_bin:/usr/bin:/bin" \
    _doctor_records _dr_check_hive_memory)
  _assert_contains "doctor: missing hm is skipped" "hm not installed" "$result"

  # Build a representative client installation and run the actual standalone
  # coordinator. Core and client sections must coexist, and application checks
  # must publish through the isolated doctor worker contract.
  cp "$REAL_HOME/.local/lib/dotfiles/shell-loader.sh" \
    "$TEST_HOME/.local/lib/dotfiles/shell-loader.sh"
  cp -R "$REAL_HOME/.local/lib/dotfiles/git-hooks" \
    "$TEST_HOME/.local/lib/dotfiles/"
  mkdir -p "$TEST_HOME/.config/shell/env.d" \
    "$TEST_HOME/.config/shell/interactive.d" \
    "$TEST_HOME/.config/shdeps"
  # shellcheck disable=SC2016 # Fixture startup files must retain literal HOME.
  printf '%s\n' \
    '. "$HOME/.local/lib/dotfiles/shell-loader.sh"' \
    '_shell_load_env bash' \
    >"$TEST_HOME/.bashrc"
  # shellcheck disable=SC2016 # Fixture startup files must retain literal HOME.
  printf '%s\n' '. "$HOME/.local/lib/dotfiles/shell-loader.sh"' >"$TEST_HOME/.zshrc"
  # shellcheck disable=SC2016 # Fixture startup files must retain literal HOME.
  printf '%s\n' \
    'export BASH_ENV="$HOME/.config/shell/env-noninteractive.sh"' \
    >"$TEST_HOME/.config/shell/env.d/50-core.sh"
  printf '%s\n' '# managed noninteractive shell fixture' \
    >"$TEST_HOME/.config/shell/env-noninteractive.sh"
  printf '%s\n' 'fixture/tool github:repo tool' >"$TEST_HOME/.config/shdeps/deps.conf"
  git --git-dir="$DOTFILES" config core.hooksPath \
    "$TEST_HOME/.local/lib/dotfiles/git-hooks"

  for dependency in sley checkrun termnav cmdblocks git-tools tmux-tools ds agentguard; do
    root="$TEST_HOME/.local/share/cgraf78/$dependency"
    mkdir -p "$root/bin" "$root/share/$dependency"
    printf '# shell asset\n' >"$root/share/$dependency/shell.sh"
    cmd=$dependency
    [[ $dependency != git-tools ]] || cmd=git-absorb-and-rebase
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$root/bin/$cmd"
    chmod +x "$root/bin/$cmd"
    ln -sf "$root/bin/$cmd" "$TEST_HOME/.local/bin/$cmd"
  done

  cat >"$TEST_HOME/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case $input in
  *'"git status -uall"'*)
    printf '%s\n' 'use dot status instead' >&2
    exit 2
    ;;
  *) printf '{}\n' ;;
esac
SH
  cat >"$TEST_HOME/.local/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  cat >"$doctor_bin/nvim" <<'SH'
#!/usr/bin/env bash
if [[ ${1:-} == --version ]]; then
  printf '%s\n' 'NVIM v0.12.0-test'
fi
exit 0
SH
  chmod +x "$TEST_HOME/.local/bin/agent-hook-pre-bash" \
    "$TEST_HOME/.local/bin/agent-hook-stop" "$doctor_bin/nvim"

  doctor_real_bash=$(command -v bash)
  doctor_shell_marker=$doctor_bin/interactive-bash
  cat >"$doctor_bin/bash" <<'SH'
#!/bin/sh
for arg in "$@"; do
  case $arg in
    -i*) : >"$DOCTOR_BASH_INTERACTIVE_MARKER" ;;
  esac
done
exec "$DOCTOR_REAL_BASH" "$@"
SH
  chmod +x "$doctor_bin/bash"

  result=$(DOCTOR_REAL_BASH="$doctor_real_bash" \
    DOCTOR_BASH_INTERACTIVE_MARKER="$doctor_shell_marker" \
    HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    _doctor_records _dr_check_shell_integrations)
  _assert_eq "doctor integration: shell probe avoids interactive job control" \
    "no" "$(test -e "$doctor_shell_marker" && printf yes || printf no)"
  rm -f "$doctor_bin/bash"

  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    "$DOT_SOURCE_ROOT/bin/dot" doctor 2>&1 || true)
  _assert_contains "doctor integration: renders the standalone title" \
    "dot doctor" "$result"
  _assert_contains "doctor integration: renders core client repository health" \
    "Client repository" "$result"
  for expected in \
    "Shell environment" "Tools" "Shell integrations" "Git hooks" \
    "Agent hooks" "Hive Memory" "Cron" "Neovim"; do
    _assert_contains "doctor integration: renders $expected" "$expected" "$result"
  done
  _assert_contains "doctor integration: checks shdeps-managed command links" \
    "checkrun bin links" "$result"
  _assert_contains "doctor integration: smokes the pre-bash guard" \
    "agent pre-bash guards raw dotfiles git status" "$result"
  _assert_contains "doctor integration: smokes the stop hook" \
    "agent stop hook runs" "$result"
  _assert_contains "doctor integration: validates managed BASH_ENV" \
    "BASH_ENV (~/.config/shell/env-noninteractive.sh)" "$result"
  _assert_not_contains "doctor integration: ignores sanitized worker BASH_ENV" \
    "BASH_ENV unset" "$result"
  _assert_contains "doctor integration: renders an aggregate summary" \
    "passed" "$result"

  rm -f "$TEST_HOME/.bashrc"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    DOT_TEST_CRONTAB="$doctor_bin/crontab" \
    DOT_TEST_CRONTAB_LOG="$doctor_crontab_log" \
    "$DOT_SOURCE_ROOT/bin/dot" doctor 2>&1 || true)
  _assert_contains "doctor integration: flags a missing bash startup file" \
    ".bashrc missing" "$result"

  rm -rf "$TEST_HOME/.config/shell/env.d"
  result=$(HOME="$TEST_HOME" PATH="$doctor_bin:$TEST_HOME/.local/bin:$PATH" \
    "$DOT_SOURCE_ROOT/bin/dot" doctor 2>&1 || true)
  _assert_contains "doctor integration: missing shell config recommends convergence" \
    "run dot update --force" "$result"

  unset -f _doctor_records
}
