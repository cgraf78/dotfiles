# Zsh prompt: git branch/status/upstream, command timing, PROMPT with exit code.

# Print git branch, dirty/staged indicators, ahead/behind counts, and
# current operation state for the working directory.
# Falls back to the bare dotfiles repo (~/.dotfiles) when not in a regular repo.
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

  local git_status flags=""
  git_status="$("${g[@]}" --no-optional-locks status --porcelain 2>/dev/null)"
  # Staged changes
  [[ "$git_status" == *$'\n'[MADRC]* || "$git_status" == [MADRC]* ]] && flags+="+"
  # Unstaged changes
  [[ "$git_status" == *$'\n'?[MDRC]* || "$git_status" == ?[MDRC]* ]] && flags+="*"
  # Untracked files
  [[ "$git_status" == *"??"* ]] && flags+="%"
  [[ -n "$flags" ]] && flags=" $flags"

  # Ahead/behind upstream (↑ ahead, ↓ behind)
  if "${g[@]}" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    local counts behind ahead
    counts="$("${g[@]}" rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null)" || true
    behind="${counts%%$'\t'*}"
    ahead="${counts##*$'\t'}"
    (( ${ahead:-0} > 0 )) && flags+=" ↑$ahead"
    (( ${behind:-0} > 0 )) && flags+=" ↓$behind"
  fi

  # In-progress operation state
  local op=""
  if [[ -f "$gitdir/MERGE_HEAD" ]]; then op="|MERGE"
  elif [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]]; then op="|REBASE"
  elif [[ -f "$gitdir/CHERRY_PICK_HEAD" ]]; then op="|PICK"
  elif [[ -f "$gitdir/REVERT_HEAD" ]]; then op="|REVERT"
  fi

  print -n " ($branch$op$flags)"
}

# Command timing via zsh preexec/precmd hooks.
# add-zsh-hook is also loaded in 70-integrations.zsh; autoloading twice is harmless.
__cmd_time=""
__prompt_preexec() { __cmd_start=$EPOCHSECONDS }
__prompt_precmd() {
  local elapsed=$(( EPOCHSECONDS - ${__cmd_start:-$EPOCHSECONDS} ))
  (( elapsed >= 2 )) && __cmd_time=" ${elapsed}s" || __cmd_time=""
}
autoload -Uz add-zsh-hook
add-zsh-hook preexec __prompt_preexec
add-zsh-hook precmd __prompt_precmd

# Set PROMPT with exit status, user@host:path, git info, timing, and a second line.
# Shows red x on non-zero exit code, green o on success.
# Args: $1 - hostname to display (default: %m, the system hostname).
set_prompt() {
  local host="${1:-%m}"
  setopt PROMPT_SUBST
  # %(?.true.false) — zsh ternary on last exit status
  PROMPT='%(?.%B%F{green}o%f%b.%B%F{red}x%f%b) %B%F{green}%n@'"$host"'%f%b:%B%F{blue}%~%f%b%F{yellow}$(__git_prompt)%f%b${__cmd_time}'$'\n''%# '
  # Set terminal title for xterm/rxvt
  case "$TERM" in
  xterm* | rxvt*)
    PROMPT=$'%{\e]0;%n@'"$host"$': %~\a%}'"$PROMPT"
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
