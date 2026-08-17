# shellcheck shell=bash
# doctor.sh - doctor coverage.

dot_core_test_doctor() {
  echo ""
  echo "=== Doctor command ==="

  _dot_doctor_load

  echo "=== Base repository topologies ==="

  # Exercise every repository shape accepted by the current doctor through the
  # same public section check. Keeping these as real Git repositories prevents
  # the standalone extraction from accidentally preserving only the spelling
  # of today's command wrapper while changing which client layouts are valid.
  _doctor_base_repo_topology_result() {
    local topology="$1" fixture_home fixture_git_dir
    fixture_home=$(_tmpdir)
    fixture_home=$(cd "$fixture_home" && pwd -P)
    fixture_git_dir="$fixture_home/.dotfiles"

    mkdir -p "$fixture_home/.local/bin"
    cat >"$fixture_home/.local/bin/dot" <<'SH'
#!/usr/bin/env bash
exit 0
SH
    chmod +x "$fixture_home/.local/bin/dot"

    case "$topology" in
      legacy-bare)
        git init --bare "$fixture_git_dir" >/dev/null 2>&1
        ;;
      canonical-worktree)
        git init --bare "$fixture_git_dir" >/dev/null 2>&1
        git --git-dir="$fixture_git_dir" config core.bare false
        git --git-dir="$fixture_git_dir" config core.worktree "$fixture_home"
        ;;
      ordinary-checkout | unrelated-checkout)
        git -C "$fixture_home" init >/dev/null 2>&1
        if [[ "$topology" == ordinary-checkout ]]; then
          mkdir -p "$fixture_home/.local/lib/dotfiles/legacy-dot/core/doctor"
          printf '%s\n' '# fixture doctor entry point' \
            >"$fixture_home/.local/lib/dotfiles/legacy-dot/core/doctor.sh"
          printf '%s\n' '# fixture doctor runtime' \
            >"$fixture_home/.local/lib/dotfiles/legacy-dot/core/doctor/runtime.sh"
          git -C "$fixture_home" add \
            .local/bin/dot \
            .local/lib/dotfiles/legacy-dot/core/doctor.sh \
            .local/lib/dotfiles/legacy-dot/core/doctor/runtime.sh
        else
          printf '%s\n' '# unrelated repository' >"$fixture_home/README.md"
          git -C "$fixture_home" add README.md
        fi
        ;;
      *)
        printf 'unknown doctor topology fixture: %s\n' "$topology" >&2
        return 2
        ;;
    esac

    (
      _DR_PASS_COUNT=0
      _DR_WARN_COUNT=0
      _DR_FAIL_COUNT=0
      HOME="$fixture_home" \
        DOTFILES="$fixture_git_dir" \
        GIT="git --git-dir=$fixture_git_dir --work-tree=$fixture_home" \
        DOT_BIN="$fixture_home/.local/bin/dot" \
        _dr_check_base_repo
    )
  }

  result=$(_doctor_base_repo_topology_result legacy-bare)
  _assert_contains "doctor topology: accepts legacy core.bare client" \
    "core.bare = true" "$result"
  _assert_contains "doctor topology: legacy client resolves HOME work tree" \
    "work-tree resolves to \$HOME" "$result"
  _assert_not_contains "doctor topology: legacy client is not reported missing" \
    ".dotfiles missing" "$result"

  result=$(_doctor_base_repo_topology_result canonical-worktree)
  _assert_contains "doctor topology: accepts canonical explicit worktree client" \
    "core.bare = false with explicit worktree" "$result"
  _assert_contains "doctor topology: canonical client resolves HOME work tree" \
    "work-tree resolves to \$HOME" "$result"
  _assert_not_contains "doctor topology: canonical client is not reported missing" \
    ".dotfiles missing" "$result"

  result=$(_doctor_base_repo_topology_result ordinary-checkout)
  _assert_contains "doctor topology: accepts identified checkout rooted at HOME" \
    "dotfiles checkout exists (regular checkout rooted at \$HOME)" "$result"
  _assert_not_contains "doctor topology: identified HOME checkout needs no separate git dir" \
    ".dotfiles missing" "$result"

  result=$(_doctor_base_repo_topology_result unrelated-checkout)
  _assert_contains "doctor topology: rejects unrelated checkout rooted at HOME" \
    ".dotfiles missing" "$result"
  _assert_not_contains "doctor topology: unrelated HOME checkout is not a dotfiles client" \
    "dotfiles checkout exists" "$result"
  unset -f _doctor_base_repo_topology_result

  doctor_opencode_home=$(_tmpdir)
  doctor_opencode_bin=$(_tmpdir)
  mkdir -p "$doctor_opencode_home/.config/opencode/plugins"
  cat >"$doctor_opencode_bin/opencode" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$doctor_opencode_bin/opencode"

  result=$(
    HOME="$doctor_opencode_home" PATH="$doctor_opencode_bin:$PATH" \
      _dr_check_opencode_agentguard 2>&1
  )
  _assert_contains "doctor: warns when OpenCode AgentGuard plugin is absent" \
    "OpenCode AgentGuard plugin missing" "$result"

  printf '%s\n' 'export const userOwned = true' \
    >"$doctor_opencode_home/.config/opencode/plugins/dotfiles-agentguard.js"
  result=$(
    HOME="$doctor_opencode_home" PATH="$doctor_opencode_bin:$PATH" \
      _dr_check_opencode_agentguard 2>&1
  )
  _assert_contains "doctor: warns when OpenCode AgentGuard plugin is unmanaged" \
    "OpenCode AgentGuard plugin unmanaged" "$result"

  cat >"$doctor_opencode_home/.config/opencode/plugins/dotfiles-agentguard.js" <<'PLUGIN'
