# shellcheck shell=bash
# dot doctor: Agent Hooks checks.

_dr_run_agent_hook() {
  local hook="$1" payload="$2"
  local tmp out_file err_file rc=0
  tmp=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-agent-hook) || return 1
  out_file="$tmp/out"
  err_file="$tmp/err"

  (
    cd "$HOME" || exit 1
    printf '%s' "$payload" |
      AGENTGUARD_NAME=agent \
        AGENTGUARD_SESSION_ID="dot-doctor-$$" \
        AGENTGUARD_HIVE_MEMORY_HOOKS=0 \
        AGENTGUARD_PROCESS_DETECT=0 \
        AGENTGUARD_SLEY_GATE=0 \
        TMPDIR="$tmp" \
        _SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS='' \
        BASH_ENV="$HOME/.config/shell/env-noninteractive.sh" \
        "$hook" >"$out_file" 2>"$err_file"
  ) || rc=$?

  _DR_AGENT_HOOK_STDOUT=$(cat "$out_file" 2>/dev/null || true)
  _DR_AGENT_HOOK_STDERR=$(cat "$err_file" 2>/dev/null || true)
  rm -f "$out_file" "$err_file"
  rmdir "$tmp" 2>/dev/null || true
  return "$rc"
}
_dr_check_agent_hooks() {
  _dr_section "Agent hooks"

  local pre_bash="$HOME/.local/bin/agent-hook-pre-bash"
  local stop_hook="$HOME/.local/bin/agent-hook-stop"

  if [[ ! -x "$pre_bash" ]]; then
    _dr_warn "agent pre-bash hook unavailable" "$(_dr_tilde "$pre_bash")"
    return 0
  fi

  if _dr_run_agent_hook "$pre_bash" '{"tool_input":{"command":"dot status"}}'; then
    _dr_ok "agent pre-bash allows dot status"
  else
    _dr_fail "agent pre-bash failed dot status smoke" \
      "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
  fi

  local raw_git_rc=0
  _dr_run_agent_hook "$pre_bash" '{"tool_input":{"command":"git status -uall"}}' || raw_git_rc=$?
  if [[ "$raw_git_rc" -eq 0 ]]; then
    if _dr_is_dotfiles_checkout; then
      _dr_ok "agent pre-bash allows raw git status in checkout"
    else
      _dr_fail "agent pre-bash allows raw dotfiles git status" \
        "expected the hook to steer agents to 'dot status'"
    fi
  elif [[ "$raw_git_rc" -eq 2 && "$_DR_AGENT_HOOK_STDERR" == *"dot status"* ]]; then
    _dr_ok "agent pre-bash guards raw dotfiles git status"
  else
    _dr_fail "agent pre-bash raw git smoke returned unexpected result" \
      "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
  fi

  if [[ -x "$stop_hook" ]]; then
    if _dr_run_agent_hook "$stop_hook" '{}'; then
      _dr_ok "agent stop hook runs"
    else
      _dr_fail "agent stop hook failed" "${_DR_AGENT_HOOK_STDERR%%$'\n'*}"
    fi
  else
    _dr_warn "agent stop hook unavailable" "$(_dr_tilde "$stop_hook")"
  fi
}
