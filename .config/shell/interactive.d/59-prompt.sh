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

_dot_git_prompt_is_ceiling() {
  local candidate="$1" ceiling
  local IFS=:
  for ceiling in ${GIT_CEILING_DIRECTORIES:-}; do
    while [[ "$ceiling" != "/" && "$ceiling" == */ ]]; do
      ceiling="${ceiling%/}"
    done
    [[ "$candidate" != "$ceiling" ]] || return 0
  done
  return 1
}

_dot_git_prompt_gitdir() {
  local dir gitdir line

  if [[ -n "${GIT_DIR:-}" ]]; then
    gitdir="$GIT_DIR"
    [[ "$gitdir" == /* ]] || gitdir="$PWD/$gitdir"
    printf '%s\n' "$gitdir"
    return 0
  fi

  # A common-dir override can decouple operation state from the local marker.
  # Leave that uncommon layout to the authoritative rev-parse fallback.
  [[ -z "${GIT_COMMON_DIR:-}" ]] || return 1

  dir="$PWD"
  while :; do
    # Git resolves discovery physically. A logical path containing a symlink
    # needs authoritative discovery so status and operation state cannot come
    # from different repositories. The ordinary path remains builtin-only.
    [[ ! -L "$dir" ]] || return 1
    if [[ -d "$dir/.git" ]]; then
      printf '%s\n' "$dir/.git"
      return 0
    fi
    if [[ -f "$dir/.git" ]]; then
      line=""
      IFS= read -r line <"$dir/.git" || [[ -n "$line" ]] || return 1
      line="${line%$'\r'}"
      case "$line" in
        "gitdir: "*) gitdir="${line#gitdir: }" ;;
        *) return 1 ;;
      esac
      [[ "$gitdir" == /* ]] || gitdir="$dir/$gitdir"
      [[ -d "$gitdir" ]] || return 1
      printf '%s\n' "$gitdir"
      return 0
    fi
    [[ "$dir" != "/" ]] || return 1
    local parent="${dir%/*}"
    [[ -n "$parent" ]] || parent="/"
    # Git inspects the starting directory but never ascends into a configured
    # ceiling directory. Check the prospective parent to preserve that rule.
    _dot_git_prompt_is_ceiling "$parent" && return 1
    dir="$parent"
  done
}

# Print colored git prompt: branch (cyan), op state (bold red), dirty (yellow),
# ahead (green), behind (red). Falls back to ~/.dotfiles when not in a repo.
# Uses porcelain=v2 to get branch, dirty, and ahead/behind in a single git call.
__git_prompt() {
  local -a g=(git)
  local gitdir="" git_status
  if [[ "$PWD" == "$HOME" && -d "$HOME/.dotfiles" ]]; then
    # The home prompt intentionally shows the base dotfiles repo. Probe it
    # directly so the prompt does not pay for the PATH-visible git launcher and
    # a separate rev-parse before the status call.
    g=(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
    gitdir="$HOME/.dotfiles"
  else
    gitdir=$(_dot_git_prompt_gitdir 2>/dev/null) || gitdir=""
    if [[ -z "$gitdir" && -d "$HOME/.dotfiles" ]]; then
      case "$PWD" in
        "$HOME"/*) gitdir="$(git rev-parse --git-dir 2>/dev/null)" ;;
      esac
    fi
    if [[ -n "$gitdir" ]]; then
      [[ "$gitdir" != /* ]] && gitdir="$PWD/$gitdir"
      if [[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" &&
        -d "$HOME/.dotfiles" && "$gitdir" -ef "$HOME/.dotfiles" ]]; then
        g=(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
      fi
    fi
  fi

  # Branch, upstream, ahead/behind, and dirty state come from one authoritative
  # Git call. Common repositories expose their gitdir through a local marker,
  # avoiding a second launcher call solely for operation-state file tests.
  git_status="$("${g[@]}" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)" || return
  if [[ -z "$gitdir" ]]; then
    gitdir="$("${g[@]}" rev-parse --git-dir 2>/dev/null)"
    [[ -n "$gitdir" ]] || return
    # git may return a relative path (e.g. ".git"); make it absolute
    [[ "$gitdir" != /* ]] && gitdir="$PWD/$gitdir"
    if [[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" &&
      -d "$HOME/.dotfiles" && "$gitdir" -ef "$HOME/.dotfiles" ]]; then
      # Discovery was authoritative; make the remaining prompt calls explicit
      # so HOME descendants do not pay the launcher routing cost again.
      g=(git --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
    fi
  fi

  local branch="" ahead=0 behind=0 dirty="" line
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

  # Validate an inferred operation-state directory only when a marker exists.
  # This keeps ordinary redraws to one Git call while preserving Git's full
  # discovery semantics at filesystem boundaries and uncommon ceiling layouts.
  local op="" authoritative_gitdir=""
  if [[ -f "$gitdir/MERGE_HEAD" || -d "$gitdir/rebase-merge" ||
    -d "$gitdir/rebase-apply" || -f "$gitdir/CHERRY_PICK_HEAD" ||
    -f "$gitdir/REVERT_HEAD" ]]; then
    authoritative_gitdir="$("${g[@]}" rev-parse --git-dir 2>/dev/null)" ||
      authoritative_gitdir=""
    if [[ -n "$authoritative_gitdir" ]]; then
      [[ "$authoritative_gitdir" == /* ]] ||
        authoritative_gitdir="$PWD/$authoritative_gitdir"
      gitdir="$authoritative_gitdir"
    else
      gitdir=""
    fi
  fi
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
  # Escape literal % for zsh PROMPT_SUBST — bare % starts prompt sequences.
  [[ -n "${ZSH_VERSION:-}" ]] && out="${out//'%'/%%}"
  printf '%s' "$out"
}