// agentguard-managed:opencode-plugin
export const AgentGuardPlugin = async () => ({});
PLUGIN
  mv "$doctor_opencode_bin/opencode" "$doctor_opencode_bin/compatible-opencode"
  result=$(
    HOME="$doctor_opencode_home" PATH="$doctor_opencode_bin:/usr/bin:/bin" \
      DOT_OPENCODE_COMMAND=compatible-opencode \
      _dr_check_opencode_agentguard 2>&1
  )
  _assert_contains "doctor: accepts the managed plugin for a compatible command" \
    "OpenCode AgentGuard plugin installed" "$result"

  doctor_physical_dir="$(_tmpdir)/physical/real"
  doctor_path_tools_log="$(_tmpdir)/path-tools.log"
  mkdir -p "$doctor_physical_dir"
  printf '%s\n' "physical" >"$doctor_physical_dir/file"
  doctor_physical_expected="$(cd "$doctor_physical_dir" && pwd -P)/file"
  # shellcheck disable=SC2329  # _dr_physical_path invokes these test seams.
  dirname() {
    printf 'dirname\n' >>"$doctor_path_tools_log"
    command dirname "$@"
  }
  # shellcheck disable=SC2329  # _dr_physical_path invokes these test seams.
  basename() {
    printf 'basename\n' >>"$doctor_path_tools_log"
    command basename "$@"
  }
  doctor_physical_result=$(_dr_physical_path "$doctor_physical_dir/file")
  unset -f dirname basename
  _assert_eq "doctor paths: physical path remains correct" \
    "$doctor_physical_expected" "$doctor_physical_result"
  _assert_file_missing "doctor paths: physical path uses no external split tools" \
    "$doctor_path_tools_log"

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
  doctor_nvim_log=$(_tmpdir)/nvim.log
  mkdir -p "$doctor_shdeps_bin" "$TEST_HOME/.local/bin" "$TEST_HOME/.local/share/cgraf78"

  cat >"$doctor_shdeps_bin/nvim" <<'SH'
