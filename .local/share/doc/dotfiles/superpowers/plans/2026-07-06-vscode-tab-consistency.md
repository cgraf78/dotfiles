# VS Code Tab-Switching Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Ctrl-Tab`, `Ctrl-Shift-Tab`, `Alt-Shift-[`, `Alt-Shift-]` behave consistently in VS Code (editor-focus and terminal-focus), and bridge the tmux/nvim bubble-up case into VS Code the same way it already works for WezTerm — routing correctly when the same tmux session is attached from both VS Code and WezTerm simultaneously.

**Architecture:** A new layered bridge in `~/git/termnav` (`bin/vscode-switch-tab`/`bin/vscode-move-tab` → `lib/termnav/shell/vscode-command.sh` seam → `lib/termnav/shell/vscode-backend-mcp.sh`) calls VS Code's already-installed MCP extension over local HTTP to execute editor commands. `tmux.conf` and `nvim`'s `keymaps.lua` both gain a branch, keyed on the triggering/active client's per-client `#{client_termtype}` (not the session-wide `VSCODE_IPC_HOOK_CLI` env var, which would misroute when both a VS Code and a WezTerm client are attached to the same session), that calls the new scripts instead of the WezTerm ones when the outer terminal is VS Code.

**Tech Stack:** Bash (termnav scripts, tmux.conf), Lua (nvim keymaps.lua), `curl` (MCP HTTP calls), tmux's own test/mocking conventions (`test/helpers.sh` in termnav, `~/.local/lib/dot/tests/helpers.sh` in dotfiles).

## Global Constraints

- Full design context: `.local/share/doc/dot/superpowers/specs/2026-07-06-vscode-tab-consistency-design.md` (spec doc, same repo).
- Silent no-op on any bridge failure (unreachable MCP server, missing auth token, timeout) — never surface an error to the user, matching existing "nothing to bubble to" behavior.
- The VS Code backend mechanism must stay swappable behind `TERMNAV_VSCODE_BACKEND` (default `mcp`) — callers (`bin/vscode-switch-tab`, `bin/vscode-move-tab`, `tmux.conf`, `nvim`) never reference the MCP backend directly.
- `nvim`'s VS Code bridge call must be async (`vim.fn.jobstart` with `detach = true`), never `vim.fn.system` — a hung MCP server must not freeze the editor.
- `tmux.conf`'s VS Code bridge call must stay `run-shell -b` (background), matching the existing WezTerm calls.
- Auth token contract: `${XDG_STATE_HOME:-$HOME/.local/state}/dot/vscode-mcp-auth-token`, written by dotfiles' `~/.local/lib/dot/core/merge-hooks/vscode.sh` (read-only from termnav's side — never generate or manage the token there).
- Every `bin/*` script in termnav needs a man page (`man/man1/<name>.1`) with a `.SH NAME` section — enforced by `test/suites/manpage-test`.
- Follow existing test conventions exactly: termnav tests source `test/helpers.sh` and use `_assert_eq`/`_assert_contains`/`_assert_exit`/`_tmpdir`/`_test_summary`; dotfiles tests source `~/.local/lib/dot/tests/helpers.sh` with the same helpers plus `_nvim_lua`.
- Run `git --git-dir=$HOME/.dotfiles --work-tree=$HOME <cmd>` for all dotfiles git operations from `$HOME` (never `git -C ~/.dotfiles`, which breaks the repo's `git` launcher wrapper). Use plain `git <cmd>` from inside `~/git/termnav` (it's a normal repo, not the bare-at-$HOME setup).

---

### Task 1: termnav — VS Code backend dispatch seam

**Files:**

- Create: `~/git/termnav/lib/termnav/shell/vscode-command.sh`
- Test: `~/git/termnav/test/suites/vscode-test` (new file — created here, extended in later tasks)

**Interfaces:**

- Consumes: nothing from other tasks.

- Produces: `termnav_vscode_execute_command <command-id>` — dispatches to `termnav_vscode_${TERMNAV_VSCODE_BACKEND:-mcp}_execute_command <command-id>`, defined by sourcing `lib/termnav/shell/vscode-backend-${TERMNAV_VSCODE_BACKEND:-mcp}.sh` from the same directory. Returns the backend function's exit code, or `1` if the backend file/function doesn't exist. This is the ONLY function later tasks (Task 3's `bin/vscode-switch-tab`/`bin/vscode-move-tab`) call.

- [ ] **Step 1: Write the failing test for the dispatch seam**

Create `~/git/termnav/test/suites/vscode-test`:

```bash
#!/usr/bin/env bash
# vscode-test — VS Code command bridge: dispatch seam, MCP backend, CLI scripts.

set -o pipefail
export NO_COLOR=1

TERMNAV_TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TERMNAV_ROOT="$(cd -- "$TERMNAV_TEST_DIR/.." && pwd -P)"

# shellcheck source=../helpers.sh
. "$TERMNAV_TEST_DIR/helpers.sh"

vscode_command_sh="$TERMNAV_ROOT/lib/termnav/shell/vscode-command.sh"

echo "=== vscode-command.sh: backend dispatch seam ==="

seam_dir=$(_tmpdir)
cat >"$seam_dir/vscode-backend-fake.sh" <<'EOF'
# shellcheck shell=bash
termnav_vscode_fake_execute_command() {
  printf 'fake-backend-called:%s\n' "$1" >>"$FAKE_BACKEND_LOG"
  return 0
}
EOF

fake_log=$(_tmpdir)/fake-backend.log
seam_result=$(
  FAKE_BACKEND_LOG="$fake_log" TERMNAV_VSCODE_BACKEND=fake bash -c "
    . '$vscode_command_sh'
    # Override the backend lookup directory so the dispatcher finds our fake
    # backend instead of the real one shipped next to vscode-command.sh.
    _termnav_vscode_command_dir() { printf '%s\n' '$seam_dir'; }
    termnav_vscode_execute_command 'workbench.action.nextEditor'
  "
)
seam_rc=$?
_assert_exit "dispatcher: fake backend call succeeds" 0 "$seam_rc"
_assert_eq "dispatcher: routes to the selected backend, not a hardcoded one" \
  "fake-backend-called:workbench.action.nextEditor" "$(cat "$fake_log")"
_assert_eq "dispatcher: does not also call any other backend" \
  "1" "$(wc -l <"$fake_log" | tr -d ' ')"

set +e
unknown_result=$(
  TERMNAV_VSCODE_BACKEND=does-not-exist bash -c "
    . '$vscode_command_sh'
    termnav_vscode_execute_command 'workbench.action.nextEditor'
  "
)
unknown_rc=$?
set -e
_assert_exit "dispatcher: unknown backend fails closed, not open" 1 "$unknown_rc"
_assert_eq "dispatcher: unknown backend produces no output" "" "$unknown_result"

_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `chmod +x ~/git/termnav/test/suites/vscode-test && ~/git/termnav/test/suites/vscode-test`
Expected: FAIL — `lib/termnav/shell/vscode-command.sh` doesn't exist yet, so `. '$vscode_command_sh'` errors and every assertion after it fails or the script aborts.

- [ ] **Step 3: Write the minimal implementation**

Create `~/git/termnav/lib/termnav/shell/vscode-command.sh`:

```bash
# shellcheck shell=bash
# Dispatch seam for executing a VS Code command via a pluggable backend.
#
# Callers (bin/vscode-switch-tab, bin/vscode-move-tab) only know VS Code
# command IDs — never how a command actually gets executed. This file owns
# backend selection and uniform failure handling so a future backend swap
# (if the MCP extension proves problematic) only changes
# TERMNAV_VSCODE_BACKEND's default, never any caller.

_termnav_vscode_command_dir() {
  cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

# Execute a VS Code command by ID through the selected backend ($1).
# Silently no-ops (returns non-zero, prints nothing) on any failure --
# unreachable backend, missing auth, timeout -- matching how the existing
# WezTerm bubble-up path already does nothing when there's nowhere to
# bubble to.
termnav_vscode_execute_command() {
  local command_id="$1" backend backend_file backend_fn

  backend="${TERMNAV_VSCODE_BACKEND:-mcp}"
  backend_file="$(_termnav_vscode_command_dir)/vscode-backend-${backend}.sh"
  [[ -r "$backend_file" ]] || return 1

  # shellcheck source=/dev/null
  . "$backend_file" || return 1

  backend_fn="termnav_vscode_${backend}_execute_command"
  declare -F "$backend_fn" >/dev/null 2>&1 || return 1

  "$backend_fn" "$command_id"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/git/termnav/test/suites/vscode-test`
Expected: `Results: 5 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
cd ~/git/termnav
git add lib/termnav/shell/vscode-command.sh test/suites/vscode-test
git commit -m "Add VS Code command-execution dispatch seam

Lets tmux/nvim ask VS Code to run a command (switch/move an editor
tab) without knowing how that actually happens. Backend selection is
one variable (TERMNAV_VSCODE_BACKEND), so a future backend swap never
touches callers."
```

---

### Task 2: termnav — MCP backend

**Files:**

- Create: `~/git/termnav/lib/termnav/shell/vscode-backend-mcp.sh`
- Modify: `~/git/termnav/test/suites/vscode-test`

**Interfaces:**

- Consumes: nothing from Task 1 directly (this file is sourced BY Task 1's dispatcher, by naming convention; it doesn't call anything Task 1 defines).

- Produces: `termnav_vscode_mcp_execute_command <command-id>` — the function Task 1's dispatcher looks up by name (`termnav_vscode_${backend}_execute_command` where `backend=mcp`). Returns 0 on a successful VS Code command execution, non-zero on any failure (missing token, connection failure, timeout, or a JSON-RPC error surviving the initialize-retry).

- [ ] **Step 1: Write the failing tests**

Append to `~/git/termnav/test/suites/vscode-test` (before the final `_test_summary` line — remove that line, add this block, then re-add `_test_summary` at the very end):

```bash
echo
echo "=== vscode-backend-mcp.sh: MCP HTTP backend ==="

vscode_backend_mcp_sh="$TERMNAV_ROOT/lib/termnav/shell/vscode-backend-mcp.sh"

_mcp_test_home() {
  local home token_dir
  home=$(_tmpdir)
  token_dir="$home/.local/state/dot"
  mkdir -p "$token_dir"
  printf 'test-token-abc123\n' >"$token_dir/vscode-mcp-auth-token"
  printf '%s\n' "$home"
}

# Case 1: auth token missing -- must fail fast, no curl invocation at all.
no_token_home=$(_tmpdir)
mock_bin=$(_tmpdir)
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl called\n' >>"$CURL_CALL_LOG"
exit 1
EOF
chmod +x "$mock_bin/curl"
curl_call_log=$(_tmpdir)/no-token-curl.log
set +e
HOME="$no_token_home" CURL_CALL_LOG="$curl_call_log" PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
no_token_rc=$?
set -e
_assert_exit "MCP backend: missing auth token fails" 1 "$no_token_rc"
_assert_file_missing "MCP backend: missing auth token never invokes curl" "$curl_call_log"

# Case 2: successful direct tools/call (no initialize needed).
success_home=$(_mcp_test_home)
mock_bin=$(_tmpdir)
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
{
  printf 'argv:'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$CURL_CALL_LOG"
printf '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}'
EOF
chmod +x "$mock_bin/curl"
success_log=$(_tmpdir)/success-curl.log
HOME="$success_home" CURL_CALL_LOG="$success_log" PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
success_rc=$?
_assert_exit "MCP backend: successful direct tools/call returns success" 0 "$success_rc"
success_calls=$(cat "$success_log")
_assert_eq "MCP backend: exactly one curl call when no initialize is needed" \
  "1" "$(printf '%s\n' "$success_calls" | grep -c '^argv:')"
_assert_contains "MCP backend: sends bearer auth token" \
  "Authorization: Bearer test-token-abc123" "$success_calls"
_assert_contains "MCP backend: posts to the default port" \
  "http://127.0.0.1:9876/mcp" "$success_calls"
_assert_contains "MCP backend: calls execute_command with the requested command id" \
  '\"command\":\"workbench.action.nextEditor\"' "$success_calls"
_assert_contains "MCP backend: bounds every call with a timeout" \
  "--max-time" "$success_calls"

# Case 3: tools/call errors first (uninitialized session), succeeds after
# an initialize round-trip.
init_home=$(_mcp_test_home)
mock_bin=$(_tmpdir)
call_count_file=$(_tmpdir)/call-count
printf '0\n' >"$call_count_file"
cat >"$mock_bin/curl" <<EOF
#!/usr/bin/env bash
{
  printf 'argv:'
  printf ' <%s>' "\$@"
  printf '\n'
} >>"\$CURL_CALL_LOG"
count=\$(cat "$call_count_file")
count=\$((count + 1))
printf '%s\n' "\$count" >"$call_count_file"
case "\$*" in
  *tools/call*)
    if [[ "\$count" -eq 1 ]]; then
      printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"not initialized"}}'
    else
      printf '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}'
    fi
    ;;
  *initialize*)
    printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}'
    ;;
