# shellcheck shell=bash
# doctor.sh - doctor coverage.

dot_core_test_doctor() {
  echo ""
  echo "=== Doctor command ==="

  _dot_doctor_load

  drift=$(_dr_lsp_policy_diff "bashls neocmake vtsls" "bashls neocmake vtsls")
  expected="$(printf 'missing=\nstale=')"
  _assert_eq "doctor: lsp policy no drift" "$expected" "$drift"

  drift=$(_dr_lsp_policy_diff "bashls neocmake vtsls" "bashls neocmake")
  expected="$(printf 'missing=vtsls\nstale=')"
  _assert_eq "doctor: lsp policy reports enabled server without fallback" "$expected" "$drift"

  drift=$(_dr_lsp_policy_diff "bashls neocmake" "bashls neocmake vtsls")
  expected="$(printf 'missing=\nstale=vtsls')"
  _assert_eq "doctor: lsp policy reports fallback for disabled server" "$expected" "$drift"

  drift=$(_dr_lsp_policy_diff "bashls neocmake pyright vtsls" "bashls jsonls neocmake")
  expected="$(printf 'missing=pyright,vtsls\nstale=jsonls')"
  _assert_eq "doctor: lsp policy reports sorted missing and stale entries" "$expected" "$drift"

  doctor_health_file=$(_tmpdir)/health.txt
  cat >"$doctor_health_file" <<'HEALTH'
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
    "1 4" "$(_dr_nvim_health_error_counts "$doctor_health_file")"

  cat >"$doctor_health_file" <<'HEALTH'
Snacks.image ~
- OK setup {enabled}
- ERROR None of the tools found: 'magick', 'convert'
HEALTH
  _assert_eq "doctor: counts enabled Snacks.image health errors" \
    "1 0" "$(_dr_nvim_health_error_counts "$doctor_health_file")"

  # Doctor runs against the sandbox HOME. Many checks will warn/fail here
  # because the sandbox is intentionally minimal (no real .bashrc, no yq
  # unless the test host has it on PATH, no cron). These tests assert
  # structural behavior — that the tool renders all sections, emits a
  # summary, and exits with a defined status — not sandbox health.

  doctor_shdeps_bin=$(_tmpdir)
  doctor_path="$doctor_shdeps_bin:$TEST_HOME/.local/bin:$PATH"
  mkdir -p "$doctor_shdeps_bin" "$TEST_HOME/.local/bin" "$TEST_HOME/.local/share/cgraf78"

  _doctor_make_dependency() {
    local dependency="$1"
    shift

    local root="$TEST_HOME/.local/share/cgraf78/$dependency"
    mkdir -p "$root/bin" "$root/share/$dependency"
    printf '# shell asset\n' >"$root/share/$dependency/shell.sh"

    local cmd
    for cmd in "$@"; do
      cat >"$root/bin/$cmd" <<'SH'
#!/usr/bin/env bash
exit 0
SH
      chmod +x "$root/bin/$cmd"
      ln -sf "$root/bin/$cmd" "$TEST_HOME/.local/bin/$cmd"
    done
  }

  _doctor_make_dependency sley sley
  _doctor_make_dependency checkrun autoformat autolint checkrun
  _doctor_make_dependency termnav \
    eza-nvim-links nvim-tmux-open tmux-follow-click \
    wezterm-switch-tab wezterm-move-tab
  _doctor_make_dependency cmdblocks term-notify-sound tmux-copy-last-output
  _doctor_make_dependency git-tools git-absorb-and-rebase
  _doctor_make_dependency tmux-tools \
    tmux-save-session tmux-restore-session tmux-clip-paste
  _doctor_make_dependency ds ds
  _doctor_make_dependency agentguard \
    agent-hook-notification \
    agent-hook-post-bash agent-hook-post-edit agent-hook-post-mcp \
    agent-hook-pre-bash agent-hook-pre-edit agent-hook-pre-mcp \
    agent-hook-prompt-submit \
    agent-hook-session-end agent-hook-session-start \
    agent-hook-stop claude-session-name

  cat >"$doctor_shdeps_bin/shdeps" <<SH
#!/usr/bin/env bash
case "\$1" in
  version)
    printf '%s\n' 'shdeps 0.0-test'
    ;;
  dep-links)
    root="$TEST_HOME/.local/share/\$2"
    bin_dir="\$root/bin"
    [[ -d "\$bin_dir" ]] || exit 1
    shopt -s nullglob
    for target in "\$bin_dir"/*; do
      [[ -f "\$target" && -x "\$target" ]] || continue
      cmd="\${target##*/}"
      printf '%s\t%s/.local/bin/%s\t%s\n' "\$cmd" "$TEST_HOME" "\$cmd" "\$target"
    done | sort
    ;;
  dep-file)
    root="$TEST_HOME/.local/share/\$2"
    asset="\$3"
    if [[ -f "\$root/\$asset" ]]; then
      printf '%s\n' "\$root/\$asset"
    else
      exit 1
    fi
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$doctor_shdeps_bin/shdeps"

  cat >"$TEST_HOME/.local/share/cgraf78/agentguard/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