#!/usr/bin/env bash
_doctor_nvim_log() {
  [[ -z "${DOCTOR_NVIM_LOG:-}" ]] || printf '%s\n' "$1" >>"$DOCTOR_NVIM_LOG"
}

if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' 'NVIM v0.12.0-test'
  _doctor_nvim_log 'version'
  exit 0
fi

guard=0
late=0
previous=""
for arg in "$@"; do
  if [[ "$previous" == "--cmd" \
    && "$arg" == "lua vim.g.disable_session_restore = true" ]]; then
    guard=1
  elif [[ "$arg" == -c || "$arg" == +* ]] && [[ "$guard" -eq 0 ]]; then
    late=1
  fi
  previous="$arg"
done
_doctor_nvim_log "probe guard=$guard late=$late"
SH
  chmod +x "$doctor_shdeps_bin/nvim"

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
    tmux-continuum-default-server tmux-continuum-save-gate tmux-clip-paste
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

  result=$(DOCTOR_NVIM_LOG="$doctor_nvim_log" PATH="$doctor_path" \
    "$BIN_DIR/dot" doctor 2>&1 || true)

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
  doctor_nvim_expected_probes=2
  if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    doctor_nvim_expected_probes=3
  fi
  doctor_nvim_probe_count=$(awk '/^probe / { count++ } END { print count + 0 }' \
    "$doctor_nvim_log")
  doctor_nvim_unguarded_count=$(awk \
    '/^probe / && $0 != "probe guard=1 late=0" { count++ } END { print count + 0 }' \
    "$doctor_nvim_log")
  _assert_eq "doctor: runs every available full-config nvim probe" \
    "$doctor_nvim_expected_probes" "$doctor_nvim_probe_count"
  _assert_eq "doctor: isolates every full-config nvim probe from user sessions" \
    "0" "$doctor_nvim_unguarded_count"

  doctor_ci_home=$(_tmpdir)
  mkdir -p \
    "$doctor_ci_home/.local/bin" \
    "$doctor_ci_home/.local/lib/dotfiles/legacy-dot/core" \
    "$doctor_ci_home/.config/shell/env.d" \
    "$doctor_ci_home/.config/shell/interactive.d"
  cp "$BIN_DIR/dot" "$doctor_ci_home/.local/bin/dot"
  cp "$REAL_HOME/.local/lib/dotfiles/legacy-dot/core/"*.sh "$doctor_ci_home/.local/lib/dotfiles/legacy-dot/core/"
  cp -R "$REAL_HOME/.local/lib/dotfiles/legacy-dot/core/doctor" "$doctor_ci_home/.local/lib/dotfiles/legacy-dot/core/"
  cp -R "$REAL_HOME/.local/lib/dotfiles/legacy-dot/core/repos" "$doctor_ci_home/.local/lib/dotfiles/legacy-dot/core/"
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
    .local/lib/dotfiles/legacy-dot/core/doctor.sh \
    .local/lib/dotfiles/legacy-dot/core/doctor >/dev/null 2>&1

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
  rm -f "$TEST_HOME/.local/bin/tmux-continuum-default-server"
  rm -f "$TEST_HOME/.local/bin/tmux-continuum-save-gate"
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

  doctor_local_root="$TEST_HOME/doctor local source"
  doctor_local_conf="$TEST_HOME/.config/dot/overlays.d/15-filesystem.local.conf"
  doctor_local_rel=.doctor-local-link
  mkdir -p "$doctor_local_root/home" "$TEST_HOME/.local/state/dot"
  printf '%s\n' "local doctor value" >"$doctor_local_root/home/$doctor_local_rel"
  cat >"$doctor_local_conf" <<CONF
