# shellcheck shell=bash
# Bash prompt: git branch/status/upstream, command timing, PS1 with exit code.

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

  local status flags=""
  status="$("${g[@]}" --no-optional-locks status --porcelain 2>/dev/null)"
  # Staged changes
  [[ "$status" == *$'\n'[MADRC]* || "$status" == [MADRC]* ]] && flags+="+"
  # Unstaged changes
  [[ "$status" == *$'\n'?[MDRC]* || "$status" == ?[MDRC]* ]] && flags+="*"
  # Untracked files
  [[ "$status" == *"??"* ]] && flags+="%"
  [[ -n "$flags" ]] && flags=" $flags"

  # Ahead/behind upstream (↑ ahead, ↓ behind)
  if "${g[@]}" rev-parse --abbrev-ref '@{upstream}' &>/dev/null; then
    local counts behind ahead
    counts="$("${g[@]}" rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null)" || true
    read -r behind ahead <<< "$counts"
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

  printf ' (%s%s%s)' "$branch" "$op" "$flags"
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
  (( elapsed >= 2 )) && __cmd_time=" ${elapsed}s" || __cmd_time=""
}
preexec_functions+=(__prompt_preexec)
precmd_functions+=(__prompt_precmd)

# DEBUG trap: sets __cmd_start at the first command after each prompt.
# Guarded by __prompt_started so it fires only once per prompt cycle.
# bash-preexec replaces this trap when it loads.
__prompt_started=1
trap '[[ -z ${COMP_LINE:-} ]] && (( __prompt_started )) && { __cmd_start=$SECONDS; __prompt_started=0; }' DEBUG

# Set PS1 with exit status, user@host:path, git info, timing, and a second line.
# Shows red x on non-zero exit code, green o on success.
# Args: $1 - hostname to display (default: \h, the system hostname).
set_prompt() {
  local host="${1:-\\h}"
  # Capture exit code first. bash-preexec preserves $? across its own
  # PROMPT_COMMAND work, so this is correct in both cases.
  # __prompt_precmd: called here when bash-preexec is absent (__bp_imported
  # unset); when bash-preexec is present it already ran via precmd_functions.
  # shellcheck disable=SC2154  # __bp_imported is set by bash-preexec when it loads
  PROMPT_COMMAND='__cmd_exit=$?; [[ -z ${__bp_imported:-} ]] && { __prompt_precmd; __prompt_started=1; }'
  # shellcheck disable=SC2016  # PS1 intentionally contains literal command substitutions
  local exit_sym='\[\033[01;$(( __cmd_exit ? 31 : 32 ))m\]$( (( __cmd_exit )) && echo "x" || echo "o")\[\033[00m\]'
  PS1="${exit_sym} "'\[\033[01;32m\]\u@'"$host"'\[\033[00m\]:\[\033[01;34m\]\w\[\033[33m\]$(__git_prompt)\[\033[00m\]${__cmd_time}\n\$ '
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
