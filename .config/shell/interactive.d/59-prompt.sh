# shellcheck shell=bash
# Shared git prompt: branch/status/upstream coloring.
# Numbered 59 so it loads before 60-prompt.bash/.zsh, which depend
# on __git_prompt and the _PC_* color constants defined here.

# Color constants for __git_prompt output.
# \001/\002 (ASCII SOH/STX) mark non-printing sequences so readline/ZLE
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
      "# branch.head "*) branch="${line#\# branch.head }" ;;
      "# branch.ab "*)
        read -r _ _ ahead behind <<<"$line"
        ahead="${ahead#+}"
        behind="${behind#-}"
        ;;
      "1 "*.*) # changed entry: index/worktree status at chars 2-3
        [[ "${line:2:1}" != "." ]] && dirty+="+"
        [[ "${line:3:1}" != "." ]] && dirty+="*"
        ;;
      "2 "*.*)
        [[ "${line:2:1}" != "." ]] && dirty+="+"
        [[ "${line:3:1}" != "." ]] && dirty+="*"
        ;;
      "u "*) dirty+="+" ;;
      "? "*) dirty+="%" ;;
    esac
  done <<<"$git_status"
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
  if [[ -f "$gitdir/MERGE_HEAD" ]]; then
    op="|MERGE"
  elif [[ -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]]; then
    op="|REBASE"
  elif [[ -f "$gitdir/CHERRY_PICK_HEAD" ]]; then
    op="|PICK"
  elif [[ -f "$gitdir/REVERT_HEAD" ]]; then
    op="|REVERT"
  fi

  # Build output: each segment colored independently, parens in default color.
  local out=" (${_PC_CYAN}${branch}${_PC_RESET}"
  [[ -n "$op" ]] && out+="${_PC_BOLD_RED}${op}${_PC_RESET}"
  [[ -n "$dirty" ]] && out+=" ${_PC_YELLOW}${dirty}${_PC_RESET}"
  ((${ahead:-0} > 0)) && out+=" ${_PC_GREEN}↑${ahead}${_PC_RESET}"
  ((${behind:-0} > 0)) && out+=" ${_PC_RED}↓${behind}${_PC_RESET}"
  out+=")"
  printf '%s' "$out"
}