sync=none
path=$doctor_local_root
CONF
  ln -s "$doctor_local_root/home/$doctor_local_rel" "$TEST_HOME/$doctor_local_rel"
  printf '%s\t%s\t%s\n' \
    "$doctor_local_rel" filesystem "$doctor_local_root/home/$doctor_local_rel" \
    >"$TEST_HOME/.local/state/dot/overlay-links"
  chmod 600 "$TEST_HOME/.local/state/dot/overlay-links"
  _discover_overlays
  result=$(_dr_check_overlays 2>&1 || true)
  _assert_contains "doctor: reports a healthy filesystem overlay source" \
    "filesystem: local source available" "$result"
  _assert_contains "doctor: accepts filesystem overlay exact-target links" \
    "overlay symlinks healthy" "$result"
  _assert_not_contains "doctor: filesystem overlay is never reported as uncloned" \
    "filesystem: not cloned" "$result"

  chmod 000 "$doctor_local_root/home/$doctor_local_rel"
  if [[ -r "$doctor_local_root/home/$doctor_local_rel" ]]; then
    _pass "doctor: privileged runner bypasses unreadable source fixture"
  else
    result=$(_dr_check_overlays 2>&1 || true)
    _assert_contains "doctor: reports an unreadable filesystem overlay source" \
      "filesystem: local source unavailable" "$result"
  fi
  chmod 600 "$doctor_local_root/home/$doctor_local_rel"

  doctor_local_next="$TEST_HOME/doctor local source next"
  mkdir -p "$doctor_local_next/home"
  printf '%s\n' "next local doctor value" \
    >"$doctor_local_next/home/$doctor_local_rel"
  cat >"$doctor_local_conf" <<CONF
sync=none
path=$doctor_local_next
CONF
  _discover_overlays
  result=$(_dr_check_overlays 2>&1 || true)
  _assert_contains "doctor: flags a stale link after local source path changes" \
    "overlay symlink issue" "$result"
  cat >"$doctor_local_conf" <<CONF
sync=none
path=$doctor_local_root
CONF
  _discover_overlays

  cat >"$TEST_HOME/.config/dot/overlays.d/16-invalid.local.conf" <<CONF
