# shellcheck shell=bash
# merges.sh - merge hook coverage.

_dot_test_merge_hook_names() {
  local source_home="$1" tracked_hooks tracked_path hook_name
  local -a git_args=()

  if [[ -e "$source_home/.git" || -L "$source_home/.git" ]]; then
    git_args=(
      -c "safe.directory=$source_home"
      -C "$source_home"
    )
  elif [[ -d "$source_home/.dotfiles" ]]; then
    git_args=(
      -C "$source_home"
      "--git-dir=$source_home/.dotfiles"
      "--work-tree=$source_home"
    )
  else
    printf 'merge hook test: cannot resolve base repository for %s\n' \
      "$source_home" >&2
    return 1
  fi

  tracked_hooks=$(git "${git_args[@]}" ls-files -- \
    ':(glob).local/lib/dotfiles/merge-hooks.d/*.sh') || return 1
  while IFS= read -r tracked_path; do
    [[ -n "$tracked_path" ]] || continue
    hook_name="${tracked_path##*/}"
    hook_name="${hook_name%.sh}"
    hook_name="${hook_name%.serial}"
    printf '%s\n' "$hook_name"
  done <<<"$tracked_hooks" | LC_ALL=C sort
}

dot_core_test_merges() {
  echo ""
  echo "=== Tool presence capability ==="

  REPLY=
  account_home_status=0
  _dot_account_home || account_home_status=$?
  account_scope_home=$REPLY
  _assert_eq "account scope: account HOME resolves" \
    "0" "$account_home_status"

  termux_account_status=0
  termux_account_home=$(dot_fixture_termux_account_home \
    "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/compat.sh" \
    _dot_account_home) || termux_account_status=$?
  if [[ "$termux_account_status" -eq 77 ]]; then
    echo "  - skipping Termux account HOME check (mount namespace unavailable)"
  else
    _assert_eq "account scope: Termux account HOME resolves" \
      "0" "$termux_account_status"
    _assert_eq "account scope: Termux uses the fixed application HOME" \
      "/data/data/com.termux/files/home" "$termux_account_home"
  fi

  account_scope_status=0
  account_scope_command=$(
    env BASH_ENV='' HOME="$account_scope_home" DOT_TEST=0 \
      bash -s -- "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/compat.sh" <<'BASH'
dot_hook_source() { return 0; }
dot_hook_warn() { :; }
. "$1" || exit
_dot_account_scoped_command "account scope test" id "" || exit
printf '%s' "$REPLY"
BASH
  ) || account_scope_status=$?
  _assert_eq "account scope: actual account HOME is accepted" \
    "0" "$account_scope_status"
  if [[ -n "$account_scope_command" && -x "$account_scope_command" ]]; then
    _pass "account scope: production command resolves from PATH"
  else
    _fail "account scope: production command resolves from PATH"
  fi

  account_spoof_home=$(_tmpdir)
  account_spoof_bin=$(_tmpdir)
  cat >"$account_spoof_bin/getent" <<'SH'
#!/usr/bin/env bash
[[ "${1:-}" == "passwd" && -n "${2:-}" ]] || exit 1
printf '%s:x:1:1::%s:/bin/sh\n' "$2" "$ACCOUNT_SPOOF_HOME"
SH
  chmod +x "$account_spoof_bin/getent"

  account_hash_spoof_status=0
  env BASH_ENV='' HOME="$account_spoof_home" DOT_TEST=0 \
    PATH="$account_spoof_bin:$PATH" \
    ACCOUNT_SPOOF_GETENT="$account_spoof_bin/getent" \
    ACCOUNT_SPOOF_HOME="$account_spoof_home" \
    bash -s -- "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/compat.sh" <<'BASH' || account_hash_spoof_status=$?
hash -p "$ACCOUNT_SPOOF_GETENT" getent
dot_hook_source() { return 0; }
dot_hook_warn() { :; }
. "$1" || exit
if _dot_account_scoped_command "account scope spoof" id ""; then
  exit 1
fi
BASH
  _assert_eq "account scope: command hash cannot authorize a synthetic HOME" \
    "0" "$account_hash_spoof_status"

  account_command_spoof_status=0
  env BASH_ENV='' HOME="$account_spoof_home" DOT_TEST=0 \
    PATH="$account_spoof_bin:$PATH" \
    ACCOUNT_SPOOF_GETENT="$account_spoof_bin/getent" \
    ACCOUNT_SPOOF_HOME="$account_spoof_home" \
    bash -s -- "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/compat.sh" <<'BASH' || account_command_spoof_status=$?
# shellcheck disable=SC2329 # Invoked by the account resolver under test.
command() {
  if [[ "${1:-}" == "-p" && "${2:-}" == "getent" ]]; then
    shift 2
    "$ACCOUNT_SPOOF_GETENT" "$@"
    return
  fi
  builtin command "$@"
}
dot_hook_source() { return 0; }
dot_hook_warn() { :; }
. "$1" || exit
if _dot_account_scoped_command "account scope spoof" id ""; then
  exit 1
fi
BASH
  _assert_eq "account scope: command function cannot authorize a synthetic HOME" \
    "0" "$account_command_spoof_status"

  local tool_platform_impl tool_command_impl tool_path_impl
  tool_platform_impl=$(declare -f _dot_tool_platform)
  tool_command_impl=$(declare -f _dot_tool_command_present)
  tool_path_impl=$(declare -f _dot_tool_path_exists)

  _tool_presence_platform=Linux
  _tool_presence_commands=""
  _tool_presence_paths=""

  # shellcheck disable=SC2329 # Invoked by the capability helper under test.
  _dot_tool_platform() {
    printf '%s\n' "$_tool_presence_platform"
  }
  # shellcheck disable=SC2329 # Invoked by the capability helper under test.
  _dot_tool_command_present() {
    case ":$_tool_presence_commands:" in
      *":$1:"*) return 0 ;;
      *) return 1 ;;
    esac
  }
  # shellcheck disable=SC2329 # Invoked by the capability helper under test.
  _dot_tool_path_exists() {
    case ":$_tool_presence_paths:" in
      *":$1:"*) return 0 ;;
      *) return 1 ;;
    esac
  }

  while IFS=: read -r logical_tool native_command; do
    _tool_presence_commands="$native_command"
    _assert_exit "tool presence: $logical_tool resolves $native_command" 0 \
      "$(
        _dot_tool_present "$logical_tool"
        printf '%s' "$?"
      )"
  done <<'TOOL_COMMANDS'