esac
EOF
chmod +x "$mock_bin/curl"
init_log=$(_tmpdir)/init-curl.log
HOME="$init_home" CURL_CALL_LOG="$init_log" PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
init_rc=$?
_assert_exit "MCP backend: succeeds after falling back to initialize" 0 "$init_rc"
init_calls=$(cat "$init_log")
_assert_eq "MCP backend: three calls total (tools/call, initialize, tools/call retry)" \
  "3" "$(printf '%s\n' "$init_calls" | grep -c '^argv:')"
_assert_contains "MCP backend: retries tools/call after initialize succeeds" \
  "initialize" "$init_calls"

# Case 4: tools/call fails even after the initialize retry.
persistent_fail_home=$(_mcp_test_home)
mock_bin=$(_tmpdir)
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
{
  printf 'argv:'
  printf ' <%s>' "$@"
  printf '\n'
} >>"$CURL_CALL_LOG"
case "$*" in
  *tools/call*)
    printf '{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"still broken"}}'
    ;;
  *initialize*)
    printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}'
    ;;
esac
EOF
chmod +x "$mock_bin/curl"
persistent_fail_log=$(_tmpdir)/persistent-fail-curl.log
set +e
HOME="$persistent_fail_home" CURL_CALL_LOG="$persistent_fail_log" PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
persistent_fail_rc=$?
set -e
_assert_exit "MCP backend: fails when tools/call errors even after initialize" 1 "$persistent_fail_rc"

# Case 5: curl itself fails (connection refused) -- no retry attempted.
refused_home=$(_mcp_test_home)
mock_bin=$(_tmpdir)
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'argv: <%s>\n' "$*" >>"$CURL_CALL_LOG"
exit 7
EOF
chmod +x "$mock_bin/curl"
refused_log=$(_tmpdir)/refused-curl.log
set +e
HOME="$refused_home" CURL_CALL_LOG="$refused_log" PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
refused_rc=$?
set -e
_assert_exit "MCP backend: connection refused fails without retrying" 1 "$refused_rc"
refused_calls=$(cat "$refused_log")
_assert_eq "MCP backend: exactly one attempt when curl itself fails" \
  "1" "$(printf '%s\n' "$refused_calls" | grep -c '^argv:')"

# Case 6: VSCODE_MCP_PORT override changes the target URL.
port_home=$(_mcp_test_home)
mock_bin=$(_tmpdir)
cat >"$mock_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'argv: <%s>\n' "$*" >>"$CURL_CALL_LOG"
printf '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}'
EOF
chmod +x "$mock_bin/curl"
port_log=$(_tmpdir)/port-curl.log
HOME="$port_home" CURL_CALL_LOG="$port_log" VSCODE_MCP_PORT=9999 PATH="$mock_bin:$PATH" bash -c "
  . '$vscode_command_sh'
  . '$vscode_backend_mcp_sh'
  termnav_vscode_mcp_execute_command 'workbench.action.nextEditor'
"
_assert_contains "MCP backend: honors VSCODE_MCP_PORT override" \
  "http://127.0.0.1:9999/mcp" "$(cat "$port_log")"

_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/git/termnav/test/suites/vscode-test`
Expected: FAIL on every new assertion in the "MCP HTTP backend" section — `vscode-backend-mcp.sh` doesn't exist, so `. '$vscode_backend_mcp_sh'` errors.

- [ ] **Step 3: Write the minimal implementation**

Create `~/git/termnav/lib/termnav/shell/vscode-backend-mcp.sh`:

```bash
# shellcheck shell=bash
# MCP backend for termnav_vscode_execute_command: calls the
# nabheet.vscode-ide-mcp extension's local HTTP JSON-RPC API to execute a
# VS Code command by ID.
#
# Contract with dotfiles: the auth token is written by
# ~/.local/lib/dot/core/merge-hooks/vscode.sh to
# ${XDG_STATE_HOME:-$HOME/.local/state}/dot/vscode-mcp-auth-token. This file
# only reads it -- it never generates or manages the token.

_termnav_vscode_mcp_port() {
  printf '%s\n' "${VSCODE_MCP_PORT:-9876}"
}

_termnav_vscode_mcp_auth_token_path() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dot/vscode-mcp-auth-token"
}

_termnav_vscode_mcp_auth_token() {
  local path
  path="$(_termnav_vscode_mcp_auth_token_path)"
  [[ -r "$path" ]] || return 1
  cat "$path"
}

# POST a JSON-RPC request. Args: method, params (raw JSON), token, port.
# Bounded by --max-time so a dead/slow server never hangs the caller --
# tmux's run-shell -b is already non-blocking, but nvim's async jobstart
# still needs this to resolve promptly.
_termnav_vscode_mcp_post() {
  local method="$1" params="$2" token="$3" port="$4"
  curl -sS --max-time 2 -X POST "http://127.0.0.1:${port}/mcp" \
    -H 'Content-Type: application/json' \
    -H "Authorization: Bearer ${token}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"${method}\",\"params\":${params}}"
}