sync=none
path=$doctor_local_root
unexpected=value
CONF
  rm -f "$TEST_HOME/$doctor_local_rel"
  result=$("$BIN_DIR/dot" doctor 2>&1 || true)
  _assert_contains "doctor: malformed descriptor is an explicit failure" \
    "overlay descriptor invalid" "$result"
  _assert_contains "doctor: malformed descriptor still checks stale manifest state" \
    "overlay symlink issue" "$result"
  rm -f \
    "$TEST_HOME/.config/dot/overlays.d/16-invalid.local.conf" \
    "$doctor_local_conf" \
    "$TEST_HOME/$doctor_local_rel" \
    "$TEST_HOME/.local/state/dot/overlay-links"
  rm -rf "$doctor_local_root" "$doctor_local_next"
  _discover_overlays

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
  _overlay_link_target ".doctor-overlay-link" work
  ln -s "$REPLY" "$TEST_HOME/.doctor-overlay-link"
  _discover_overlays
  doctor_physical_fallback_log=$(_tmpdir)/physical-fallback.log
  doctor_readlink_log=$(_tmpdir)/readlink.log
  for doctor_link_suffix in one two; do
    doctor_link_rel=".doctor-overlay-link-$doctor_link_suffix"
    printf '%s\n' "expected" \
      >"$TEST_HOME/.dotfiles-work/home/$doctor_link_rel"
    _overlay_link_target "$doctor_link_rel" work
    ln -s "$REPLY" "$TEST_HOME/$doctor_link_rel"
    printf '%s\t%s\n' "$doctor_link_rel" "work" \
      >>"$TEST_HOME/.local/state/dot/overlay-links"
  done
  result=$(
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    readlink() {
      printf '%s\n' "$#" >>"$doctor_readlink_log"
      command readlink "$@"
    }
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    _dr_symlink_points_to() {
      printf 'called\n' >>"$doctor_physical_fallback_log"
      return 1
    }
    _dr_check_overlays 2>&1 || true
  )
  _assert_contains "doctor: canonical overlay target stays healthy" \
    "overlay symlinks healthy" "$result"
  _assert_file_missing "doctor: canonical overlay target skips physical fallback" \
    "$doctor_physical_fallback_log"
  _assert_file_content "doctor: canonical overlay targets use one batched readlink" \
    "3" "$doctor_readlink_log"
  doctor_readlink_fallback_log=$(_tmpdir)/readlink-fallback.log
  result=$(
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    readlink() {
      printf '%s\n' "$#" >>"$doctor_readlink_fallback_log"
      [[ "$#" -eq 1 ]] || return 1
      command readlink "$@"
    }
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    _dr_symlink_points_to() {
      printf 'called\n' >>"$doctor_physical_fallback_log"
      return 1
    }
    _dr_check_overlays 2>&1 || true
  )
  _assert_contains "doctor: unsupported batched readlink falls back safely" \
    "overlay symlinks healthy" "$result"
  _assert_file_content "doctor: failed batch retries each link separately" \
    $'3\n1\n1\n1' "$doctor_readlink_fallback_log"
  _assert_file_missing "doctor: successful readlink fallback skips physical resolution" \
    "$doctor_physical_fallback_log"
  doctor_readlink_short_log=$(_tmpdir)/readlink-short.log
  result=$(
    set -e
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    readlink() {
      printf '%s\n' "$#" >>"$doctor_readlink_short_log"
      if [[ "$#" -gt 1 ]]; then
        command readlink "$1"
        return 0
      fi
      command readlink "$@"
    }
    _dr_check_overlays 2>&1
  )
  _assert_contains "doctor: incomplete batch output falls back under errexit" \
    "overlay symlinks healthy" "$result"
  _assert_file_content "doctor: incomplete batch retries each link separately" \
    $'3\n1\n1\n1' "$doctor_readlink_short_log"

  doctor_cancel_dir=$(_tmpdir)
  doctor_cancel_bin="$doctor_cancel_dir/bin"
  doctor_cancel_tmp="$doctor_cancel_dir/tmp"
  mkdir -p "$doctor_cancel_bin" "$doctor_cancel_tmp"
  doctor_real_readlink=$(command -v readlink)
  cat >"$doctor_cancel_bin/readlink" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ "$arg" == "$DOCTOR_CANCEL_LINK" ]]; then
    : >"$DOCTOR_CANCEL_READY"
    trap 'exit 143' TERM
    while :; do
      sleep 1
    done
  fi