input=$(cat)
case "$input" in
  *'"git status -uall"'*)
    printf '%s\n' "use dot status instead" >&2
    exit 2
    ;;
  *)
    printf '{}\n'
    ;;
esac
SH
  chmod +x "$TEST_HOME/.local/share/cgraf78/agentguard/bin/agent-hook-pre-bash"
  cat >"$TEST_HOME/.local/share/cgraf78/agentguard/bin/agent-hook-stop" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  chmod +x "$TEST_HOME/.local/share/cgraf78/agentguard/bin/agent-hook-stop"

  result=$(PATH="$doctor_path" "$BIN_DIR/dot" doctor 2>&1 || true)

  _assert_contains "doctor: title banner" "dot doctor" "$result"
  _assert_contains "doctor: Shell environment section" "Shell environment" "$result"
  _assert_contains "doctor: Dotfiles base repo section" "Dotfiles base repo" "$result"
  _assert_contains "doctor: Overlays section" "Overlays" "$result"
  _assert_contains "doctor: Tools section" "Tools" "$result"
  _assert_contains "doctor: checks schema validation deps" "schema validation deps" "$result"
  _assert_contains "doctor: checks sley front door" "sley" "$result"
  _assert_contains "doctor: Shell integrations section" "Shell integrations" "$result"
  _assert_contains "doctor: Git hooks section" "Git hooks" "$result"
  _assert_contains "doctor: Agent hooks section" "Agent hooks" "$result"
  _assert_contains "doctor: checks shdeps-managed command links" "checkrun bin links" "$result"
  _assert_contains "doctor: checks all configured agent hooks" "agentguard bin links" "$result"
  # ds is a declared github dep with a bin; guard against it being dropped from
  # the checked set again (it was previously silently omitted).
  _assert_contains "doctor: checks the ds command link" "ds bin links" "$result"
  _assert_contains "doctor: checks shdeps-managed shell assets" "agentguard shell asset" "$result"
  _assert_contains "doctor: smokes agent pre-bash guard" \
    "agent pre-bash guards raw dotfiles git status" "$result"
  _assert_contains "doctor: smokes agent stop hook" "agent stop hook runs" "$result"
  _assert_contains "doctor: Config merges section" "Config merges" "$result"
  _assert_contains "doctor: Cron section" "Cron" "$result"
  _assert_contains "doctor: summary line" "passed" "$result"

  doctor_ci_home=$(_tmpdir)
  mkdir -p \
    "$doctor_ci_home/.local/bin" \
    "$doctor_ci_home/.local/lib/dot/core" \
    "$doctor_ci_home/.config/shell/env.d" \
    "$doctor_ci_home/.config/shell/interactive.d"
  cp "$BIN_DIR/dot" "$doctor_ci_home/.local/bin/dot"
  cp "$REAL_HOME/.local/lib/dot/core/"*.sh "$doctor_ci_home/.local/lib/dot/core/"
  cp -R "$REAL_HOME/.local/lib/dot/core/doctor" "$doctor_ci_home/.local/lib/dot/core/"
  cp -R "$REAL_HOME/.local/lib/dot/core/repos" "$doctor_ci_home/.local/lib/dot/core/"
  printf '%s\n' '. ~/.config/shell/shell-loader.sh' >"$doctor_ci_home/.bashrc"
  printf '%s\n' '. ~/.config/shell/shell-loader.sh' >"$doctor_ci_home/.zshrc"
  printf '%s\n' '# test env loader' >"$doctor_ci_home/.config/shell/env-noninteractive.sh"
  cat >"$doctor_ci_home/.local/bin/agent-hook-pre-bash" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '{}\n'
