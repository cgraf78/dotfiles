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

  local branch
  branch="$("${g[@]}" symbolic-ref --short HEAD 2>/dev/null \
    || "${g[@]}" rev-parse --short HEAD 2>/dev/null)" || return

  local git_status dirty=""
  git_status="$("${g[@]}" --no-optional-locks status --porcelain 2>/dev/null)"
  # Staged changes
  [[ "$git_status" == *$'\n'[MADRC]* || "$git_status" == [MADRC]* ]] && dirty+="+"
  # Unstaged changes
  [[ "$git_status" == *$'\n'?[MDRC]* || "$git_status" == ?[MDRC]* ]] && dirty+="*"
  # Untracked files
  [[ "$git_status" == *"??"* ]] && dirty+="%"

  # Ahead/behind upstream
  local behind=0 ahead=0
  if "${g[@]}" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    local counts
    counts="$("${g[@]}" rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null)" || true
    behind="${counts%%$'\t'*}"
    ahead="${counts##*$'\t'}"
  fi

  # In-progress operation state
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
  # %(?.true.false) — zsh ternary on last exit status
  # Line 2 colors %# (% for users, # for root) to match the o/x indicator.
  PROMPT="%(?.%B%F{green}o%f%b.%B%F{red}x%f%b) ${dim}%n@${host}${nodim}:%B%F{cyan}%~%f%b"'$(__git_prompt)${__cmd_time}'$'\n''%(?.%B%F{green}.%B%F{red})%#%f%b '
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
