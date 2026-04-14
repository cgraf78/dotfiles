# shellcheck shell=bash
# Bash prompt: git branch/status/upstream, command timing, PS1 with exit code.

# Color constants for __git_prompt output embedded in PS1 via $().
# \001/\002 (ASCII SOH/STX) mark non-printing sequences so readline
# correctly calculates visible line length.
_PC_RESET=$'\001\033[0m\002'
_PC_CYAN=$'\001\033[36m\002'
_PC_BOLD_RED=$'\001\033[1;31m\002'
_PC_YELLOW=$'\001\033[33m\002'
_PC_GREEN=$'\001\033[32m\002'
_PC_RED=$'\001\033[31m\002'

# Print colored git prompt: branch (cyan), op state (bold red), dirty (yellow),
# ahead (green), behind (red). Falls back to ~/.dotfiles when not in a repo.
# Uses porcelain=v2 to get branch, dirty, and ahead/behind in a single git call.
__git_prompt() {
  local -a g=(git)
  local gitdir
  gitdir="$(git rev-parse --git-dir 2>/dev/null)"
  if [[ -z "$gitdir" ]]; then
    [[ "$PWD" == "$HOME" && -d "$HOME/.dotfiles" ]] || return
    g=(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
    gitdir="$HOME/.dotfiles"
  else
    # git may return a relative path (e.g. ".git"); make it absolute
    [[ "$gitdir" != /* ]] && gitdir="$PWD/$gitdir"
  fi

  # Single git call: branch, upstream, ahead/behind, and dirty state.
  local git_status branch="" ahead=0 behind=0 dirty="" line
  git_status="$("${g[@]}" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)" || return
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*)  branch="${line#\# branch.head }" ;;
      "# branch.ab "*)    read -r _ _ ahead behind <<< "$line"
                          ahead="${ahead#+}"; behind="${behind#-}" ;;
      "1 "*.*)            # changed entry: index/worktree status at chars 2-3
                          [[ "${line:2:1}" != "." ]] && dirty+="+"
                          [[ "${line:3:1}" != "." ]] && dirty+="*" ;;
      "2 "*.*)            [[ "${line:2:1}" != "." ]] && dirty+="+"
                          [[ "${line:3:1}" != "." ]] && dirty+="*" ;;
      "u "*)              dirty+="+" ;;
      "? "*)              dirty+="%" ;;
    esac
  done <<< "$git_status"
  [[ -z "$branch" ]] && return
  # Detached HEAD: porcelain v2 reports "(detached)", show short sha instead.
  [[ "$branch" == "(detached)" ]] && branch="$("${g[@]}" rev-parse --short HEAD 2>/dev/null)"
  # Deduplicate dirty markers (multiple changed files may append duplicates).
  local d=""
  [[ "$dirty" == *"+"* ]] && d+="+"
  [[ "$dirty" == *"*"* ]] && d+="*"
  [[ "$dirty" == *"%"* ]] && d+="%"
  dirty="$d"

  # In-progress operation state (file tests, no subprocess).
  local op=""
  if [[ -f "$gitdir/MERGE_HEAD" ]]; then op="|MERGE"
  elif [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]]; then op="|REBASE"
  elif [[ -f "$gitdir/CHERRY_PICK_HEAD" ]]; then op="|PICK"
  elif [[ -f "$gitdir/REVERT_HEAD" ]]; then op="|REVERT"
  fi

  # Build output: each segment colored independently, parens in default color.
  local out=" (${_PC_CYAN}${branch}${_PC_RESET}"
  [[ -n "$op"    ]] && out+="${_PC_BOLD_RED}${op}${_PC_RESET}"
  [[ -n "$dirty" ]] && out+=" ${_PC_YELLOW}${dirty}${_PC_RESET}"
  (( ${ahead:-0}  > 0 )) && out+=" ${_PC_GREEN}↑${ahead}${_PC_RESET}"
  (( ${behind:-0} > 0 )) && out+=" ${_PC_RED}↓${behind}${_PC_RESET}"
  out+=")"
  printf '%s' "$out"
}

# Command timing.
# Registers with preexec_functions/precmd_functions so bash-preexec (loaded
# later in 70-integrations.bash) picks them up. A DEBUG trap covers the
# fallback for systems without bash-preexec; bash-preexec replaces the DEBUG
# trap on load, so there is no double-counting.
__cmd_time=""
__prompt_preexec() { __cmd_start=$SECONDS; }
__prompt_precmd() {
  local elapsed=$(( SECONDS - ${__cmd_start:-$SECONDS} ))
  __cmd_start=$SECONDS
  if (( elapsed >= 2 )); then
    # Pre-color with dim + \001/\002 wrappers so readline counts correctly.
    __cmd_time=$'\001\033[2m\002 '"${elapsed}s"$'\001\033[0m\002'
  else
    __cmd_time=""
  fi
}
preexec_functions+=(__prompt_preexec)
precmd_functions+=(__prompt_precmd)

# DEBUG trap: sets __cmd_start at the first command after each prompt.
# Guarded by __prompt_started so it fires only once per prompt cycle.
# bash-preexec replaces this trap when it loads.
__prompt_started=1
trap '[[ -z ${COMP_LINE:-} ]] && (( __prompt_started )) && { __cmd_start=$SECONDS; __prompt_started=0; }' DEBUG

# Set PS1 with exit status, user@host:path, git info, timing, and a second line.
# Line 1: dim user@host, bold-cyan path, colored git info, dim timing.
# Line 2: exit-colored $ (green on success, red on failure).
# Args: $1 - hostname to display (default: \h, the system hostname).
set_prompt() {
  local host="${1:-\\h}"
  # Capture exit code via PROMPT_COMMAND. __prompt_precmd runs here when
  # bash-preexec is absent; when present it already ran via precmd_functions.
  # Only set once — re-calls (e.g., set_hostname_alias in 99-local.sh) would
  # clobber hooks appended by 70-integrations.bash (direnv, zoxide, etc.).
  # shellcheck disable=SC2154  # __bp_imported is set by bash-preexec when it loads
  if [[ -z "${__prompt_cmd_set:-}" ]]; then
    PROMPT_COMMAND='__cmd_exit=$?; [[ -z ${__bp_imported:-} ]] && { __prompt_precmd; __prompt_started=1; }'
    __prompt_cmd_set=1
  fi
  # Exit code: bold red [N] only on failure; nothing on success.
  # \001/\002 wrappers inside the printf format let readline exclude the
  # escape sequences from visible line-length calculation.
  # shellcheck disable=SC2016  # PS1 intentionally contains literal command substitutions
  local exit_code='$( (( __cmd_exit )) && printf '"'"'\001\033[1;31m\002[%s]\001\033[0m\002 '"'"' "$__cmd_exit")'
  PS1="${exit_code}"'\[\033[2m\]\u@'"$host"'\[\033[0m\]:\[\033[1;36m\]\w\[\033[0m\]$(__git_prompt)${__cmd_time}\n\[\033[01;$(( __cmd_exit ? 31 : 32 ))m\]\$\[\033[0m\] '
  case "$TERM" in
  xterm* | rxvt*)
    PS1="\[\e]0;\u@$host: \w\a\]$PS1"
    ;;
  esac
}

# Set a hostname alias for the prompt and tmux pane borders.
# Args: $1 - alias to display (e.g., "dev1").
#        Call from ~/.bashrc_local to override the default hostname.
set_hostname_alias() {
  # shellcheck disable=SC2034  # used by interactive sessions and tmux integrations
  HOSTNAME_ALIAS="$1"
  set_prompt "$1"
  [ -n "$TMUX" ] && tmux set -g @hostname_alias "$1" 2>/dev/null
}

set_prompt