done
exec "$DOCTOR_REAL_READLINK" "$@"
SH
  chmod +x "$doctor_cancel_bin/readlink"

  doctor_cancel_fixture_rc=0
  # shellcheck disable=SC2016 # The inner shell expands fixture environment.
  DOCTOR_CANCEL_LINK="$TEST_HOME/.doctor-overlay-link" \
    DOCTOR_CANCEL_READY="$doctor_cancel_dir/ready" \
    DOCTOR_REAL_READLINK="$doctor_real_readlink" \
    DOT_DOCTOR_BIN="$BIN_DIR/dot" \
    TMPDIR="$doctor_cancel_tmp" \
    PATH="$doctor_cancel_bin:$PATH" \
    _with_timeout 8 bash -c '
      set -uo pipefail
      leader=""
      cleanup() {
        [[ -n "$leader" ]] || return 0
        kill -KILL -- "-$leader" 2>/dev/null || true
        wait "$leader" 2>/dev/null || true
      }
      trap cleanup EXIT
      trap "exit 124" HUP INT TERM

      set -m
      "$DOT_DOCTOR_BIN" doctor >"$DOCTOR_CANCEL_READY.output" 2>&1 &
      leader=$!
      set +m

      ready=0
      for ((attempt = 0; attempt < 500; attempt++)); do
        if [[ -e "$DOCTOR_CANCEL_READY" ]]; then
          ready=1
          break
        fi
        kill -0 "$leader" 2>/dev/null || break
        sleep 0.01
      done
      [[ "$ready" -eq 1 ]] || exit 90

      find "$TMPDIR" -mindepth 1 -maxdepth 1 -print \
        >"$DOCTOR_CANCEL_READY.before"
      kill -TERM -- "-$leader"
      doctor_rc=0
      wait "$leader" || doctor_rc=$?
      leader=""
      printf "%s\n" "$doctor_rc" >"$DOCTOR_CANCEL_READY.rc"
      find "$TMPDIR" -mindepth 1 -maxdepth 1 -print \
        >"$DOCTOR_CANCEL_READY.after"
    ' || doctor_cancel_fixture_rc=$?
  _assert_exit "doctor cancellation: fixture completes within deadline" \
    0 "$doctor_cancel_fixture_rc"
  _assert_file_content "doctor cancellation: preserves TERM status" \
    "143" "$doctor_cancel_dir/ready.rc"
  doctor_cancel_before=$(cat "$doctor_cancel_dir/ready.before" 2>/dev/null || true)
  _assert_contains "doctor cancellation: reaches a registered operation root" \
    "$doctor_cancel_tmp/dot-doctor." "$doctor_cancel_before"
  _assert_file_content "doctor cancellation: removes its registered scratch root" \
    "" "$doctor_cancel_dir/ready.after"

  for doctor_link_suffix in one two; do
    doctor_link_rel=".doctor-overlay-link-$doctor_link_suffix"
    rm -f \
      "$TEST_HOME/$doctor_link_rel" \
      "$TEST_HOME/.dotfiles-work/home/$doctor_link_rel"
  done
  printf '%s\t%s\n' ".doctor-overlay-link" "work" \
    >"$TEST_HOME/.local/state/dot/overlay-links"

  rm -f "$TEST_HOME/.dotfiles-work/home/.doctor-overlay-link"
  result=$(
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    _dr_symlink_points_to() {
      printf 'called\n' >>"$doctor_physical_fallback_log"
      return 1
    }
    _dr_check_overlays 2>&1 || true
  )
  _assert_contains "doctor: canonical dangling overlay target remains an issue" \
    "overlay symlink issue" "$result"
  _assert_file_missing "doctor: dangling target fails before the lexical fast path" \
    "$doctor_physical_fallback_log"
  printf '%s\n' "expected" >"$TEST_HOME/.dotfiles-work/home/.doctor-overlay-link"

  # A malformed record can make the generated lexical target point at a
  # different, existing sibling tree after filesystem normalization. It must
  # take the physical fallback rather than inheriting the canonical fast path.
  doctor_escape_overlay="${TEST_HOME%/*}/.dotfiles-work"
  mkdir -p "$doctor_escape_overlay/home"
  printf '%s\n' "wrong tree" >"$doctor_escape_overlay/home/.doctor-overlay-link"
  rm -f "$TEST_HOME/.doctor-overlay-link" "$doctor_physical_fallback_log"
  _overlay_link_target "./.doctor-overlay-link" work
  ln -s "$REPLY" "$TEST_HOME/.doctor-overlay-link"
  printf '%s\t%s\n' "./.doctor-overlay-link" "work" >"$TEST_HOME/.local/state/dot/overlay-links"
  result=$(
    # shellcheck disable=SC2329 # invoked indirectly by _dr_check_overlays.
    _dr_symlink_points_to() {
      printf 'called\n' >>"$doctor_physical_fallback_log"
      return 1
    }
    _dr_check_overlays 2>&1 || true
  )
  _assert_contains "doctor: noncanonical overlay target remains an issue" \
    "overlay symlink issue" "$result"
  _assert_file_missing "doctor: malformed manifest is rejected before physical fallback" \
    "$doctor_physical_fallback_log"
  rm -rf "$doctor_escape_overlay"

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
