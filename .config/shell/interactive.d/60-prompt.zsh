# Zsh prompt: git branch/status/upstream, command timing, PROMPT with exit code.

# Color constants for __git_prompt output embedded in PROMPT via $().
# \001/\002 (ASCII SOH/STX) mark non-printing sequences so ZLE correctly
# calculates visible line length.
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
                          [[ "${line[3]}" != "." ]] && dirty+="+"
                          [[ "${line[4]}" != "." ]] && dirty+="*" ;;
      "2 "*.*)            [[ "${line[3]}" != "." ]] && dirty+="+"
                          [[ "${line[4]}" != "." ]] && dirty+="*" ;;
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
  print -rn -- "$out"
}

# Command timing via zsh preexec/precmd hooks.
# add-zsh-hook is also loaded in 70-integrations.zsh; autoloading twice is harmless.
__cmd_time=""
__prompt_preexec() { __cmd_start=$EPOCHSECONDS }
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
  PROMPT="%(?.%b%f.%B%F{red}[%?]%f%b )${dim}%n@${host}${nodim}:%B%F{cyan}%~%f%b"'$(__git_prompt)${__cmd_time}'$'\n''%(?.%B%F{green}.%B%F{red})%#%f%b '
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
