# Zsh prompt: async git info, command timing, PROMPT with exit code.
# __git_prompt and color constants are defined in 59-prompt.sh (shared).

# ---------------------------------------------------------------------------
# Async git prompt: computes git info in background, updates prompt via
# zle reset-prompt when ready.  Shows stale result instantly, refreshes
# ~60ms later (imperceptible).
# ---------------------------------------------------------------------------

__git_prompt_result=""
__git_prompt_fd=""
__git_prompt_pwd=""

# Cancel any pending async git prompt computation.
__git_prompt_async_cancel() {
  if [[ -n "$__git_prompt_fd" ]]; then
    zle -F "$__git_prompt_fd" 2>/dev/null
    exec {__git_prompt_fd}<&- 2>/dev/null
    __git_prompt_fd=""
  fi
}

# Start async git prompt computation.  Called from precmd.
# Skips the fork if no command was run and directory hasn't changed,
# since git state can't have changed without user action.
__git_prompt_cmd_ran=""
__git_prompt_async_start() {
  if [[ -z "$__git_prompt_cmd_ran" && "${__git_prompt_pwd}" == "$PWD" ]]; then
    return
  fi
  __git_prompt_cmd_ran=""
  __git_prompt_async_cancel
  if [[ "${__git_prompt_pwd}" != "$PWD" ]]; then
    __git_prompt_result=""
    __git_prompt_pwd="$PWD"
  fi
  exec {__git_prompt_fd}< <(__git_prompt)
  zle -F "$__git_prompt_fd" __git_prompt_async_callback
}

# Callback when background git prompt result is ready.
__git_prompt_async_callback() {
  local fd=$1
  zle -F "$fd"
  IFS= read -r -d '' -u "$fd" __git_prompt_result 2>/dev/null
  exec {fd}<&-
  __git_prompt_fd=""
  zle && zle reset-prompt
}

# Command timing via zsh preexec/precmd hooks.
__cmd_time=""
__prompt_preexec() { __cmd_start=$EPOCHSECONDS; __git_prompt_cmd_ran=1 }
__prompt_precmd() {
  local elapsed=$(( EPOCHSECONDS - ${__cmd_start:-$EPOCHSECONDS} ))
  __cmd_start=$EPOCHSECONDS
  if (( elapsed >= 2 )); then
    # Pre-color with dim + \001/\002 wrappers so ZLE counts correctly.
    __cmd_time=$'\001\033[2m\002 '"${elapsed}s"$'\001\033[0m\002'
  else
    __cmd_time=""
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec __prompt_preexec
add-zsh-hook precmd __prompt_precmd
add-zsh-hook precmd __git_prompt_async_start

# Set PROMPT with exit status, user@host:path, git info, timing, and a second line.
# Line 1: dim user@host, bold-cyan path, colored git info, dim timing.
# Line 2: exit-colored % (green on success, red on failure).
# Args: $1 - hostname to display (default: %m, the system hostname).
set_prompt() {
  local host="${1:-%m}"
  setopt PROMPT_SUBST
  # dim/nodim: raw ANSI wrapped in %{...%} so ZLE treats them as zero-width.
  # $'...' expands \033 to an actual ESC character at assignment time.
  local dim=$'%{\033[2m%}' nodim=$'%{\033[0m%}'
  # %(?.true.false) — zsh ternary on last exit status.
  # Exit code: bold red [N] only on failure; nothing on success.
  # Line 2 colors %# (% for users, # for root) green/red to match.
  PROMPT="%(?.%b%f.%B%F{red}[%?]%f%b )${dim}%n@${host}${nodim}:%B%F{cyan}%~%f%b"'${__git_prompt_result}${__cmd_time}'$'\n''%(?.%B%F{green}.%B%F{red})%#%f%b '
  # Set terminal title for xterm/rxvt
  case "$TERM" in
  xterm* | rxvt*)
    PROMPT=$'%{\e]0;%n@'"${host}"$': %~\a%}'"$PROMPT"
    ;;
  esac
}

# Set a hostname alias for the prompt and tmux pane borders.
# Args: $1 - alias to display (e.g., "dev1").
#        Call from ~/.zshrc_local to override the default hostname.
set_hostname_alias() {
  HOSTNAME_ALIAS="$1"
  set_prompt "$1"
  [ -n "$TMUX" ] && tmux set -g @hostname_alias "$1" 2>/dev/null
}

set_prompt