SH
  chmod +x "$doctor_ci_home/.local/bin/dot" "$doctor_ci_home/.local/bin/agent-hook-pre-bash"
  git -C "$doctor_ci_home" init >/dev/null 2>&1
  git -C "$doctor_ci_home" add \
    .local/bin/dot \
    .local/lib/dot/core/doctor.sh \
    .local/lib/dot/core/doctor >/dev/null 2>&1

  result=$(
    HOME="$doctor_ci_home" PATH="$doctor_shdeps_bin:$doctor_ci_home/.local/bin:$PATH" \
      "$doctor_ci_home/.local/bin/dot" doctor 2>&1 || true
  )
  _assert_contains "doctor: accepts CI regular checkout base" \
    "dotfiles checkout exists" "$result"
  _assert_not_contains "doctor: CI checkout does not require bare repo" \
    ".dotfiles missing" "$result"
  _assert_contains "doctor: CI checkout allows raw git smoke" \
    "agent pre-bash allows raw git status in checkout" "$result"
  _assert_not_contains "doctor: CI checkout raw git is not a failure" \
    "agent pre-bash allows raw dotfiles git status" "$result"

  # Shell config dir checks resolve via DOT_SHELL_ENV_DIR /
  # DOT_SHELL_INTERACTIVE_DIR; the fixture created both dirs above, so a correct
  # constant reports each as present. A drifted constant would probe a different
  # leaf and report it missing instead.
  _assert_contains "doctor: shell env.d dir checked via constant" \
    "env.d/ exists" "$result"
  _assert_contains "doctor: shell interactive.d dir checked via constant" \
    "interactive.d/ exists" "$result"

  # Exit status must be 0 (all OK) or 1 (any FAIL) — never a script crash.
  PATH="$doctor_path" "$BIN_DIR/dot" doctor >/dev/null 2>&1
  _doctor_rc=$?
  if [[ $_doctor_rc -eq 0 || $_doctor_rc -eq 1 ]]; then
    _pass "doctor: exit code is 0 or 1"
  else
    _fail "doctor: exit code is 0 or 1 (got $_doctor_rc)"
  fi

  doctor_precmd_bin=$(_tmpdir)
  doctor_precmd_marker=$(_tmpdir)/precmd-marker
  cat >"$doctor_precmd_bin/zsh" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version)
    printf '%s\n' "zsh 5.9-test"
    ;;
  -ic)
    # The real zsh prompt starts an async git-status precmd hook. Doctor only
    # needs the deferred sley completion registration hook; running every
    # precmd hook can leave background writers in its isolated cache.
    if [[ "${2:-}" == *'precmd_functions'* ]]; then
      printf '%s\n' "ran broad precmd loop" >"$DOCTOR_PRECMD_MARKER"
    fi
    mkdir -p "$XDG_CACHE_HOME/shell"
    : >"$XDG_CACHE_HOME/shell/sley.zsh"
    printf '%s\n' "loaded=1"
    printf '%s\n' "termnav=1"
    printf '%s\n' "zsh_complete=yes"
    printf '%s\n' "zsh_compdef=_sley_zsh_complete"
    ;;
  *)
    ;;