agent-rules:agent-rules-sync
claude:claude
codex:codex
cron:crontab
gemini:gemini
gh:gh
git:git
grafhome-ca:grafhome-ca
gstack:gstack-register
hive-memory:hm
mise:mise
muse:muse
nvim:nvim
opencode:opencode
sapling:sl
ssh:ssh
tmux:tmux
TOOL_COMMANDS

  _tool_presence_commands=fdfind
  _assert_exit "tool presence: shared ignore policy accepts Debian fd" 0 \
    "$(
      _dot_tool_present ignore
      printf '%s' "$?"
    )"

  _tool_presence_commands=""
  _assert_exit "tool presence: absent command-backed tool is rejected" 1 \
    "$(
      _dot_tool_present ssh
      printf '%s' "$?"
    )"

  _tool_presence_platform=Darwin
  _tool_presence_paths="$HOME/Applications/iTerm.app"
  _assert_exit "tool presence: macOS user app bundle enables iTerm2" 0 \
    "$(
      _dot_tool_present iterm2
      printf '%s' "$?"
    )"

  _tool_presence_paths="/Applications/Karabiner-Elements.app"
  _assert_exit "tool presence: macOS app bundle enables Karabiner" 0 \
    "$(
      _dot_tool_present karabiner
      printf '%s' "$?"
    )"

  _tool_presence_paths="/Applications/Visual Studio Code - Insiders.app"
  _assert_exit "tool presence: any macOS editor variant enables VS Code" 0 \
    "$(
      _dot_tool_present vscode
      printf '%s' "$?"
    )"

  _tool_presence_commands=code-fb
  _tool_presence_paths=""
  _assert_exit "tool presence: VS Code @ FB command enables VS Code" 0 \
    "$(
      _dot_tool_present vscode
      printf '%s' "$?"
    )"

  _tool_presence_commands=""
  _tool_presence_paths="/Applications/VS Code @ FB.app"
  _assert_exit "tool presence: VS Code @ FB app enables VS Code" 0 \
    "$(
      _dot_tool_present vscode
      printf '%s' "$?"
    )"

  _tool_presence_platform=WSL
  _tool_presence_commands=wezterm.exe
  _tool_presence_paths=""
  _assert_exit "tool presence: WSL accepts the Windows WezTerm command" 0 \
    "$(
      _dot_tool_present wezterm
      printf '%s' "$?"
    )"

  _tool_presence_commands=codium-insiders.exe
  _assert_exit "tool presence: WSL accepts VSCodium Insiders executable" 0 \
    "$(
      _dot_tool_present vscode
      printf '%s' "$?"
    )"

  _tool_presence_platform=Linux
  _tool_presence_commands=""
  _tool_presence_paths="$HOME/.cursor-server"
  _assert_exit "tool presence: remote editor server enables VS Code merge" 0 \
    "$(
      _dot_tool_present vscode
      printf '%s' "$?"
    )"

  _tool_presence_paths=""
  _assert_exit "tool presence: unknown logical tools fail closed" 1 \
    "$(
      _dot_tool_present not-a-tool
      printf '%s' "$?"
    )"

  eval "$tool_platform_impl"
  eval "$tool_command_impl"
  eval "$tool_path_impl"

  echo "=== Merge hook tool gates ==="

  tool_gated_hooks=$(
    printf '%s\n' \
      agent-rules claude codex cron gemini gh git gstack hive-memory ignore \
      iterm2 karabiner mise muse nvim opencode sapling ssh tmux vscode wezterm
  )
  merge_hook_inventory_home=$(_tmpdir)
  mkdir -p "$merge_hook_inventory_home/.local/lib/dotfiles/merge-hooks.d/lib"
  printf '# tracked base hook\n' \
    >"$merge_hook_inventory_home/.local/lib/dotfiles/merge-hooks.d/git.sh"
  printf '# tracked support file, not a top-level hook\n' \
    >"$merge_hook_inventory_home/.local/lib/dotfiles/merge-hooks.d/lib/support.sh"
  printf '# untracked overlay hook\n' \
    >"$merge_hook_inventory_home/.local/lib/dotfiles/merge-hooks.d/overlay-extension.sh"
  git -C "$merge_hook_inventory_home" init -q
  git -C "$merge_hook_inventory_home" add \
    .local/lib/dotfiles/merge-hooks.d/git.sh \
    .local/lib/dotfiles/merge-hooks.d/lib/support.sh
  git -C "$merge_hook_inventory_home" \
    -c user.name='Dot Fixture' -c user.email=dot.fixture.invalid \
    -c commit.gpgsign=false commit -qm fixture
  _assert_eq "merge hook gates: conventional checkout inventories only base hooks" \
    "git" "$(_dot_test_merge_hook_names "$merge_hook_inventory_home")"
  _assert_eq "merge hook gates: checkout ownership mismatch inventories base hooks" \
    "git" "$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
      _dot_test_merge_hook_names "$merge_hook_inventory_home")"

  merge_hook_linked_parent=$(_tmpdir)
  merge_hook_linked_home="$merge_hook_linked_parent/home"
  git -C "$merge_hook_inventory_home" worktree add -q -b linked-layout \
    "$merge_hook_linked_home"
  printf '# untracked overlay hook\n' \
    >"$merge_hook_linked_home/.local/lib/dotfiles/merge-hooks.d/overlay-extension.sh"
  _assert_eq "merge hook gates: linked worktree inventories only base hooks" \
    "git" "$(_dot_test_merge_hook_names "$merge_hook_linked_home")"
  _assert_eq "merge hook gates: linked ownership mismatch inventories base hooks" \
    "git" "$(GIT_TEST_ASSUME_DIFFERENT_OWNER=1 \
      _dot_test_merge_hook_names "$merge_hook_linked_home")"

  merge_hook_dotfiles_home=$(_tmpdir)
  mkdir -p "$merge_hook_dotfiles_home/.local/lib/dotfiles/merge-hooks.d/lib"
  printf '# tracked base hook\n' \
    >"$merge_hook_dotfiles_home/.local/lib/dotfiles/merge-hooks.d/git.sh"
  printf '# tracked support file, not a top-level hook\n' \
    >"$merge_hook_dotfiles_home/.local/lib/dotfiles/merge-hooks.d/lib/support.sh"
  printf '# untracked overlay hook\n' \
    >"$merge_hook_dotfiles_home/.local/lib/dotfiles/merge-hooks.d/overlay-extension.sh"
  git init --bare -q "$merge_hook_dotfiles_home/.dotfiles"
  git -C "$merge_hook_dotfiles_home" \
    "--git-dir=$merge_hook_dotfiles_home/.dotfiles" \
    "--work-tree=$merge_hook_dotfiles_home" add \
    .local/lib/dotfiles/merge-hooks.d/git.sh \
    .local/lib/dotfiles/merge-hooks.d/lib/support.sh
  _assert_eq "merge hook gates: live dotfiles layout inventories only base hooks" \
    "git" "$(_dot_test_merge_hook_names "$merge_hook_dotfiles_home")"

  classified_hooks=$(_dot_test_merge_hook_names "$REAL_HOME")
  _assert_eq "merge hook gates: every base hook is classified" \
    "$(printf '%s\n' "$tool_gated_hooks" | LC_ALL=C sort)" "$classified_hooks"

  while IFS= read -r hook_name; do
    hook_file=$hook_name
    [[ $hook_file == cron ]] && hook_file=cron.serial
    hook_path="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/$hook_file.sh"
    first_merge_statement=$(
      awk '
        /^merge\(\)[[:space:]]*\{/ { in_merge = 1; next }
        in_merge && /^[[:space:]]*$/ { next }
        in_merge && /^[[:space:]]*#/ { next }
        in_merge {
          sub(/^[[:space:]]+/, "")
          print
          exit
        }
      ' "$hook_path"
    )
    _assert_eq "$hook_name merge: tool guard is the first operation" \
      "_dot_tool_present $hook_name || return 0" "$first_merge_statement"

    absent_hook_output=$(
      (
        unset -f merge 2>/dev/null
        # shellcheck source=/dev/null
        . "$hook_path"
        # shellcheck disable=SC2329 # Invoked indirectly by the sourced hook.
        _dot_tool_present() { return 1; }
        merge
      ) 2>&1
    )
    absent_hook_status=$?
    _assert_exit "$hook_name merge: absent tool is a successful no-op" \
      0 "$absent_hook_status"
    _assert_eq "$hook_name merge: absent tool is silent" "" "$absent_hook_output"
  done <<<"$tool_gated_hooks"

  echo "=== Merge hook support helpers ==="

  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d" "$TEST_HOME/.config/testapp"
  _assert_eq "merge hook support: source path uses active HOME" \
    "$TEST_HOME/.config/dot/merge-hooks.d/settings.json" \
    "$(_merge_hook_source settings.json)"
  # shellcheck disable=SC2016 # Exercise literal placeholders from config files.
  _assert_eq "merge hook support: expands leading \$HOME" \
    "$TEST_HOME/bin" \
    "$(_merge_hook_expand_home '$HOME/bin')"
  # shellcheck disable=SC2088 # Exercise literal tilde from config files.
  _assert_eq "merge hook support: expands leading tilde" \
    "$TEST_HOME/bin" \
    "$(_merge_hook_expand_home '~/bin')"
  # shellcheck disable=SC2016 # Exercise literal placeholders from config files.
  _assert_eq "merge hook support: expands \$HOME inside native config line" \
    "precommit.sley = $TEST_HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate" \
    "$(_merge_hook_expand_home 'precommit.sley = $HOME/.local/share/cgraf78/sley/share/sley/hooks/sapling/sley-commit-gate')"

  yq_resolver_home="$TEST_HOME/yq-resolver-home"
  yq_resolver_path="$TEST_HOME/yq-resolver-path"
  mkdir -p "$yq_resolver_home/.local/bin" "$yq_resolver_path"
  cat >"$yq_resolver_path/yq" <<'YQ'
#!/usr/bin/env bash
printf '%s\n' 'yq 3.4.3'
YQ
  cat >"$yq_resolver_home/.local/bin/yq" <<'YQ'
#!/usr/bin/env bash
printf '%s\n' 'yq (https://github.com/mikefarah/yq/) version v4.53.3'
YQ
  chmod +x "$yq_resolver_path/yq" "$yq_resolver_home/.local/bin/yq"
  _assert_eq "merge hook support: Shdeps yq survives an unrefreshed bootstrap PATH" \
    "$yq_resolver_home/.local/bin/yq" \
    "$(HOME="$yq_resolver_home" PATH="$yq_resolver_path:/usr/bin:/bin" \
      _merge_hook_mikefarah_yq 2>/dev/null || true)"

  if declare -F dot_agentguard_integration_file >/dev/null 2>&1; then
    agentguard_resolved=$(
      (
        # shellcheck disable=SC2329 # Invoked through the resolver under test.
        dot_shdeps_dep_file() {
          _assert_eq "AgentGuard resolver: requests the dependency repository" \
            "cgraf78/agentguard" "$1" >&2
          printf '/resolved/%s\n' "$2"
        }
        dot_agentguard_integration_file claude hooks.json
      )
    )
    _assert_eq "AgentGuard resolver: maps an agent asset without local layout knowledge" \
      "/resolved/share/agentguard/integrations/claude/hooks.json" \
      "$agentguard_resolved"
  else
    _fail "AgentGuard resolver: shared dependency asset helper exists"
  fi

  codex_api="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/lib/codex/api.sh"
  _assert_exit "Codex API boundary: clean shell rejects direct private loading" 1 \
    "$(
      # shellcheck disable=SC2016 # $1 expands inside the clean child shell.
      env -i HOME="$TEST_HOME" PATH="/usr/bin:/bin" \
        /bin/bash --noprofile --norc -c '
          . "$1"
        ' bash "$codex_api"
      printf '%s' "$?"
    )"
  _assert_exit "Codex API boundary: public extension API supplies dependencies" 0 \
    "$(
      # shellcheck disable=SC2016 # $1 and $2 expand in the clean child shell.
      env -i HOME="$TEST_HOME" PATH="/usr/bin:/bin" \
        REAL_HOME="$REAL_HOME" DOT_TEST_SOURCE_HOME="$REAL_HOME" \
        DOT_TEST_DOT_ROOT="$DOT_SOURCE_ROOT" \
        /bin/bash --noprofile --norc -c '
          . "$1"
          . "$2"
          declare -F dot_agentguard_integration_file >/dev/null
        ' bash "$REAL_HOME/.local/lib/dotfiles/tests/load-merge-api.sh" "$codex_api"
      printf '%s' "$?"
    )"

  echo "=== tmux merge hook ==="

  tmux_home="$TEST_HOME/tmux-merge-home"
  tmux_bin="$tmux_home/bin"
  tmux_log="$tmux_home/tmux.log"
  tmux_server="$tmux_home/server-running"
  mkdir -p "$tmux_home/.config/tmux" "$tmux_bin"
  printf '%s\n' 'set -g status on' >"$tmux_home/.config/tmux/tmux.conf"
  cat >"$tmux_bin/tmux" <<'TMUX'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOT_TEST_TMUX_LOG"