# Tries tools/call directly first (the server's documented "direct POST,
# backward compat, synchronous" mode). If that response carries a JSON-RPC
# error (observed if a session/initialize step turns out to be required),
# falls back to initialize + one retry of tools/call.
termnav_vscode_mcp_execute_command() {
  local command_id="$1" token port response call_params

  token="$(_termnav_vscode_mcp_auth_token)" || return 1
  port="$(_termnav_vscode_mcp_port)"

  call_params=$(printf '{"name":"execute_command","arguments":{"command":"%s"}}' "$command_id")

  response="$(_termnav_vscode_mcp_post 'tools/call' "$call_params" "$token" "$port")" || return 1
  [[ -n "$response" ]] || return 1
  [[ "$response" == *'"error"'* ]] || return 0

  _termnav_vscode_mcp_post 'initialize' '{"protocolVersion":"2024-11-05","capabilities":{}}' "$token" "$port" >/dev/null || return 1
  response="$(_termnav_vscode_mcp_post 'tools/call' "$call_params" "$token" "$port")" || return 1
  [[ -n "$response" && "$response" != *'"error"'* ]]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/git/termnav/test/suites/vscode-test`
Expected: `Results: 20 passed, 0 failed` (5 from Task 1 + 15 new)

- [ ] **Step 5: Commit**

```bash
cd ~/git/termnav
git add lib/termnav/shell/vscode-backend-mcp.sh test/suites/vscode-test
git commit -m "Add MCP HTTP backend for the VS Code command bridge

Calls the already-installed nabheet.vscode-ide-mcp extension's
execute_command tool over loopback HTTP. Tries a direct tools/call
first (matching the server's documented stateless mode); if that
comes back with a JSON-RPC error, falls back to an initialize
handshake and retries once. Every call is bounded by --max-time so a
dead server fails fast instead of hanging."
```

---

### Task 3: termnav — CLI scripts, man pages

**Files:**

- Create: `~/git/termnav/bin/vscode-switch-tab`
- Create: `~/git/termnav/bin/vscode-move-tab`
- Create: `~/git/termnav/man/man1/vscode-switch-tab.1`
- Create: `~/git/termnav/man/man1/vscode-move-tab.1`
- Modify: `~/git/termnav/test/suites/vscode-test`

**Interfaces:**

- Consumes: `termnav_vscode_execute_command <command-id>` (Task 1).

- Produces: `vscode-switch-tab [next|previous]` and `vscode-move-tab [left|right]` — the stable public CLI, callable from `tmux.conf` (Task 6) and `nvim` (Task 7) exactly like `wezterm-switch-tab`/`wezterm-move-tab` already are.

- [ ] **Step 1: Write the failing tests**

Append to `~/git/termnav/test/suites/vscode-test` (before `_test_summary`):

```bash
echo
echo "=== vscode-switch-tab / vscode-move-tab: CLI scripts ==="

vscode_switch_tab="$TERMNAV_ROOT/bin/vscode-switch-tab"
vscode_move_tab="$TERMNAV_ROOT/bin/vscode-move-tab"

set +e
switch_help=$("$vscode_switch_tab" --help 2>&1)
switch_help_rc=$?
set -e
_assert_exit "vscode-switch-tab: help exits successfully" 0 "$switch_help_rc"
_assert_contains "vscode-switch-tab: usage text" "usage: vscode-switch-tab" "$switch_help"

set +e
move_help=$("$vscode_move_tab" --help 2>&1)
move_help_rc=$?
set -e
_assert_exit "vscode-move-tab: help exits successfully" 0 "$move_help_rc"
_assert_contains "vscode-move-tab: usage text" "usage: vscode-move-tab" "$move_help"

# Isolate CLI direction->command-id mapping with a fake `curl` standing in
# for the real MCP endpoint, reusing the same technique as Task 2's MCP
# backend tests -- this exercises the real dispatcher and real mcp backend
# end to end, just with the network call stubbed, rather than inventing a
# second backend-swap mechanism only for this test.
mapping_home=$(_tmpdir)
mkdir -p "$mapping_home/.local/state/dot"
printf 'mapping-test-token\n' >"$mapping_home/.local/state/dot/vscode-mcp-auth-token"
mapping_bin=$(_tmpdir)
cat >"$mapping_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MAPPING_LOG"
printf '{"jsonrpc":"2.0","id":1,"result":{"content":[]}}'
EOF
chmod +x "$mapping_bin/curl"

mapping_log=$(_tmpdir)/mapping.log
: >"$mapping_log"
HOME="$mapping_home" MAPPING_LOG="$mapping_log" PATH="$mapping_bin:$PATH" "$vscode_switch_tab" next
HOME="$mapping_home" MAPPING_LOG="$mapping_log" PATH="$mapping_bin:$PATH" "$vscode_switch_tab" previous
_assert_eq "vscode-switch-tab: next maps to nextEditor, previous to previousEditor" \
  "$(printf '"command":"workbench.action.nextEditor"\n"command":"workbench.action.previousEditor"')" \
  "$(grep -oE '"command":"[^"]+"' "$mapping_log")"

: >"$mapping_log"
HOME="$mapping_home" MAPPING_LOG="$mapping_log" PATH="$mapping_bin:$PATH" "$vscode_move_tab" left
HOME="$mapping_home" MAPPING_LOG="$mapping_log" PATH="$mapping_bin:$PATH" "$vscode_move_tab" right
_assert_eq "vscode-move-tab: left maps to moveEditorLeftInGroup, right to moveEditorRightInGroup" \
  "$(printf '"command":"workbench.action.moveEditorLeftInGroup"\n"command":"workbench.action.moveEditorRightInGroup"')" \
  "$(grep -oE '"command":"[^"]+"' "$mapping_log")"

set +e
bad_direction=$("$vscode_switch_tab" sideways 2>&1)
bad_direction_rc=$?
set -e
_assert_exit "vscode-switch-tab: rejects an invalid direction" 2 "$bad_direction_rc"

echo
echo "=== shdeps-installed symlink entry points (vscode) ==="

vscode_symlink_bin=$(_tmpdir)/bin
mkdir -p "$vscode_symlink_bin"
ln -s "$vscode_switch_tab" "$vscode_symlink_bin/vscode-switch-tab"
ln -s "$vscode_move_tab" "$vscode_symlink_bin/vscode-move-tab"

set +e
symlink_switch_help=$("$vscode_symlink_bin/vscode-switch-tab" --help 2>&1)
symlink_switch_rc=$?
set -e
_assert_exit "vscode-switch-tab symlink: help exits successfully" 0 "$symlink_switch_rc"
_assert_contains "vscode-switch-tab symlink: resolves dependency libraries" \
  "usage: vscode-switch-tab" "$symlink_switch_help"

set +e
symlink_move_help=$("$vscode_symlink_bin/vscode-move-tab" --help 2>&1)
symlink_move_rc=$?
set -e
_assert_exit "vscode-move-tab symlink: help exits successfully" 0 "$symlink_move_rc"
_assert_contains "vscode-move-tab symlink: resolves dependency libraries" \
  "usage: vscode-move-tab" "$symlink_move_help"

_test_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/git/termnav/test/suites/vscode-test`
Expected: FAIL — `bin/vscode-switch-tab` and `bin/vscode-move-tab` don't exist.

- [ ] **Step 3: Write the minimal implementation**

Create `~/git/termnav/bin/vscode-switch-tab`:

```bash
#!/usr/bin/env bash
# Ask VS Code to switch the active editor tab.

set -euo pipefail

_termnav_script_parent() {
  case "$1" in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

_termnav_script_dir() {
  local path="$1" dir target
  while [[ -L "$path" ]]; do
    dir=$(cd -P -- "$(_termnav_script_parent "$path")" && pwd) || return 1
    target=$(readlink "$path") || return 1
    [[ "$target" == /* ]] || target="$dir/$target"
    path="$target"
  done
  cd -P -- "$(_termnav_script_parent "$path")" && pwd
}

script_dir=$(_termnav_script_dir "${BASH_SOURCE[0]}") || {
  echo "vscode-switch-tab: cannot resolve executable path" >&2
  exit 2
}
lib_dir="${script_dir%/bin}/lib/termnav"

# shellcheck source=../lib/termnav/shell/vscode-command.sh
. "$lib_dir/shell/vscode-command.sh" || exit 1

_usage() {
  cat <<'EOF'
usage: vscode-switch-tab [next|previous]

Ask VS Code (via its pluggable command-execution bridge) to switch the
active editor tab. tmux/Neovim bindings are the common caller, invoked when
there is nothing left to switch locally and the outer terminal is VS Code's
integrated terminal.

Arguments:
  next|previous      Direction to switch. Defaults to next.

Options:
  -h, --help         Show this help.
EOF
}

_die() {
  printf 'vscode-switch-tab: %s\n' "$*" >&2
  exit 2
}

direction="next"

while (($#)); do
  case "$1" in
    next | previous)
      direction="$1"
      shift
      ;;
    -h | --help)
      _usage
      exit 0
      ;;
    -*)
      _die "unknown option: $1"
      ;;
    *)
      _die "direction must be next or previous"
      ;;
  esac
done

command_id="workbench.action.nextEditor"
[[ "$direction" == "previous" ]] && command_id="workbench.action.previousEditor"

termnav_vscode_execute_command "$command_id"
```

Create `~/git/termnav/bin/vscode-move-tab`:

```bash
#!/usr/bin/env bash
# Ask VS Code to move the active editor tab left or right.

set -euo pipefail

_termnav_script_parent() {
  case "$1" in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

_termnav_script_dir() {
  local path="$1" dir target
  while [[ -L "$path" ]]; do
    dir=$(cd -P -- "$(_termnav_script_parent "$path")" && pwd) || return 1
    target=$(readlink "$path") || return 1
    [[ "$target" == /* ]] || target="$dir/$target"
    path="$target"
  done
  cd -P -- "$(_termnav_script_parent "$path")" && pwd
}

script_dir=$(_termnav_script_dir "${BASH_SOURCE[0]}") || {
  echo "vscode-move-tab: cannot resolve executable path" >&2
  exit 2
}
lib_dir="${script_dir%/bin}/lib/termnav"

# shellcheck source=../lib/termnav/shell/vscode-command.sh
. "$lib_dir/shell/vscode-command.sh" || exit 1

_usage() {
  cat <<'EOF'
usage: vscode-move-tab [left|right]

Ask VS Code (via its pluggable command-execution bridge) to move the active
editor tab left or right within its group. tmux/Neovim bindings are the
common caller, invoked when there is nothing left to move locally and the
outer terminal is VS Code's integrated terminal.

Arguments:
  left|right         Direction to move. Defaults to right.

Options:
  -h, --help         Show this help.
EOF
}

_die() {
  printf 'vscode-move-tab: %s\n' "$*" >&2
  exit 2
}

direction="right"

while (($#)); do
  case "$1" in
    left | right)
      direction="$1"
      shift
      ;;
    -h | --help)
      _usage
      exit 0
      ;;
    -*)
      _die "unknown option: $1"
      ;;
    *)
      _die "direction must be left or right"
      ;;
  esac
done

command_id="workbench.action.moveEditorRightInGroup"
[[ "$direction" == "left" ]] && command_id="workbench.action.moveEditorLeftInGroup"

termnav_vscode_execute_command "$command_id"
```

Make both executable:

```bash
chmod +x ~/git/termnav/bin/vscode-switch-tab ~/git/termnav/bin/vscode-move-tab
```

Create `~/git/termnav/man/man1/vscode-switch-tab.1`:

```troff
.TH VSCODE-SWITCH-TAB 1 "2026-07-06" "termnav" "User Commands"
.SH NAME
vscode-switch-tab \- request a VS Code editor tab switch
.SH SYNOPSIS
.B vscode-switch-tab
.RI [ next | previous ]
.SH DESCRIPTION
.B vscode-switch-tab
asks VS Code, through its pluggable command-execution bridge (see
.B TERMNAV_VSCODE_BACKEND
below), to switch the active editor tab. Consumers such as tmux and Neovim
call this when the focused application cannot handle the key itself and
there is nothing left to switch locally.
.PP
Fails silently (non-zero exit, no output) if the bridge is unreachable --
this is expected whenever VS Code is not the terminal you're actually
attached to, or its command-execution extension isn't running.
.SH ARGUMENTS
.TP
.B next
Switch to the next editor tab. This is the default.
.TP
.B previous
Switch to the previous editor tab.
.SH OPTIONS
.TP
.B -h, --help
Show command help.
.SH ENVIRONMENT
.TP
.B TERMNAV_VSCODE_BACKEND
Selects the command-execution backend. Defaults to
.BR mcp .
.TP
.B VSCODE_MCP_PORT
Overrides the MCP backend's target port. Defaults to
.BR 9876 .
.SH EXIT STATUS
.TP
.B 0
The command was executed.
.TP
.B 1
The bridge was unreachable or the command failed.
.TP
.B 2
Usage error.
.SH SEE ALSO
.BR vscode-move-tab (1),
.BR wezterm-switch-tab (1)
```

Create `~/git/termnav/man/man1/vscode-move-tab.1`:

```troff
.TH VSCODE-MOVE-TAB 1 "2026-07-06" "termnav" "User Commands"
.SH NAME
vscode-move-tab \- request a VS Code editor tab move
.SH SYNOPSIS
.B vscode-move-tab
.RI [ left | right ]
.SH DESCRIPTION
.B vscode-move-tab
asks VS Code, through its pluggable command-execution bridge (see
.B TERMNAV_VSCODE_BACKEND
below), to move the active editor tab left or right within its group.
Consumers such as tmux and Neovim call this when the focused application
cannot handle the key itself and there is nothing left to move locally.
.PP
Fails silently (non-zero exit, no output) if the bridge is unreachable --
this is expected whenever VS Code is not the terminal you're actually
attached to, or its command-execution extension isn't running.
.SH ARGUMENTS
.TP
.B left
Move the active editor tab left.
.TP
.B right
Move the active editor tab right. This is the default.
.SH OPTIONS
.TP
.B -h, --help
Show command help.
.SH ENVIRONMENT
.TP
.B TERMNAV_VSCODE_BACKEND
Selects the command-execution backend. Defaults to
.BR mcp .
.TP
.B VSCODE_MCP_PORT
Overrides the MCP backend's target port. Defaults to
.BR 9876 .
.SH EXIT STATUS
.TP
.B 0
The command was executed.
.TP
.B 1
The bridge was unreachable or the command failed.
.TP
.B 2
Usage error.
.SH SEE ALSO
.BR vscode-switch-tab (1),
.BR wezterm-move-tab (1)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/git/termnav/test/suites/vscode-test`
Expected: all assertions pass. Also run the full suite to confirm the new
man pages satisfy `manpage-test`:

```bash
~/git/termnav/test/termnav-test
```

Expected: `termnav-test: ok`

- [ ] **Step 5: Commit**

```bash
cd ~/git/termnav
git add bin/vscode-switch-tab bin/vscode-move-tab \
  man/man1/vscode-switch-tab.1 man/man1/vscode-move-tab.1 \
  test/suites/vscode-test
git commit -m "Add vscode-switch-tab and vscode-move-tab CLI scripts

Public entry points mirroring wezterm-switch-tab/wezterm-move-tab:
translate a direction into a VS Code command ID and call the
dispatch seam. Includes man pages (required by manpage-test)."
```

---

### Task 4: termnav — README documentation

**Files:**

- Modify: `~/git/termnav/README.md`

**Interfaces:**

- Consumes: nothing (documentation only).

- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Update the Public API and Dependencies sections**

In `~/git/termnav/README.md`, after this existing bullet:

```markdown
- `bin/wezterm-move-tab`: request WezTerm tab movement, including parent-tmux
  bubbling for nested local or remote tmux sessions.
```

insert:

```markdown
- `bin/vscode-switch-tab`: request a VS Code editor tab switch through the
  pluggable command-execution bridge.
- `bin/vscode-move-tab`: request a VS Code editor tab move through the
  pluggable command-execution bridge.
```

After this existing bullet:

```markdown
- `lib/termnav/shell/wezterm-vars.sh`: shell helpers for emitting WezTerm
  `SetUserVar` OSC requests with raw or tmux-passthrough framing.
```

insert:

```markdown
- `lib/termnav/shell/vscode-command.sh`: dispatch seam for executing a VS
  Code command by ID through a pluggable backend (`TERMNAV_VSCODE_BACKEND`,
  default `mcp`).
- `lib/termnav/shell/vscode-backend-mcp.sh`: default backend, calling the
  `nabheet.vscode-ide-mcp` extension's local HTTP JSON-RPC API.
```

In the "Dependencies" section, after this existing bullet:

```markdown
- `ssh` for `nvim-ssh-control-open` when remote file links should reuse an
  existing ControlMaster connection.
```

insert:

```markdown
- `curl` for `vscode-switch-tab`/`vscode-move-tab`'s default MCP backend.
- VS Code with the `nabheet.vscode-ide-mcp` extension installed and running,
  for the VS Code tab bridge. The auth token it reads is written by
  dotfiles' `vscode.sh` merge hook to
  `${XDG_STATE_HOME:-$HOME/.local/state}/dot/vscode-mcp-auth-token`; this
  repo only reads that file, never generates or manages the token.
```

- [ ] **Step 2: Verify the doc renders sensibly**

Run: `cat ~/git/termnav/README.md`
Expected: the new bullets read naturally alongside the existing WezTerm ones, no broken Markdown.

- [ ] **Step 3: Commit**

```bash
cd ~/git/termnav
git add README.md
git commit -m "Document the VS Code tab bridge in README

Lists the new bin/ scripts, lib/ modules, and the curl + VS Code
extension dependency alongside the existing WezTerm entries."
```

---

### Task 5: dotfiles — VS Code editor-focus Alt-Shift-bracket keybindings

**Files:**

- Modify: `~/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc`

**Interfaces:**

- Consumes: nothing from other tasks.

- Produces: nothing consumed by other tasks (VS Code-side keybindings are independent of the tmux/nvim/termnav bridge work).

- [ ] **Step 1: Check for a conflicting VS Code default (empirical verification)**

This step requires a reachable VS Code Remote-SSH client machine (`clark2` in
this environment; substitute whichever machine is running VS Code). If it's
asleep/unreachable, skip to Step 2 with the negation omitted as designed, and
re-run this check later as a follow-up before considering the feature fully
verified (see Task 8).

```bash
timeout 8 ssh clark2 "jq -c '.[] | select(.key==\"alt+shift+[\" or .key==\"alt+shift+]\")' '/Users/chris/Library/Application Support/Code/User/keybindings.json'"
```

Expected: only the two existing `terminalFocus` `sendSequence` entries (added
previously) — no unnegated default for `moveEditorLeftInGroup`/
`moveEditorRightInGroup`. If an unnegated default DOES show up, add a
negation entry for it in Step 2, following the exact pattern already used
for `ctrl+tab`'s `-workbench.action.quickOpenPreviousRecentlyUsedEditorInGroup`
a few lines above (negate first with no `when` filter, matching whatever
`when` clause the discovered default actually has).

- [ ] **Step 2: Add the editor-focus move rules**

In `~/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc`,
replace this block:

```jsonc
  // Tab switching. Editors own Ctrl+Tab outside the terminal. Terminal focus
  // sends extended Ctrl+Tab sequences so tmux/nvim can handle their own tab
  // layers; unlike WezTerm, VS Code has no terminal-output bridge here for
  // bubbling back to editor tabs when tmux has one window.
```

with:

```jsonc
  // Tab switching/moving. Editors own these chords outside the terminal.
  // Terminal focus sends the raw sequences so tmux/nvim can handle their own
  // tab layers, including bubbling back to editor tabs when tmux/nvim have
  // nothing left to switch locally (see ~/git/termnav's vscode-switch-tab/
  // vscode-move-tab, wired in from tmux.conf and nvim's keymaps.lua).
```

Then, immediately after this existing block:

```jsonc
  {
    "key": "alt+shift+]",
    "command": "workbench.action.terminal.sendSequence",
    "args": { "text": "}" },
    "when": "terminalFocus"
  },
```

insert:

```jsonc
  {
    "key": "alt+shift+[",
    "command": "workbench.action.moveEditorLeftInGroup",
    "when": "!terminalFocus"
  },
  {
    "key": "alt+shift+]",
    "command": "workbench.action.moveEditorRightInGroup",
    "when": "!terminalFocus"
  },
```

(If Step 1 found a conflicting default, add its negation entries here too,
before the two entries above, matching the `-workbench.action....` pattern
used for `ctrl+tab` earlier in this same file.)

- [ ] **Step 2: Verify the JSONC is well-formed**

Run:

```bash
grep -v '^[[:space:]]*//' ~/.config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc | jq '.' >/dev/null
echo "exit: $?"
```

Expected: `exit: 0`

- [ ] **Step 3: Regenerate and spot-check on a reachable client**

If a VS Code client machine is reachable, run `dot update` there and confirm
the new entries landed:

```bash
ssh clark2 'cd ~ && dot update'
timeout 8 ssh clark2 "jq -c '.[] | select(.key==\"alt+shift+[\" or .key==\"alt+shift+]\")' '/Users/chris/Library/Application Support/Code/User/keybindings.json'"
```

Expected: four entries total for these two keys — the two pre-existing
`terminalFocus` ones plus the two new `!terminalFocus` ones, with no stray
unnegated default (matching the class of bug found and fixed in commit
`fb3e5cb2`). If unreachable, defer this check to Task 8.

- [ ] **Step 4: Commit**

```bash
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add \
  .config/dot/merge-hooks.d/vscode/keybindings/all.d/10-keybindings.jsonc
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -F - <<'EOF'
Add VS Code editor-focus Alt-Shift-bracket tab-move keybindings

Summary
Ctrl-Tab/Ctrl-Shift-Tab already switch editor tabs when the editor
region is focused (VS Code's own MRU commands) and forward to the
shell when the terminal is focused. Alt-Shift-[/Alt-Shift-] only had
the terminal-focus half — no editor-focus counterpart to move editor
tabs, unlike the switch chords. Adds workbench.action.moveEditorLeftInGroup/
moveEditorRightInGroup guarded by !terminalFocus, mirroring the
existing pattern exactly.

Testing
- Verified the JSONC parses (comments stripped, jq .).
- Spot-checked the regenerated keybindings.json on a reachable VS
  Code client for the expected four entries and no stray unnegated
  default, matching the class of bug fixed in fb3e5cb2.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
```

---

### Task 6: dotfiles — tmux.conf VS Code bubble-up branch

**Files:**

- Modify: `~/.config/tmux/tmux.conf`
- Modify: `~/.local/lib/dot/tests/tmux-test`

**Interfaces:**

- Consumes: `vscode-switch-tab [next|previous]`, `vscode-move-tab [left|right]` (Task 3) — installed as PATH-visible symlinks at `~/.local/bin/vscode-switch-tab`/`~/.local/bin/vscode-move-tab` via shdeps, same as `wezterm-switch-tab`/`wezterm-move-tab`.

- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write the failing test**

In `~/.local/lib/dot/tests/tmux-test`, add these variable definitions right
after the existing `wezterm_move_tab_path` line:

```bash
# shellcheck disable=SC2088 # tmux expands this literal path in its own shell.
vscode_switch_tab_path='~/.local/bin/vscode-switch-tab'
# shellcheck disable=SC2088 # tmux expands this literal path in its own shell.
vscode_move_tab_path='~/.local/bin/vscode-move-tab'
```

Then, right after this existing block (which checks the four bind-key
config lines exist):

```bash
ctrl_tab_config_line=$(printf '%s\n' "$tmux_content" | grep '^bind-key -n C-Tab ' || true)
ctrl_shift_tab_config_line=$(printf '%s\n' "$tmux_content" | grep '^bind-key -n C-BTab ' || true)
move_tab_left_config_line=$(printf '%s\n' "$tmux_content" | grep "^bind-key -n 'M-{' " || true)
move_tab_right_config_line=$(printf '%s\n' "$tmux_content" | grep "^bind-key -n 'M-}' " || true)
```

add these new assertions in the "tmux config integration" section (right
after the existing `_assert_contains "tmux Alt-Shift-] asks parent tmux when
nested client has one window" ...` line):

```bash
_assert_contains "tmux Ctrl-Tab checks for a VS Code client before asking WezTerm" \
  "#{m:xterm.js*,#{client_termtype}}" "$ctrl_tab_config_line"
_assert_contains "tmux Ctrl-Shift-Tab checks for a VS Code client before asking WezTerm" \
  "#{m:xterm.js*,#{client_termtype}}" "$ctrl_shift_tab_config_line"
_assert_contains "tmux Alt-Shift-[ checks for a VS Code client before asking WezTerm" \
  "#{m:xterm.js*,#{client_termtype}}" "$move_tab_left_config_line"
_assert_contains "tmux Alt-Shift-] checks for a VS Code client before asking WezTerm" \
  "#{m:xterm.js*,#{client_termtype}}" "$move_tab_right_config_line"
_assert_contains "tmux Ctrl-Tab bubbles to VS Code via the installed helper" \
  "$vscode_switch_tab_path next" "$tmux_content"
_assert_contains "tmux Ctrl-Shift-Tab bubbles to VS Code via the installed helper" \
  "$vscode_switch_tab_path previous" "$tmux_content"
_assert_contains "tmux Alt-Shift-[ bubbles to VS Code via the installed helper" \
  "$vscode_move_tab_path left" "$tmux_content"
_assert_contains "tmux Alt-Shift-] bubbles to VS Code via the installed helper" \
  "$vscode_move_tab_path right" "$tmux_content"
_assert_executable "tmux VS Code tab switch helper is installed" \
  "$tmux_tool_home/.local/bin/vscode-switch-tab"
_assert_executable "tmux VS Code tab move helper is installed" \
  "$tmux_tool_home/.local/bin/vscode-move-tab"
```

Also add the same checks to the "runtime" section (after tmux parses the
config), right after the existing `_assert_contains "tmux runtime Alt-Shift-]
can request parent tmux move" ...` line:

```bash
  _assert_contains "tmux runtime Ctrl-Tab checks for a VS Code client" \
    "#{m:xterm.js*,#{client_termtype}}" "$ctrl_tab_root_line"
  _assert_contains "tmux runtime Ctrl-Shift-Tab checks for a VS Code client" \
    "#{m:xterm.js*,#{client_termtype}}" "$ctrl_shift_tab_root_line"
  _assert_contains "tmux runtime Alt-Shift-[ checks for a VS Code client" \
    "#{m:xterm.js*,#{client_termtype}}" "$move_tab_left_root_line"
  _assert_contains "tmux runtime Alt-Shift-] checks for a VS Code client" \
    "#{m:xterm.js*,#{client_termtype}}" "$move_tab_right_root_line"
  _assert_contains "tmux runtime Ctrl-Tab can bubble to VS Code" \
    "$vscode_switch_tab_path next" "$root_keys"
  _assert_contains "tmux runtime Alt-Shift-[ can bubble to VS Code" \
    "$vscode_move_tab_path left" "$root_keys"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/lib/dot/tests/tmux-test`
Expected: FAIL on all the new assertions — `tmux.conf` doesn't reference
`client_termtype` or the vscode scripts yet.

- [ ] **Step 3: Write the minimal implementation**

In `~/.config/tmux/tmux.conf`, add four new variables right after the
existing `move_parent_tab_right` line:

```tmux
switch_vscode_tab_next="run-shell -b '~/.local/bin/vscode-switch-tab next'"
switch_vscode_tab_previous="run-shell -b '~/.local/bin/vscode-switch-tab previous'"
move_vscode_tab_left="run-shell -b '~/.local/bin/vscode-move-tab left'"
move_vscode_tab_right="run-shell -b '~/.local/bin/vscode-move-tab right'"
```

Update the explanatory comment block above the four bind-key lines. Replace:

```tmux
# Ctrl+Tab mirrors app tab-switching for tmux windows. Prefix+Left/Right above
# stays available for pane-aware navigation. Unbind Alt+Tab so sourcing this
# config clears any older experimental binding from a live tmux server. Forward
# the chord when nvim/fzf owns the foreground pane, or when a nested tmux/screen
# wrapper has mouse reporting on (its own inner content, invisible to ps, wants
# raw input). If this tmux session has one window and is attached inside
# another tmux, ask WezTerm to bounce a private key into the parent tmux layer;
# otherwise ask WezTerm itself.
```

with:

```tmux
# Ctrl+Tab mirrors app tab-switching for tmux windows. Prefix+Left/Right above
# stays available for pane-aware navigation. Unbind Alt+Tab so sourcing this
# config clears any older experimental binding from a live tmux server. Forward
# the chord when nvim/fzf owns the foreground pane, or when a nested tmux/screen
# wrapper has mouse reporting on (its own inner content, invisible to ps, wants
# raw input). If this tmux session has one window, bubble to whichever outer
# terminal actually sent this keypress: #{client_termtype} is evaluated per
# triggering client (not a session-wide env var, which would misroute if the
# same session is attached from both VS Code and WezTerm at once). VS Code's
# integrated terminal reports "xterm.js(...)"; anything else is assumed to be
# WezTerm, forwarded through the existing nested-tmux/parent-bubble logic
# (irrelevant to the VS Code bridge, which is a direct HTTP call, not an
# escape-sequence relay, so it needs no nested/parent distinction).
```

Now update the four bind-key lines themselves. Replace:

```tmux
bind-key -n C-Tab if-shell "$is_terminal_app" "$send_ctrl_tab" { if-shell "$is_nested_wrapper_with_mouse" "$send_ctrl_tab" { if-shell -F '#{>:#{session_windows},1}' 'next-window' { if-shell "$is_nested_tmux_client" "$switch_parent_tab_next" "$switch_wezterm_tab_next" } } }
bind-key -n C-BTab if-shell "$is_terminal_app" "$send_ctrl_shift_tab" { if-shell "$is_nested_wrapper_with_mouse" "$send_ctrl_shift_tab" { if-shell -F '#{>:#{session_windows},1}' 'previous-window' { if-shell "$is_nested_tmux_client" "$switch_parent_tab_previous" "$switch_wezterm_tab_previous" } } }
```

with:

```tmux
bind-key -n C-Tab if-shell "$is_terminal_app" "$send_ctrl_tab" { if-shell "$is_nested_wrapper_with_mouse" "$send_ctrl_tab" { if-shell -F '#{>:#{session_windows},1}' 'next-window' { if-shell -F '#{m:xterm.js*,#{client_termtype}}' "$switch_vscode_tab_next" { if-shell "$is_nested_tmux_client" "$switch_parent_tab_next" "$switch_wezterm_tab_next" } } } }
bind-key -n C-BTab if-shell "$is_terminal_app" "$send_ctrl_shift_tab" { if-shell "$is_nested_wrapper_with_mouse" "$send_ctrl_shift_tab" { if-shell -F '#{>:#{session_windows},1}' 'previous-window' { if-shell -F '#{m:xterm.js*,#{client_termtype}}' "$switch_vscode_tab_previous" { if-shell "$is_nested_tmux_client" "$switch_parent_tab_previous" "$switch_wezterm_tab_previous" } } } }
```

Replace:

```tmux
bind-key -n 'M-{' if-shell "$is_terminal_app" "$send_alt_shift_left_bracket" { if-shell "$is_nested_wrapper_with_mouse" "$send_alt_shift_left_bracket" { if-shell -F '#{==:#{session_windows},1}' { if-shell "$is_nested_tmux_client" "$move_parent_tab_left" "$move_wezterm_tab_left" } { if-shell -F '#{>:#{window_index},#{base-index}}' 'swap-window -d -t :-' 'display-message -p ""' } } }
bind-key -n 'M-}' if-shell "$is_terminal_app" "$send_alt_shift_right_bracket" { if-shell "$is_nested_wrapper_with_mouse" "$send_alt_shift_right_bracket" { if-shell -F '#{==:#{session_windows},1}' { if-shell "$is_nested_tmux_client" "$move_parent_tab_right" "$move_wezterm_tab_right" } { if-shell -F '#{<:#{window_index},#{e|+:#{base-index},#{e|-:#{session_windows},1}}}' 'swap-window -d -t :+' 'display-message -p ""' } } }
```

with:

```tmux
bind-key -n 'M-{' if-shell "$is_terminal_app" "$send_alt_shift_left_bracket" { if-shell "$is_nested_wrapper_with_mouse" "$send_alt_shift_left_bracket" { if-shell -F '#{==:#{session_windows},1}' { if-shell -F '#{m:xterm.js*,#{client_termtype}}' "$move_vscode_tab_left" { if-shell "$is_nested_tmux_client" "$move_parent_tab_left" "$move_wezterm_tab_left" } } { if-shell -F '#{>:#{window_index},#{base-index}}' 'swap-window -d -t :-' 'display-message -p ""' } } }
bind-key -n 'M-}' if-shell "$is_terminal_app" "$send_alt_shift_right_bracket" { if-shell "$is_nested_wrapper_with_mouse" "$send_alt_shift_right_bracket" { if-shell -F '#{==:#{session_windows},1}' { if-shell -F '#{m:xterm.js*,#{client_termtype}}' "$move_vscode_tab_right" { if-shell "$is_nested_tmux_client" "$move_parent_tab_right" "$move_wezterm_tab_right" } } { if-shell -F '#{<:#{window_index},#{e|+:#{base-index},#{e|-:#{session_windows},1}}}' 'swap-window -d -t :+' 'display-message -p ""' } } }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/lib/dot/tests/tmux-test`
Expected: all assertions pass, including the pre-existing ones (they should
be unaffected — the new checks are additive).

- [ ] **Step 5: Manual isolated-server verification (mirrors the mouse-flag bugfix technique)**

```bash
SOCK=vscode-bubble-test
tmux -L $SOCK kill-server 2>/dev/null || true
TERM=xterm-256color tmux -L $SOCK new-session -d -s probe -x 100 -y 30
tmux -L $SOCK source-file ~/.config/tmux/tmux.conf
mkdir -p /tmp/vscode-bubble-mock-bin
cat >/tmp/vscode-bubble-mock-bin/vscode-switch-tab <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>/tmp/vscode-bubble-test.log
EOF
chmod +x /tmp/vscode-bubble-mock-bin/vscode-switch-tab
rm -f /tmp/vscode-bubble-test.log

python3 - <<'PY'
import pty, os, time, signal
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["PATH"] = "/tmp/vscode-bubble-mock-bin:" + os.environ["PATH"]
    os.execvp("tmux", ["tmux", "-L", "vscode-bubble-test", "attach", "-t", "probe"])
else:
    time.sleep(1)
    os.write(fd, b"\x1b[9;5u")
    time.sleep(0.5)
    os.kill(pid, signal.SIGTERM)
    time.sleep(0.2)
PY

cat /tmp/vscode-bubble-test.log
tmux -L vscode-bubble-test kill-server 2>/dev/null
rm -rf /tmp/vscode-bubble-mock-bin /tmp/vscode-bubble-test.log
```

Expected: this test can't actually force tmux's `#{client_termtype}` to
report `xterm.js` (that's negotiated with the real terminal, not something a
raw `pty.fork()` client answers) — so this specific manual check will show
the WezTerm path being taken instead of the mock `vscode-switch-tab`. That's
expected and fine: the config-content assertions in Step 4 already prove the
right condition and script path are wired correctly; a live end-to-end check
of the actual `#{client_termtype}` branch needs a real VS Code client, which
is what Task 8's manual checklist covers.

- [ ] **Step 6: Reload into the live session and commit**

```bash
tmux source-file ~/.config/tmux/tmux.conf
```

```bash
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add .config/tmux/tmux.conf .local/lib/dot/tests/tmux-test
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -F - <<'EOF'
Bubble tmux Ctrl-Tab/Alt-Shift-bracket to VS Code when it's the outer terminal

Summary
The bubble-up bindings (tmux has one window, nothing left to switch
locally) only ever asked WezTerm, via OSC 1337 SetUserVar escapes --
VS Code's terminal doesn't understand that protocol, so bubbling up
inside VS Code was silently a no-op.

Added a branch, checked before the existing WezTerm logic, that asks
whichever outer terminal actually sent this keypress:
#{client_termtype} is evaluated in the context of the triggering
client already (tmux's own per-event format expansion), reporting
"xterm.js(...)" for VS Code's integrated terminal. Deliberately not
using the VSCODE_IPC_HOOK_CLI env var: it's session-wide via
update-environment, so it would misroute to VS Code even when the
keypress came from a WezTerm client attached to the same session.

The VS Code bridge (vscode-switch-tab/vscode-move-tab, from
~/git/termnav) needs no nested/parent distinction the way the WezTerm
path does -- it's a direct loopback HTTP call, not an escape-sequence
relay, so tmux nesting doesn't affect it.

Testing
- ~/.local/lib/dot/tests/tmux-test: new assertions for the
  client_termtype condition and the vscode-switch-tab/vscode-move-tab
  call sites, both in the static config and against a live-parsed
  tmux server. Full suite still passes.
- Manual isolated tmux -L server check confirmed the config wiring;
  a live #{client_termtype}-triggered check needs a real VS Code
  client (deferred to end-to-end verification).
- Reloaded into the live ds session via tmux source-file.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
```

---

### Task 7: dotfiles — nvim keymaps.lua VS Code bubble-up branch

**Files:**

- Modify: `~/.config/nvim/lua/config/keymaps.lua`
- Modify: `~/.local/lib/dot/tests/nvim-test`

**Interfaces:**

- Consumes: `vscode-switch-tab [next|previous]`, `vscode-move-tab [left|right]` (Task 3).

- Produces: nothing consumed by other tasks.

- [ ] **Step 1: Write the failing tests**

In `~/.local/lib/dot/tests/nvim-test`, the four existing mocks that simulate
"nvim buffer count == 1 and tmux window count == 1" (the bubble-up path)
need a `list-clients` case added — the new `outer_terminal_is_vscode()`
check will call it, and if left unhandled the mock falls through silently
(no output), which the Lua code must treat as "not VS Code" so the existing
WezTerm-bubble assertions still hold.

Replace this mock (used by the "Ctrl-Tab bubbles to WezTerm when nvim and
tmux each have one tab/window" test):

```bash
tab_tmux_one_window_mock=$(_tmpdir)
cat >"$tab_tmux_one_window_mock/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_MOCK_LOG"
if [[ "$1" == "display-message" ]]; then
  printf '1\n'
fi
MOCK
chmod +x "$tab_tmux_one_window_mock/tmux"
```

with:

```bash
tab_tmux_one_window_mock=$(_tmpdir)
cat >"$tab_tmux_one_window_mock/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_MOCK_LOG"
case "$1" in
  display-message)
    printf '1\n'
    ;;
  list-clients)
    printf '100 wezterm\n'
    ;;
esac
MOCK
chmod +x "$tab_tmux_one_window_mock/tmux"
```

and update its expected result. Replace:

```bash
expected="$(printf 'DOT_SWITCH_TAB:next\nDOT_SWITCH_TAB:previous\ntmux:display-message -p #{session_windows}|display-message -p #{client_termname}|display-message -p #{session_windows}|display-message -p #{client_termname}')"
_assert_eq "buffer cycling: Ctrl-Tab bubbles to WezTerm when nvim and tmux each have one tab/window" \
  "$expected" "$result"
```

with:

```bash
expected="$(printf 'DOT_SWITCH_TAB:next\nDOT_SWITCH_TAB:previous\ntmux:display-message -p #{session_windows}|list-clients -F #{client_activity} #{client_termtype}|display-message -p #{client_termname}|display-message -p #{session_windows}|list-clients -F #{client_activity} #{client_termtype}|display-message -p #{client_termname}')"
_assert_eq "buffer cycling: Ctrl-Tab bubbles to WezTerm when nvim and tmux each have one tab/window" \
  "$expected" "$result"
```

Apply the identical two changes (mock + expected string) to
`tab_tmux_nested_one_window_mock`, `move_tmux_one_window_mock`, and
`move_tmux_nested_one_window_mock` — same `list-clients) printf '100
wezterm\n' ;;` case added to each mock, same `list-clients -F

## {client_activity} #{client_termtype}|` inserted into each expected string

immediately after the `session_windows`/`window_index...` display-message
call and before the `client_termname` display-message call, for both
directions in each test.

Now add three brand-new tests after the existing
"buffer moving: Alt-Shift-brackets bubble to parent tmux..." test (i.e.,
after the block ending with the `_assert_eq` at line ~632-633 in the current
file):

```bash
vscode_switch_mock=$(_tmpdir)
cat >"$vscode_switch_mock/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_MOCK_LOG"
case "$1" in
  display-message)
    printf '1\n'
    ;;
  list-clients)
    printf '100 xterm.js(6.1.0-beta.285)\n'
    ;;
esac
MOCK
chmod +x "$vscode_switch_mock/tmux"
cat >"$vscode_switch_mock/vscode-switch-tab" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VSCODE_MOCK_LOG"
MOCK
chmod +x "$vscode_switch_mock/vscode-switch-tab"

vscode_switch_log=$(_tmpdir)/vscode-switch.log
result=$(TMUX="/tmp/tmux-test,1,0" TMUX_PANE="%1" \
  TMUX_MOCK_LOG="$vscode_switch_mock/tmux.log" \
  VSCODE_MOCK_LOG="$vscode_switch_log" \
  PATH="$vscode_switch_mock:$PATH" _nvim_lua '
  package.loaded["config.wezterm-vars"] = {
    set = function(name, value)
      print("wezterm:" .. name .. ":" .. value)
    end,
  }
  dofile(vim.fn.expand("~/.config/nvim/lua/config/keymaps.lua"))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.bo[bufnr].buflisted = bufnr == vim.api.nvim_get_current_buf()
  end
  vim.fn.maparg("<C-Tab>", "n", false, true).callback()
  vim.wait(1000, function()
    return vim.fn.filereadable(vim.env.VSCODE_MOCK_LOG) == 1
  end)
  print("vscode:" .. table.concat(vim.fn.readfile(vim.env.VSCODE_MOCK_LOG), "|"))
')
_assert_eq "buffer cycling: Ctrl-Tab bubbles to VS Code (not WezTerm) when the active client is VS Code" \
  "vscode:next" "$result"

vscode_move_mock=$(_tmpdir)
cat >"$vscode_move_mock/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_MOCK_LOG"
case "$1" in
  display-message)
    printf '1 1 1\n'
    ;;
  list-clients)
    printf '100 xterm.js(6.1.0-beta.285)\n'
    ;;
esac
MOCK
chmod +x "$vscode_move_mock/tmux"
cat >"$vscode_move_mock/vscode-move-tab" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$VSCODE_MOCK_LOG"
MOCK
chmod +x "$vscode_move_mock/vscode-move-tab"

vscode_move_log=$(_tmpdir)/vscode-move.log
result=$(TMUX="/tmp/tmux-test,1,0" TMUX_PANE="%1" \
  TMUX_MOCK_LOG="$vscode_move_mock/tmux.log" \
  VSCODE_MOCK_LOG="$vscode_move_log" \
  PATH="$vscode_move_mock:$PATH" _nvim_lua '
  package.loaded["config.wezterm-vars"] = {
    set = function(name, value)
      print("wezterm:" .. name .. ":" .. value)
    end,
  }
  dofile(vim.fn.expand("~/.config/nvim/lua/config/keymaps.lua"))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.bo[bufnr].buflisted = bufnr == vim.api.nvim_get_current_buf()
  end
  vim.fn.maparg("<M-{>", "n", false, true).callback()
  vim.wait(1000, function()
    return vim.fn.filereadable(vim.env.VSCODE_MOCK_LOG) == 1
  end)
  print("vscode:" .. table.concat(vim.fn.readfile(vim.env.VSCODE_MOCK_LOG), "|"))
')
_assert_eq "buffer moving: Alt-Shift-[ bubbles to VS Code (not WezTerm) when the active client is VS Code" \
  "vscode:left" "$result"

vscode_multi_client_mock=$(_tmpdir)
cat >"$vscode_multi_client_mock/tmux" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TMUX_MOCK_LOG"
case "$1" in
  display-message)
    printf '1\n'
    ;;
  list-clients)
    # Two attached clients; the WezTerm one is MORE recently active, so it
    # must win even though a VS Code client is also attached.
    printf '50 xterm.js(6.1.0-beta.285)\n200 wezterm\n'
    ;;
esac
MOCK
chmod +x "$vscode_multi_client_mock/tmux"

result=$(TMUX="/tmp/tmux-test,1,0" TMUX_PANE="%1" \
  TMUX_MOCK_LOG="$vscode_multi_client_mock/tmux.log" \
  PATH="$vscode_multi_client_mock:$PATH" _nvim_lua '
  package.loaded["config.wezterm-vars"] = {
    set = function(name, value)
      print(name .. ":" .. value:match("^[^:]+"))
    end,
  }
  dofile(vim.fn.expand("~/.config/nvim/lua/config/keymaps.lua"))
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    vim.bo[bufnr].buflisted = bufnr == vim.api.nvim_get_current_buf()
  end
  vim.fn.maparg("<C-Tab>", "n", false, true).callback()
')
_assert_eq "buffer cycling: Ctrl-Tab picks the most-recently-active client when both VS Code and WezTerm are attached" \
  "DOT_SWITCH_TAB:next" "$result"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.local/lib/dot/tests/nvim-test`
Expected: the four updated mocks' tests FAIL (expected strings now include
`list-clients` calls the current code never makes), and the three new tests
FAIL (no `outer_terminal_is_vscode` function exists yet, so `vscode-switch-tab`/
`vscode-move-tab` are never invoked and the VS Code mock logs stay empty —
`vim.wait` will time out after 1000ms and the printed result will be
`vscode:` with nothing after it).

- [ ] **Step 3: Write the minimal implementation**

In `~/.config/nvim/lua/config/keymaps.lua`, add the new detection and
request functions right after the existing `tmux_client_is_nested` function
(before `request_wezterm_tab_switch`):

```lua
local function outer_terminal_is_vscode()
  if not vim.env.TMUX then
    return false
  end

  local output = vim.fn.system({
    "tmux",
    "list-clients",
    "-F",
    "#{client_activity} #{client_termtype}",
  })
  if vim.v.shell_error ~= 0 then
    return false
  end

  local best_activity, best_termtype = nil, nil
  for line in vim.gsplit(output, "\n", { trimempty = true }) do
    local activity, termtype = line:match("^(%d+)%s+(.*)$")
    if activity then
      activity = tonumber(activity)
      if not best_activity or activity > best_activity then
        best_activity = activity
        best_termtype = termtype
      end
    end
  end

  return best_termtype ~= nil and best_termtype:match("^xterm%.js") ~= nil
end

local function request_vscode_tab_switch(direction)
  vim.fn.jobstart({ "vscode-switch-tab", direction }, { detach = true })
end

local function request_vscode_tab_move(direction)
  vim.fn.jobstart({ "vscode-move-tab", direction }, { detach = true })
end
```

Then update `smart_tab_switch`. Replace:

```lua
local function smart_tab_switch(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "previous" and "BufferLineCyclePrev" or "BufferLineCycleNext")
    return
  end

  if tmux_window_count() > 1 then
    vim.fn.system({ "tmux", direction == "previous" and "previous-window" or "next-window" })
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_SWITCH_TAB" or "DOT_SWITCH_TAB"
  request_wezterm_tab_switch(var_name, direction)
end
```

with:

```lua
local function smart_tab_switch(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "previous" and "BufferLineCyclePrev" or "BufferLineCycleNext")
    return
  end

  if tmux_window_count() > 1 then
    vim.fn.system({ "tmux", direction == "previous" and "previous-window" or "next-window" })
    return
  end

  if outer_terminal_is_vscode() then
    request_vscode_tab_switch(direction)
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_SWITCH_TAB" or "DOT_SWITCH_TAB"
  request_wezterm_tab_switch(var_name, direction)
end
```

And update `smart_tab_move`. Replace:

```lua
local function smart_tab_move(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "left" and "BufferLineMovePrev" or "BufferLineMoveNext")
    return
  end

  local index, count, base = tmux_window_position()
  if count > 1 then
    local last = base + count - 1
    if direction == "left" and index > base then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":-" })
    elseif direction == "right" and index < last then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":+" })
    end
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_MOVE_TAB" or "DOT_MOVE_TAB"
  request_wezterm_tab_move(var_name, direction)
end
```

with:

```lua
local function smart_tab_move(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "left" and "BufferLineMovePrev" or "BufferLineMoveNext")
    return
  end

  local index, count, base = tmux_window_position()
  if count > 1 then
    local last = base + count - 1
    if direction == "left" and index > base then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":-" })
    elseif direction == "right" and index < last then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":+" })
    end
    return
  end

  if outer_terminal_is_vscode() then
    request_vscode_tab_move(direction)
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_MOVE_TAB" or "DOT_MOVE_TAB"
  request_wezterm_tab_move(var_name, direction)
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.local/lib/dot/tests/nvim-test`
Expected: all assertions pass, including every pre-existing test in the file
(2358+ lines — this is a large shared suite; a regression anywhere in it
means something in this change broke unrelated keymap tests, not just the
tab-switching ones).

- [ ] **Step 5: Commit**

```bash
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add .config/nvim/lua/config/keymaps.lua .local/lib/dot/tests/nvim-test
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -F - <<'EOF'
Bubble nvim Ctrl-Tab/Alt-Shift-bracket to VS Code when it's the active client

Summary
smart_tab_switch/smart_tab_move's bubble-up path (nvim has one buffer,
tmux has one window) only ever asked WezTerm. Added the same
outer-terminal detection tmux.conf just gained: tmux list-clients -F
'#{client_activity} #{client_termtype}', picking the most-recently-
active attached client as a proxy for "whichever window the user is
actually looking at" (nvim has no per-keypress client identity the
way tmux's own key bindings do), and checking whether its termtype
starts with "xterm.js" (VS Code's integrated terminal).

The VS Code bridge call uses vim.fn.jobstart with detach = true, not
vim.fn.system: the existing WezTerm bubble call is synchronous but
instant (just writes an OSC escape), while the VS Code path is a real
HTTP round-trip that could hang on a dead server, and must not freeze
the editor while it does.

Testing
- ~/.local/lib/dot/tests/nvim-test: updated the four existing
  bubble-to-WezTerm mocks/expectations to account for the new
  list-clients call, and added three new cases -- bubbles to VS Code
  for both Ctrl-Tab and Alt-Shift-[, and correctly prefers whichever
  client is most recently active when both VS Code and WezTerm are
  attached to the same session.
- Full nvim-test suite passes (no regressions in unrelated keymap
  tests sharing this file).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
```

---

### Task 8: End-to-end manual verification and fleet deployment

**Files:** none (verification only).

**Interfaces:**

- Consumes: everything from Tasks 1-7.

- Produces: nothing — this is the final acceptance pass.

- [ ] **Step 1: Push both repos**

```bash
cd ~/git/termnav && git push
git --git-dir=$HOME/.dotfiles --work-tree=$HOME push
```

- [ ] **Step 2: Deploy to the VS Code client machine**

```bash
timeout 8 ssh clark2 'echo reachable' 2>&1
```

If unreachable, wait until it's back online before continuing (this task
can't be completed without a live VS Code window to test against).

```bash
ssh clark2 'cd ~ && dot update'
```

- [ ] **Step 3: Confirm the alt-shift-bracket keybindings deployed cleanly**

```bash
timeout 8 ssh clark2 "jq -c '.[] | select(.key==\"alt+shift+[\" or .key==\"alt+shift+]\")' '/Users/chris/Library/Application Support/Code/User/keybindings.json'"
```

Expected: exactly two `terminalFocus` `sendSequence` entries and two
`!terminalFocus` move entries for these keys, no unnegated defaults. If a
default was found and negated back in Task 5, confirm that negation entry is
present too.

- [ ] **Step 4: Manual functional checks in the actual VS Code window**

Perform each of these directly in VS Code, in the same `ds` tmux session
used throughout this work (or a fresh one with 3+ windows for the
non-bubble cases):

1. With the editor focused (not the terminal): `Alt-Shift-[` and
   `Alt-Shift-]` move the active editor tab left/right.
2. With the editor focused: `Ctrl-Tab`/`Ctrl-Shift-Tab` still cycle editor
   tabs (unaffected — confirms no regression from Task 5).
3. With the terminal focused and tmux having 3+ windows: all four chords
   behave as before (switch/move tmux windows) — confirms no regression
   from Tasks 6/7.
4. Reduce tmux to one window (`tmux kill-window` down to one, or attach a
   fresh single-window session). With the terminal focused: `Ctrl-Tab`
   switches the active VS Code editor tab; `Ctrl-Shift-Tab` switches the
   other direction; `Alt-Shift-[`/`Alt-Shift-]` move the active editor tab.
5. Multi-client check: attach the same tmux session from a WezTerm window
   too (`tmux attach -t <session>` from a plain terminal, or WezTerm
   directly if configured for it). With the session reduced to one window,
   trigger the bubble-up chord from the WezTerm-attached client — confirm it
   switches WezTerm's own tab, not VS Code's. Then trigger it from the
   VS Code-attached client — confirm it switches VS Code's tab, not
   WezTerm's.

- [ ] **Step 5: Confirm the MCP handshake behavior empirically**

```bash
ssh clark2 'echo test' # just to confirm reachability before the local check below
```

From `nas` (or wherever the remote extension host actually runs — same host
the tmux session lives on), while VS Code is connected and the MCP server is
up:

```bash
TOKEN=$(cat ~/.local/state/dot/vscode-mcp-auth-token)
curl -s -m 5 -X POST http://127.0.0.1:9876/mcp \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"execute_command","arguments":{"command":"workbench.action.nextEditor"}}}'
```

If this succeeds directly (no error in the response), the initialize-fallback
code path in `vscode-backend-mcp.sh` is dead code for this server version —
note that but leave it in place (defensive, tested, harmless). If it returns
an error requiring initialization, confirm `termnav_vscode_mcp_execute_command`
(Task 2) actually recovers via its fallback by running it directly:

```bash
bash -c "
  . ~/git/termnav/lib/termnav/shell/vscode-command.sh
  . ~/git/termnav/lib/termnav/shell/vscode-backend-mcp.sh
  termnav_vscode_mcp_execute_command workbench.action.nextEditor
  echo \"exit: \$?\"
"
```

Expected: `exit: 0`, and the active VS Code editor tab visibly switches.

- [ ] **Step 6: Deploy to the rest of the fleet**

```bash
ssh nas 'dot update' # or --cron, matching this host's normal invocation
ssh taylor 'dot update'
ssh metro 'dot update'
ssh bevo2 'dot update'
```

(These hosts don't run VS Code, so this just confirms the tmux.conf/nvim
changes and the termnav dependency bump apply cleanly everywhere, not only
on `clark2`.)

- [ ] **Step 7: Update the design spec's Open Items**

In `.local/share/doc/dot/superpowers/specs/2026-07-06-vscode-tab-consistency-design.md`,
replace the "Open items for the implementation plan" section's three bullets
with their resolved answers (whether a default existed for the bracket keys,
whether the initialize handshake was actually required, and WezTerm's
confirmed `client_termtype` value from Step 4's multi-client check, if
observed directly rather than only via the assumed-fallback design).

```bash
git --git-dir=$HOME/.dotfiles --work-tree=$HOME add \
  .local/share/doc/dot/superpowers/specs/2026-07-06-vscode-tab-consistency-design.md
git --git-dir=$HOME/.dotfiles --work-tree=$HOME commit -m "Resolve open items in the VS Code tab-consistency design spec

Records the empirical answers found during end-to-end verification:
whether VS Code had a default binding on the bracket chords, whether
the MCP server required the initialize handshake, and WezTerm's
confirmed client_termtype value."
```

---

### Self-Review Notes

- **Spec coverage:** Task 1-2 cover the swap seam and MCP backend (spec
  Components #2, Error handling). Task 3 covers the CLI scripts (spec
  Components #2) plus the man-page/README conventions the spec didn't call
  out explicitly but the repo requires. Task 4 covers documentation. Task 5
  covers the editor-focus gap (spec Components #1). Tasks 6-7 cover the
  bubble-up bridge wiring and the multi-client routing fix (spec Components
  #3-4, Data flow, the "same session in both apps" refinement). Task 8
  covers the spec's Testing section's manual/live checklist and the three
  Open Items.
- **Placeholder scan:** no TBD/TODO; the one deliberately-deferred check
  (Task 5 Step 1's default-keybinding lookup) ships with concrete fallback
  code for both outcomes, not a placeholder.
- **Type consistency:** `termnav_vscode_execute_command`, `TERMNAV_VSCODE_BACKEND`,
  `termnav_vscode_mcp_execute_command`, `outer_terminal_is_vscode`,
  `request_vscode_tab_switch`/`request_vscode_tab_move` are named identically
  everywhere they're defined and called across Tasks 1-3 and 6-7.