esac
SH
  chmod +x "$doctor_precmd_bin/zsh"
  result=$(DOCTOR_PRECMD_MARKER="$doctor_precmd_marker" PATH="$doctor_precmd_bin:$doctor_path" "$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: fake zsh probe still passes sley integration" "sley zsh integration" "$result"
  _assert_file_missing "doctor: zsh probe does not run unrelated precmd hooks" "$doctor_precmd_marker"

  doctor_dep_links_bin=$(_tmpdir)
  cat >"$doctor_dep_links_bin/shdeps" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  dep-links)
    case "${2:-}" in
      cgraf78/emptydep)
        exit 0
        ;;
      cgraf78/malformeddep)
        printf '%s\t%s\n' "bad-row" "missing-target"
        ;;
      cgraf78/directdep)
        printf '%s\t%s\t%s\n' "direct-tool" "$DOCTOR_DIRECT_TOOL" "$DOCTOR_DIRECT_TOOL"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  *)
    exit 1
    ;;
esac
SH
  chmod +x "$doctor_dep_links_bin/shdeps"
  doctor_direct_tool="$TEST_HOME/.local/bin/direct-tool"
  cat >"$doctor_direct_tool" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$doctor_direct_tool"

  result=$(PATH="$doctor_dep_links_bin:$PATH" _dr_check_shdeps_bin_group warn emptydep 2>&1)
  _assert_contains "doctor: empty shdeps dep-links rows are reported" \
    "emptydep bin links missing" "$result"

  result=$(PATH="$doctor_dep_links_bin:$PATH" _dr_check_shdeps_bin_group warn malformeddep 2>&1)
  _assert_contains "doctor: malformed shdeps dep-links rows are reported" \
    "malformeddep bin links malformed" "$result"

  result=$(
    DOCTOR_DIRECT_TOOL="$doctor_direct_tool" \
      PATH="$doctor_dep_links_bin:$PATH" \
      _dr_check_shdeps_bin_group warn directdep 2>&1
  )
  _assert_contains "doctor: direct executable command targets are accepted" \
    "directdep bin links" "$result"
  _assert_not_contains "doctor: direct executable command target is not forced to symlink" \
    "direct-tool not linked" "$result"

  rm -f "$TEST_HOME/.local/bin/sley"
  rm -f "$TEST_HOME/.local/bin/autoformat"
  rm -f "$TEST_HOME/.local/bin/autolint"
  rm -f "$TEST_HOME/.local/bin/checkrun"
  rm -f "$TEST_HOME/.local/bin/eza-nvim-links"
  rm -f "$TEST_HOME/.local/bin/nvim-tmux-open"
  rm -f "$TEST_HOME/.local/bin/tmux-follow-click"
  rm -f "$TEST_HOME/.local/bin/term-notify-sound"
  rm -f "$TEST_HOME/.local/bin/tmux-copy-last-output"
  rm -f "$TEST_HOME/.local/bin/git-absorb-and-rebase"
  rm -f "$TEST_HOME/.local/bin/tmux-save-session"
  rm -f "$TEST_HOME/.local/bin/tmux-restore-session"
  rm -f "$TEST_HOME/.local/bin/tmux-clip-paste"
  rm -f "$TEST_HOME/.local/bin/wezterm-switch-tab"
  rm -f "$TEST_HOME/.local/bin/agent-hook-notification"
  rm -f "$TEST_HOME/.local/bin/agent-hook-pre-bash"
  rm -f "$TEST_HOME/.local/bin/agent-hook-pre-edit"
  rm -f "$TEST_HOME/.local/bin/agent-hook-pre-mcp"
  rm -f "$TEST_HOME/.local/bin/agent-hook-post-bash"
  rm -f "$TEST_HOME/.local/bin/agent-hook-post-edit"
  rm -f "$TEST_HOME/.local/bin/agent-hook-post-mcp"
  rm -f "$TEST_HOME/.local/bin/agent-hook-prompt-submit"
  rm -f "$TEST_HOME/.local/bin/agent-hook-session-end"
  rm -f "$TEST_HOME/.local/bin/agent-hook-session-start"
  rm -f "$TEST_HOME/.local/bin/agent-hook-stop"
  rm -f "$TEST_HOME/.local/bin/claude-session-name"
  rm -rf "$TEST_HOME/.local/share/cgraf78"

  # A sandbox without ~/.bashrc should get flagged as a FAIL (bashrc is
  # checked by the shell section). Ensures the failure path is wired up,
  # not just the happy path. Remove .bashrc unconditionally so the assertion
  # is deterministic rather than silently skipped when the sandbox has one.
  rm -f "$TEST_HOME/.bashrc"
  result=$(PATH="$doctor_path" "$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: flags missing .bashrc" ".bashrc missing" "$result"

  doctor_merge_target=$(_tmpdir)/merge-output
  mkdir -p "$TEST_HOME/.codex"
  printf '%s\n' "merge output" >"$doctor_merge_target"
  rm -f "$TEST_HOME/.codex/config.toml"
  ln -s "$doctor_merge_target" "$TEST_HOME/.codex/config.toml"
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: flags symlinked merge-managed config output" \
    "merge-managed config output symlink" "$result"
  rm -f "$TEST_HOME/.codex/config.toml"

  doctor_overlay_bare=$(_tmpdir)
  doctor_wrong_target=$(_tmpdir)/wrong-target
  git init --bare "$doctor_overlay_bare" >/dev/null 2>&1
  rm -rf "$TEST_HOME/.dotfiles-work"
  dot_fixture_clone_repo "$doctor_overlay_bare" "$TEST_HOME/.dotfiles-work"
  mkdir -p "$TEST_HOME/.dotfiles-work/home" "$TEST_HOME/.local/state/dot"
  printf '%s\n' "expected" >"$TEST_HOME/.dotfiles-work/home/.doctor-overlay-link"
  printf '%s\n' "wrong" >"$doctor_wrong_target"
  ln -sf "$doctor_wrong_target" "$TEST_HOME/.doctor-overlay-link"
  printf '%s\t%s\n' ".doctor-overlay-link" "work" >"$TEST_HOME/.local/state/dot/overlay-links"
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: flags overlay symlink target drift" "overlay symlink issue" "$result"
  rm -f "$TEST_HOME/.doctor-overlay-link"
  : >"$TEST_HOME/.local/state/dot/overlay-links"
  rm -rf "$TEST_HOME/.dotfiles-work" "$doctor_overlay_bare"

  doctor_key_bare=$(_tmpdir)
  git init --bare "$doctor_key_bare" >/dev/null 2>&1
  rm -rf "$TEST_HOME/.dotfiles-work"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$doctor_key_bare
CONF
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.ssh" <<'SSH'
Host github-dotfiles-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/dotfiles-work-doctor-test-nonexistent
  IdentitiesOnly yes
SSH
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: required overlay missing key fails" "SSH deploy key missing" "$result"

  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<CONF
url=$doctor_key_bare
optional=true
CONF
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: optional overlay missing key skips" "optional deploy key not present" "$result"
  _assert_not_contains "doctor: optional overlay missing key is not failure" \
    "SSH deploy key missing" "$result"
  rm -f "$TEST_HOME/.config/dot/overlays.d/10-work.ssh"
  cat >"$TEST_HOME/.config/dot/overlays.d/10-work.conf" <<'CONF'
url=git@example.com:work.git
CONF
  rm -rf "$doctor_key_bare"

  doctor_work_bare=$(_tmpdir)
  doctor_extra_bare=$(_tmpdir)
  git init --bare "$doctor_work_bare" >/dev/null 2>&1
  git init --bare "$doctor_extra_bare" >/dev/null 2>&1
  dot_fixture_clone_repo "$doctor_work_bare" "$TEST_HOME/.dotfiles-work"
  dot_fixture_clone_repo "$doctor_extra_bare" "$TEST_HOME/.dotfiles-extra"
  mkdir -p "$TEST_HOME/.dotfiles-work/home" "$TEST_HOME/.dotfiles-extra/home"
  printf '%s\n' "work" >"$TEST_HOME/.dotfiles-work/home/.doctor-shared-link"
  printf '%s\n' "extra" >"$TEST_HOME/.dotfiles-extra/home/.doctor-shared-link"
  cat >"$TEST_HOME/.config/dot/overlays.d/20-extra.conf" <<CONF
url=$doctor_extra_bare
CONF
  ln -sf "$TEST_HOME/.dotfiles-extra/home/.doctor-shared-link" "$TEST_HOME/.doctor-shared-link"
  {
    printf '%s\t%s\n' ".doctor-shared-link" "work"
    printf '%s\t%s\n' ".doctor-shared-link" "extra"
  } >"$TEST_HOME/.local/state/dot/overlay-links"
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: accepts last-wins overlay symlink" "overlay symlinks healthy" "$result"
  _assert_not_contains "doctor: ignores losing manifest duplicate" "overlay symlink issue" "$result"
  rm -f "$TEST_HOME/.doctor-shared-link" "$TEST_HOME/.config/dot/overlays.d/20-extra.conf"
  : >"$TEST_HOME/.local/state/dot/overlay-links"
  rm -rf "$TEST_HOME/.dotfiles-work" "$TEST_HOME/.dotfiles-extra" "$doctor_work_bare" "$doctor_extra_bare"

  _real_bash=$(command -v bash)
  _fake_bash_bin=$(_tmpdir)
  cat >"$_fake_bash_bin/bash" <<FAKEBASH
#!$_real_bash
if [[ "\${1:-}" == "-c" ]]; then
  printf '%s\n' '4.9'
  exit 0
fi
if [[ "\${1:-}" == "--version" ]]; then
  printf '%s\n' 'GNU bash, version 5.3.3(1)-release (x86_64-alpine-linux-musl)'
  _i=0
  while [[ \$_i -lt 200000 ]]; do
    printf 'extra version line %s\n' "\$_i"
    _i=\$((\$_i + 1))
  done
  exit 0
fi
exec "$_real_bash" "\$@"
FAKEBASH
  chmod +x "$_fake_bash_bin/bash"
  result=$(PATH="$_fake_bash_bin:$PATH" "$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: handles early-closing bash version probe" "Dotfiles base repo" "$result"
  _assert_contains "doctor: uses isolated bash -c version probe" "bash version (4.9)" "$result"

  _noisy_bash_env=$(_tmpdir)/bashenv
  printf '%s\n' 'echo noisy-bashenv' >"$_noisy_bash_env"
  result=$(BASH_ENV="$_noisy_bash_env" "$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: ignores BASH_ENV output in bash version probe" "Dotfiles base repo" "$result"
  _assert_not_contains "doctor: avoids BASH_ENV output in version arithmetic" "unbound variable" "$result"

  # hive-memory binary/config skew: the dotfiles-managed hm config can sync to
  # a machine before the hive-memory release that understands a new key, and
  # hm downgrades unknown keys to a warning, so the configured memory policy
  # silently stays inactive. The doctor check must surface that skew.
  doctor_hm_bin=$(_tmpdir)
  cat >"$doctor_hm_bin/hm" <<'SH'
#!/usr/bin/env bash
if [[ "${DOCTOR_HM_SKEW:-0}" == "1" ]]; then
  printf 'warning: unknown config key: defaults.context_strategy\n' >&2
fi
printf '[]\n'
exit 0
SH
  chmod +x "$doctor_hm_bin/hm"

  result=$(DOCTOR_HM_SKEW=1 PATH="$doctor_hm_bin:$PATH" _dr_check_hive_memory 2>&1)
  _assert_contains "doctor: hm config skew is reported" \
    "hm binary behind configured keys" "$result"
  _assert_contains "doctor: hm config skew names the key" \
    "defaults.context_strategy" "$result"

  result=$(PATH="$doctor_hm_bin:$PATH" _dr_check_hive_memory 2>&1)
  _assert_contains "doctor: hm without skew passes" \
    "hm understands configured keys" "$result"

  # System dirs only (no ~/.local/bin), so a real installed hm is invisible.
  doctor_no_hm_bin=$(_tmpdir)
  result=$(PATH="$doctor_no_hm_bin:/usr/bin:/bin" _dr_check_hive_memory 2>&1 || true)
  _assert_contains "doctor: missing hm is skipped" "hm not installed" "$result"
}