case "$1" in
  has-session)
    [[ -f "$DOT_TEST_TMUX_SERVER" ]]
    ;;
  source-file) exit 0 ;;
  *) exit 2 ;;
esac
TMUX
  chmod +x "$tmux_bin/tmux"
  _run_tmux_merge_for_test() {
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/tmux.sh"
    merge
  }

  : >"$tmux_server"
  : >"$tmux_log"
  tmux_missing_double_output=$(HOME="$tmux_home" PATH="$tmux_bin:$PATH" \
    DOT_TEST_TMUX_LOG="$tmux_log" DOT_TEST_TMUX_SERVER="$tmux_server" \
    _run_tmux_merge_for_test 2>&1)
  _assert_eq "tmux merge: test mode requires an explicit double" \
    "" "$(cat "$tmux_log")"
  _assert_contains "tmux merge: missing test double is reported" \
    "test tmux" "$tmux_missing_double_output"

  : >"$tmux_log"
  tmux_non_account_output=$(DOT_TEST=0 HOME="$tmux_home" \
    PATH="$tmux_bin:$PATH" DOT_TEST_TMUX_LOG="$tmux_log" \
    DOT_TEST_TMUX_SERVER="$tmux_server" _run_tmux_merge_for_test 2>&1)
  _assert_eq "tmux merge: non-account HOME leaves the user server untouched" \
    "" "$(cat "$tmux_log")"
  _assert_contains "tmux merge: non-account HOME is reported" \
    "account home" "$tmux_non_account_output"

  : >"$tmux_log"
  HOME="$tmux_home" PATH="$tmux_bin:$PATH" DOT_TEST_TMUX="$tmux_bin/tmux" \
    DOT_TEST_TMUX_LOG="$tmux_log" \
    DOT_TEST_TMUX_SERVER="$tmux_server" _run_tmux_merge_for_test
  tmux_expected=$(printf 'has-session\nsource-file %s' \
    "$tmux_home/.config/tmux/tmux.conf")
  _assert_eq "tmux merge: reloads the default running server" \
    "$tmux_expected" "$(cat "$tmux_log")"

  rm -f "$tmux_server"
  : >"$tmux_log"
  HOME="$tmux_home" PATH="$tmux_bin:$PATH" DOT_TEST_TMUX="$tmux_bin/tmux" \
    DOT_TEST_TMUX_LOG="$tmux_log" \
    DOT_TEST_TMUX_SERVER="$tmux_server" _run_tmux_merge_for_test
  _assert_eq "tmux merge: skips reload when no server is running" \
    "has-session" "$(cat "$tmux_log")"
  unset -f _run_tmux_merge_for_test merge 2>/dev/null

  echo "=== Karabiner source config ==="

  if command -v jq >/dev/null 2>&1; then
    karabiner_src="$REAL_HOME/.config/dot/merge-hooks.d/karabiner/profiles.d/10-windows-dotfiles.json"
    karabiner_ctrl_arrow_vscode_exemptions=$(
      jq -r '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description as $desc | [
              "Left Arrow (Ctrl+Shift)",
              "Left Arrow (Ctrl)",
              "Right Arrow (Ctrl+Shift)",
              "Right Arrow (Ctrl)"
            ] | index($desc))
          | .manipulators[0].conditions[0].bundle_identifiers as $bundles
          | select(vscode_bundle_ids | all(. as $bundle | $bundles | index($bundle)))
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: Windows Ctrl-arrow rules exempt VS Code apps" \
      "4" "$karabiner_ctrl_arrow_vscode_exemptions"

    karabiner_pane_move_transports=$(
      jq -c '[
        .profiles[]
        | select(.name == "Windows (Dotfiles)")
        | .complex_modifications.rules[]
        | select(.description == "Alt-Shift-H/J/K/L [Only VS Code]")
        | .manipulators[]
        | {from: .from.key_code, to: .to[0].key_code}
      ] | sort_by(.from)' "$karabiner_src"
    )
    _assert_eq "karabiner: Alt-Shift-H/J/K/L use the reserved VS Code transports" \
      '[{"from":"h","to":"f16"},{"from":"j","to":"f17"},{"from":"k","to":"f18"},{"from":"l","to":"f19"}]' \
      "$karabiner_pane_move_transports"

    karabiner_pane_move_transport_errors=$(
      jq -c '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description == "Alt-Shift-H/J/K/L [Only VS Code]")
          | .manipulators[]
          | select(
              .from.modifiers.mandatory != ["option", "shift"]
              or (.from.modifiers.optional // []) != []
              or (.to | length) != 1
              or (.to[0] | has("modifiers"))
              or (.conditions | length) != 1
              or .conditions[0].type != "frontmost_application_if"
              or (.conditions[0].bundle_identifiers | sort) != (vscode_bundle_ids | sort)
            )
          | .from.key_code
        ] | sort
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: pane-move transports are exact and VS Code-only" \
      '[]' "$karabiner_pane_move_transport_errors"

    karabiner_pane_move_transport_collisions=$(
      jq '[
        .profiles[]
        | select(.name == "Windows (Dotfiles)")
        | .complex_modifications.rules[]
        | select(.description != "Alt-Shift-H/J/K/L [Only VS Code]")
        | .manipulators[].to[]?
        | select(.key_code == "f16" or .key_code == "f17" or .key_code == "f18" or .key_code == "f19")
      ] | length' "$karabiner_src"
    )
    _assert_eq "karabiner: F16-F19 are reserved for pane movement" \
      "0" "$karabiner_pane_move_transport_collisions"

    karabiner_home_end_vscode_exemptions=$(
      jq -r '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description as $desc | [
              "Home (Ctrl+Shift)",
              "Home (Shift)",
              "Home (Ctrl)",
              "Home",
              "End (Ctrl+Shift)",
              "End (Shift)",
              "End (Ctrl)",
              "End"
            ] | index($desc))
          | .manipulators[0].conditions[0].bundle_identifiers as $bundles
          | select(vscode_bundle_ids | all(. as $bundle | $bundles | index($bundle)))
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: Windows Home/End rules exempt VS Code apps" \
      "8" "$karabiner_home_end_vscode_exemptions"

    karabiner_clipboard_vscode_mappings=$(
      jq -r '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description as $desc | ["C (Ctrl)", "V (Ctrl)"] | index($desc))
          | .manipulators[]
          | select(.from.modifiers.mandatory == ["control"])
          | select(.to[0].modifiers == ["command"])
          | select(.to[0].key_code == .from.key_code)
          | .conditions[]
          | select(.type == "frontmost_application_unless")
          | .bundle_identifiers as $bundles
          | select(vscode_bundle_ids | all(. as $bundle | $bundles | index($bundle) | not))
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: Windows profile owns VS Code Ctrl+C/V to Cmd+C/V remapping" \
      "2" "$karabiner_clipboard_vscode_mappings"

    karabiner_vscode_ctrl_letter_mappings=$(
      jq -c '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[].manipulators[]
          | select(.from.key_code | test("^[a-z]$"))
          | select(.from.modifiers.mandatory == ["control"])
          | select(.to[0].key_code == .from.key_code)
          | select(.to[0].modifiers == ["command"])
          | select(any(.conditions[];
              .type == "frontmost_application_unless"
              and (.bundle_identifiers as $bundles
                | vscode_bundle_ids
                | all(. as $bundle | $bundles | index($bundle) | not))))
          | .from.key_code
        ] | unique | sort
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: VS Code Ctrl-letter translation inventory is explicit" \
      '["a","b","c","f","g","i","n","o","p","r","s","t","u","v","w","x","y","z"]' \
      "$karabiner_vscode_ctrl_letter_mappings"

    karabiner_ctrl_slash_vscode_mapping=$(
      jq -r '
        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description == "/ (Ctrl) [+Terminal Emulators]")
          | .manipulators[]
          | select(.from.key_code == "slash")
          | select(.from.modifiers.mandatory == ["control"])
          | select(.to[0].key_code == "slash")
          | select(.to[0].modifiers == ["command"])
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: VS Code Ctrl+slash translation stays explicit" \
      "1" "$karabiner_ctrl_slash_vscode_mapping"

    karabiner_shift_c_vscode_mapping=$(
      jq -r '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description == "C (Ctrl+Shift) [Only Terminal Emulators]")
          | .manipulators[]
          | select(.from.key_code == "c")
          | select(.from.modifiers.mandatory == ["control", "shift"])
          | select(.to[0].key_code == "c")
          | select(.to[0].modifiers == ["command"])
          | .conditions[]
          | select(.type == "frontmost_application_if")
          | .bundle_identifiers as $bundles
          | select(vscode_bundle_ids | all(. as $bundle | $bundles | index($bundle)))
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: VS Code Ctrl+Shift+C remains copy" \
      "1" "$karabiner_shift_c_vscode_mapping"

    karabiner_shift_v_vscode_mapping=$(
      jq -r '
        def vscode_bundle_ids:
          [
            "^com\\.facebook\\.fbvscode$",
            "^com\\.facebook\\.fbvscode-insiders$",
            "^com\\.microsoft\\.VSCode$",
            "^com\\.microsoft\\.VSCodeInsiders$",
            "^com\\.todesktop\\.230313mzl4w4u92$",
            "^com\\.vscodium$"
          ];

        [
          .profiles[]
          | select(.name == "Windows (Dotfiles)")
          | .complex_modifications.rules[]
          | select(.description == "V (Ctrl+Shift) [Only VS Code]")
          | .manipulators[]
          | select(.from.key_code == "v")
          | select(.from.modifiers.mandatory == ["control", "shift"])
          | select(.to[0].key_code == "f20")
          | select((.to[0] | has("modifiers")) | not)
          | .conditions[]
          | select(.type == "frontmost_application_if")
          | .bundle_identifiers as $bundles
          | select(vscode_bundle_ids | all(. as $bundle | $bundles | index($bundle)))
        ] | length
      ' "$karabiner_src"
    )
    _assert_eq "karabiner: VS Code Ctrl+Shift+V uses a private transport" \
      "1" "$karabiner_shift_v_vscode_mapping"
  else
    echo "  SKIP: Karabiner source assertions (jq unavailable)"
  fi

  echo ""
  echo "=== Karabiner merge hook ==="

  if command -v jq >/dev/null 2>&1; then
    karabiner_home=$(_tmpdir)
    karabiner_bin=$(_tmpdir)
    mkdir -p \
      "$karabiner_home/.config/dot/merge-hooks.d/karabiner/profiles.d" \
      "$karabiner_home/.config/karabiner" \
      "$karabiner_home/Applications/Karabiner-Elements.app" \
      "$karabiner_bin"
    cat >"$karabiner_home/.config/dot/merge-hooks.d/karabiner/profiles.d/10-profiles.json" <<'JSON'
{
    "profiles": [
        {
            "name": "Source Replacement",
            "selected": true
        },
        {
            "name": "Source Only"
        }
    ]
}
JSON
    cat >"$karabiner_home/.config/karabiner/karabiner.json" <<'JSON'
{
    "profiles": [
        {
            "name": "Local Only"
        },
        {
            "name": "Source Replacement",
            "selected": false,
            "stale": true
        }
    ]
}
JSON
    cat >"$karabiner_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' Darwin
EOF
    chmod +x "$karabiner_bin/uname"
    _run_karabiner_merge_for_test() {
      unset -f merge 2>/dev/null
      # shellcheck source=/dev/null
      . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/karabiner.sh"
      merge
    }
    HOME="$karabiner_home" PATH="$karabiner_bin:$PATH" _run_karabiner_merge_for_test
    unset -f _run_karabiner_merge_for_test merge 2>/dev/null
    karabiner_output=$(jq -c . "$karabiner_home/.config/karabiner/karabiner.json")
    _assert_contains "karabiner merge: local-only profile preserved" \
      '{"name":"Local Only"}' "$karabiner_output"
    _assert_contains "karabiner merge: matching source profile replaces local stale copy" \
      '{"name":"Source Replacement","selected":true}' "$karabiner_output"
    _assert_not_contains "karabiner merge: stale local profile copy removed" \
      '"stale":true' "$karabiner_output"
    _assert_contains "karabiner merge: source-only profile appended" \
      '{"name":"Source Only"}' "$karabiner_output"
  else
    echo "  SKIP: Karabiner merge hook assertions (jq unavailable)"
  fi

  echo ""
  echo "=== iTerm2 merge hook ==="

  iterm2_home=$(_tmpdir)
  iterm2_bin=$(_tmpdir)
  iterm2_defaults_log="$iterm2_home/defaults.log"
  mkdir -p \
    "$iterm2_home/.config/dot/merge-hooks.d/iterm2/defaults.d" \
    "$iterm2_home/.config/dot/merge-hooks.d/iterm2/profiles.d" \
    "$iterm2_home/Applications/iTerm.app" \
    "$iterm2_home/Library/Application Support/iTerm2/DynamicProfiles" \
    "$iterm2_bin"
  printf '%s\n' '{"Name": "Dotfiles"}' \
    >"$iterm2_home/.config/dot/merge-hooks.d/iterm2/profiles.d/10-dotfiles-dyn-profile.json"
  cat >"$iterm2_home/.config/dot/merge-hooks.d/iterm2/defaults.d/10-preferences.tsv" <<'EOF'
com.googlecode.iterm2	ApplePressAndHoldEnabled	bool	false
com.googlecode.iterm2	TabStyleWithAutomaticOption	int	5
com.googlecode.iterm2	AppleWindowTabbingMode	string	manual
com.googlecode.iterm2	PointerActions	plist	{ "Button,1,1,," = { Action = kContextMenuPointerAction; }; }
EOF
  cat >"$iterm2_bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' Darwin
EOF
  cat >"$iterm2_bin/defaults" <<'EOF'
#!/usr/bin/env bash
{
  first=true
  for arg in "$@"; do
    if $first; then
      first=false
    else
      printf '\t'
    fi
    printf '%s' "$arg"
  done
  printf '\n'
} >>"$DOT_TEST_DEFAULTS_LOG"
EOF
  chmod +x "$iterm2_bin/uname" "$iterm2_bin/defaults"
  _run_iterm2_merge_for_test() {
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/iterm2.sh"
    merge
  }

  : >"$iterm2_defaults_log"
  iterm2_missing_double_output=$(HOME="$iterm2_home" \
    PATH="$iterm2_bin:$PATH" \
    DOT_TEST_DEFAULTS_LOG="$iterm2_defaults_log" \
    _run_iterm2_merge_for_test 2>&1)
  _assert_eq "iterm2 defaults: test mode requires an explicit double" \
    "" "$(cat "$iterm2_defaults_log")"
  _assert_contains "iterm2 defaults: missing test double is reported" \
    "test defaults" "$iterm2_missing_double_output"

  : >"$iterm2_defaults_log"
  iterm2_non_account_output=$(DOT_TEST=0 HOME="$iterm2_home" \
    PATH="$iterm2_bin:$PATH" \
    DOT_TEST_DEFAULTS_LOG="$iterm2_defaults_log" \
    _run_iterm2_merge_for_test 2>&1)
  _assert_eq "iterm2 defaults: non-account HOME leaves preferences untouched" \
    "" "$(cat "$iterm2_defaults_log")"
  _assert_contains "iterm2 defaults: non-account HOME is reported" \
    "account home" "$iterm2_non_account_output"

  : >"$iterm2_defaults_log"
  HOME="$iterm2_home" \
    PATH="$iterm2_bin:$PATH" \
    DOT_TEST_DEFAULTS="$iterm2_bin/defaults" \
    DOT_TEST_DEFAULTS_LOG="$iterm2_defaults_log" \
    _run_iterm2_merge_for_test
  unset -f _run_iterm2_merge_for_test merge 2>/dev/null
  _assert_file_content "iterm2: dynamic profile copied" \
    '{"Name": "Dotfiles"}' \
    "$iterm2_home/Library/Application Support/iTerm2/DynamicProfiles/dotfiles-dyn-profile.json"
  iterm2_defaults_output=$(cat "$iterm2_defaults_log")
  _assert_contains "iterm2 defaults: key repeat policy applied" \
    $'write\tcom.googlecode.iterm2\tApplePressAndHoldEnabled\t-bool\tfalse' \
    "$iterm2_defaults_output"
  _assert_contains "iterm2 defaults: tab style policy applied" \
    $'write\tcom.googlecode.iterm2\tTabStyleWithAutomaticOption\t-int\t5' \
    "$iterm2_defaults_output"
  _assert_contains "iterm2 defaults: window tabbing policy applied" \
    $'write\tcom.googlecode.iterm2\tAppleWindowTabbingMode\t-string\tmanual' \
    "$iterm2_defaults_output"
  _assert_contains "iterm2 defaults: pointer actions policy applied" \
    $'write\tcom.googlecode.iterm2\tPointerActions\t{' \
    "$iterm2_defaults_output"

  echo ""
  echo "=== SSH config merge hook ==="

  SSH_DIR="$TEST_HOME/.ssh"
  SSH_CONFIG="$SSH_DIR/config"
  rm -rf "$SSH_DIR"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d"

  # Source the SSH merge hook so we can call merge() directly.
  _SSH_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/ssh.sh"

  _run_ssh_merge() {
    unset -f merge 2>/dev/null
    # shellcheck source=/dev/null
    . "$_SSH_HOOK"
    merge
  }

  # No ssh-config files → no-op
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d"
  _run_ssh_merge 2>/dev/null
  if [[ ! -f "$SSH_CONFIG" ]]; then
    _pass "ssh hook: no source files → no config"
  else
    _fail "ssh hook: no source files → no config"
  fi
  mkdir -p "$SSH_DIR"
  cat >"$SSH_CONFIG" <<'EXISTING'
Host manual-only
  HostName manual.example.com

# dot-managed:ssh:ssh-config begin
# DO NOT EDIT: changes will be overwritten by dot update
# source: /old/ssh-config
Host stale-managed
  HostName stale.example.com
# dot-managed:ssh:ssh-config end
EXISTING
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook no source: preserves manual entries" "Host manual-only" "$ssh_content"
  _assert_not_contains "ssh hook no source: prunes stale managed entries" "stale-managed" "$ssh_content"

  # Single source file → creates marked block
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-primary.ssh_config" <<'SSH'
# Header comment
# Another comment

Host testhost
  HostName test.example.com
  User testuser
SSH
  _run_ssh_merge 2>/dev/null
  _assert_file_exists "ssh hook: config created" "$SSH_CONFIG"
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook: begin marker" "dot-managed:ssh:10-primary.ssh_config begin" "$ssh_content"
  _assert_contains "ssh hook: end marker" "dot-managed:ssh:10-primary.ssh_config end" "$ssh_content"
  _assert_contains "ssh hook: host present" "Host testhost" "$ssh_content"
  _assert_contains "ssh hook: options present" "HostName test.example.com" "$ssh_content"
  _assert_contains "ssh hook: source comments preserved" "Header comment" "$ssh_content"

  # Idempotent — running again doesn't change output
  cp "$SSH_CONFIG" "$SSH_CONFIG.prev"
  _run_ssh_merge 2>/dev/null
  if cmp -s "$SSH_CONFIG.prev" "$SSH_CONFIG"; then
    _pass "ssh hook: idempotent"
  else
    _fail "ssh hook: idempotent"
  fi
  rm -f "$SSH_CONFIG.prev"

  # Updated source → block content updated
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-primary.ssh_config" <<'SSH'
Host testhost
  HostName changed.example.com
  User newuser
SSH
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook: updated hostname" "changed.example.com" "$ssh_content"
  _assert_not_contains "ssh hook: old hostname gone" "test.example.com" "$ssh_content"

  # Two source files → two separate marked blocks
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-personal.ssh-config" <<'SSH'
Host personal
  HostName personal.example.com
  User me
SSH
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-primary.ssh_config"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/20-extra.ssh-config" <<'SSH'
Host extra
  HostName extra.example.com
  User extrauser
SSH
  rm -f "$SSH_CONFIG"
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook multi: personal begin" "dot-managed:ssh:10-personal.ssh-config begin" "$ssh_content"
  _assert_contains "ssh hook multi: personal end" "dot-managed:ssh:10-personal.ssh-config end" "$ssh_content"
  _assert_contains "ssh hook multi: extra begin" "dot-managed:ssh:20-extra.ssh-config begin" "$ssh_content"
  _assert_contains "ssh hook multi: extra end" "dot-managed:ssh:20-extra.ssh-config end" "$ssh_content"
  _assert_contains "ssh hook multi: personal host" "Host personal" "$ssh_content"
  _assert_contains "ssh hook multi: extra host" "Host extra" "$ssh_content"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/20-extra.ssh-config"

  # Source migration: replacing one family source with another should remove the
  # old managed block, not leave duplicate generated host definitions behind.
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-personal.ssh-config"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/50-personal.ssh-config" <<'SSH'
Host migrated-personal
  HostName migrated.example.com
SSH
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_not_contains "ssh hook migration: old source marker pruned" \
    "dot-managed:ssh:10-personal.ssh-config begin" "$ssh_content"
  _assert_contains "ssh hook migration: new source marker present" \
    "dot-managed:ssh:50-personal.ssh-config begin" "$ssh_content"
  _assert_contains "ssh hook migration: new host present" "Host migrated-personal" "$ssh_content"
  rm -f "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/50-personal.ssh-config"

  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/60-env.replace"
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/60-env.replace/80-host.ssh-config" <<'SSH'
Host replace-winner
  HostName replace.example.com
SSH
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/60-env.replace/90-README" <<'TXT'
This visible documentation file must not win the SSH replace group.
TXT
  rm -f "$SSH_CONFIG"
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook replace: typed lower-priority fragment wins over README" \
    "Host replace-winner" "$ssh_content"
  _assert_not_contains "ssh hook replace: README not installed" \
    "visible documentation file" "$ssh_content"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/60-env.replace"

  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-primary.ssh-config" <<'SSH'
Host restored
  HostName restored.example.com
SSH

  # Hand-managed entries preserved above marked blocks
  cat >"$SSH_CONFIG" <<'EXISTING'
Host mymanual
  HostName manual.example.com
  User manual
EXISTING
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook preserve: manual host kept" "Host mymanual" "$ssh_content"
  _assert_contains "ssh hook preserve: managed blocks present" "dot-managed:ssh" "$ssh_content"

  # Hand-managed entries come first (can override managed hosts)
  first_host=$(grep -m1 '^Host ' "$SSH_CONFIG")
  _assert_contains "ssh hook order: hand-managed first" "mymanual" "$first_host"

  # Permissions are 600
  perms=$(stat -c '%a' "$SSH_CONFIG" 2>/dev/null || stat -f '%Lp' "$SSH_CONFIG" 2>/dev/null)
  _assert_eq "ssh hook: config is 600" "600" "$perms"

  # Inline comments preserved (not stripped as header)
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d/10-primary.ssh-config" <<'SSH'
Host commented
  HostName commented.example.com
  #RemoteCommand /bin/bash
  User test
SSH
  rm -f "$SSH_CONFIG"
  _run_ssh_merge 2>/dev/null
  ssh_content=$(cat "$SSH_CONFIG")
  _assert_contains "ssh hook: inline comment preserved" "#RemoteCommand" "$ssh_content"

  # No blank-line accumulation across repeated merges
  cat >"$SSH_CONFIG" <<'EXISTING'
Host stable
  HostName stable.example.com
  User user
EXISTING
  for _i in 1 2 3 4 5; do
    _run_ssh_merge 2>/dev/null
  done
  # Count max consecutive blank lines
  max_consecutive=$(awk '/^$/{c++;next}{if(c>m)m=c;c=0}END{if(c>m)m=c;print m}' "$SSH_CONFIG")
  if [[ "$max_consecutive" -le 2 ]]; then
    _pass "ssh hook: no blank-line accumulation (max $max_consecutive consecutive)"
  else
    _fail "ssh hook: no blank-line accumulation (max $max_consecutive consecutive, expected ≤2)"
  fi

  # Clean up
  rm -rf "$SSH_DIR"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/ssh/config.d"

  echo ""
  echo "=== Global ignore merge hook ==="

  IGNORE_FILE="$TEST_HOME/.ignore"
  rm -f "$IGNORE_FILE"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/ignore/ignore.d"
  mkdir -p "$TEST_HOME/.config/dot/merge-hooks.d/ignore/ignore.d"
  _IGNORE_HOOK="$REAL_HOME/.local/lib/dotfiles/merge-hooks.d/ignore.sh"

  _run_ignore_merge() {
    unset -f merge _ignore_sources 2>/dev/null
    # shellcheck source=/dev/null
    . "$_IGNORE_HOOK"
    merge
  }

  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns" <<'EOF'
.cache/
EOF
  cat >"$TEST_HOME/.config/dot/merge-hooks.d/ignore/ignore.d/80-work" <<'EOF'
build-output/
EOF
  _run_ignore_merge 2>/dev/null
  _assert_file_exists "ignore hook: output created" "$IGNORE_FILE"
  ignore_content=$(cat "$IGNORE_FILE")
  _assert_contains "ignore hook: base source marker" \
    "dot-managed:ignore:10-patterns begin" "$ignore_content"
  _assert_contains "ignore hook: prefixed source marker" \
    "dot-managed:ignore:80-work begin" "$ignore_content"
  _assert_contains "ignore hook: base pattern merged" \
    ".cache/" "$ignore_content"
  _assert_contains "ignore hook: prefixed pattern merged" \
    "build-output/" "$ignore_content"
  rm -f "$IGNORE_FILE"
  rm -rf "$TEST_HOME/.config/dot/merge-hooks.d/ignore/ignore.d"

  echo "=== D4 merge hook ownership boundary ==="

  expected_base_hooks=$(printf '%s\n' \
    agent-rules cron ignore iterm2 karabiner ssh tmux wezterm | LC_ALL=C sort)
  actual_hooks=$(_dot_test_merge_hook_names "$REAL_HOME")
  missing_base_hooks=$(comm -23 <(printf '%s\n' "$expected_base_hooks") \
    <(printf '%s\n' "$actual_hooks"))
  _assert_eq "merge hooks: every base hook remains available during staging" \
    "" "$missing_base_hooks"
  temporary_hooks=$(comm -13 <(printf '%s\n' "$expected_base_hooks") \
    <(printf '%s\n' "$actual_hooks"))
  baseline=$REAL_HOME/.local/share/doc/dotfiles/overlay-profile-baseline-disposition.tsv
  while IFS= read -r hook_name; do
    [[ -n $hook_name ]] || continue
    hook_path=.local/lib/dotfiles/merge-hooks.d/$hook_name.sh
    if awk -F '\t' -v path="$hook_path" '
      NR > 1 && $1 == path && $5 == "keep" && $6 == "remove" { found=1 }
      END { exit found ? 0 : 1 }
    ' "$baseline"; then
      _pass "merge hooks staging: temporary capability hook is inventoried: $hook_name"
    else
      _fail "merge hooks staging: temporary capability hook is inventoried: $hook_name"
    fi
  done <<<"$temporary_hooks"
}
