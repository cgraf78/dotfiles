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

_DOT_GIT_PROMPT_BIN=git
_DOT_GIT_PROMPT_REAL_BIN=git
_DOT_GIT_PROMPT_PATH_SNAPSHOT=""

# Accept a published real-git cache file. The file carries the resolved
# binary plus the PATH it was resolved against; entries from a different
# PATH, removed binaries, and the launcher itself are all rejected so a
# stale cache can never route prompts through the slow path silently.
_dot_git_prompt_cache_accept() {
  local cache="$1" candidate="" cached_path=""
  local launcher="$HOME/.local/bin/git"
  [[ -r "$cache" ]] || return 1
  {
    IFS= read -r candidate || return 1
    IFS= read -r cached_path || return 1
  } <"$cache"
  [[ -n "$candidate" && "$cached_path" == "${PATH:-}" &&
    -x "$candidate" && ! -d "$candidate" ]] || return 1
  if [[ -e "$launcher" && "$candidate" -ef "$launcher" ]]; then
    return 1
  fi
  _DOT_GIT_PROMPT_REAL_BIN="$candidate"
  _DOT_GIT_PROMPT_PATH_SNAPSHOT="${PATH:-}"
}

# Walk PATH for the first git past the dotfiles launcher, without forking.
# This unrolls the `command -v` chain in-process: for each executable git on
# PATH, skip the launcher by identity and skip any other launcher copy by
# its marker line, and take the first real binary. Sets REPLY on success.
_dot_git_prompt_resolve_past_launcher() {
  local launcher="$HOME/.local/bin/git"
  local marker="# Dotfiles-aware launcher for Git."
  local dir rest candidate line=""
  rest="${PATH:-/usr/local/bin:/usr/bin:/bin}:"
  while [[ -n "$rest" ]]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    [[ -n "$dir" ]] || dir="."
    candidate="$dir/git"
    [[ -x "$candidate" && ! -d "$candidate" ]] || continue
    if [[ -e "$launcher" && "$candidate" -ef "$launcher" ]]; then
      continue
    fi
    line=""
    {
      IFS= read -r line
      IFS= read -r line
    } <"$candidate" 2>/dev/null || true
    [[ "$line" == "$marker" ]] && continue
    REPLY="$candidate"
    return 0
  done
  return 1
}

_dot_git_prompt_cache_dir() {
  case "${XDG_CACHE_HOME:-}" in
    /*) REPLY="$XDG_CACHE_HOME" ;;
    *) REPLY="$HOME/.cache" ;;
  esac
}

# Select a system git for read-only prompt calls. Relocated or
# loader-wrapped toolchains can add tens of milliseconds of spawn overhead
# per git fork; the system binary reads the same user and repo config, so
# porcelain and rev-parse output is identical. Set
# DOT_GIT_PROMPT_SYSTEM_GITS to a space-separated candidate list to
# override, or to empty to disable. Sets REPLY on success.
_dot_git_prompt_select_system() {
  local candidates="${DOT_GIT_PROMPT_SYSTEM_GITS-/usr/bin/git /bin/git}"
  local real_bin="$1" launcher="$HOME/.local/bin/git"
  local marker="# Dotfiles-aware launcher for Git."
  local candidate rest line prefix
  [[ -n "$candidates" ]] || return 1
  # Never downgrade the launcher's first preference: a Homebrew toolchain
  # is typically newer than the system binary, so keep it when resolved.
  for prefix in "${HOMEBREW_PREFIX:-}" /opt/homebrew /home/linuxbrew/.linuxbrew; do
    [[ -n "$prefix" ]] || continue
    case "$prefix" in /*) ;; *) continue ;; esac
    case "$real_bin" in "$prefix"/*) return 1 ;; esac
  done
  rest="$candidates "
  while [[ -n "$rest" ]]; do
    candidate="${rest%% *}"
    rest="${rest#* }"
    [[ -n "$candidate" ]] || continue
    [[ -x "$candidate" && ! -d "$candidate" ]] || continue
    if [[ -e "$launcher" && "$candidate" -ef "$launcher" ]]; then
      continue
    fi
    line=""
    {
      IFS= read -r line
      IFS= read -r line
    } <"$candidate" 2>/dev/null || true
    [[ "$line" == "$marker" ]] && continue
    REPLY="$candidate"
    return 0
  done
  return 1
}

# Run a read-only prompt git call, retrying once past the system fast-path
# binary when repository signals say git should have worked. The retry keeps
# exotic binaries (older system gits, new repo formats) behavior-identical
# at the cost of one extra fork on that rare path; ordinary failures outside
# repositories never retry.
_dot_git_prompt_try() {
  local retry="$1"
  local -a real_cmd=()
  shift
  if [[ "$retry" == 1 && "$1" == "$_DOT_GIT_PROMPT_BIN" &&
    "$_DOT_GIT_PROMPT_BIN" != "$_DOT_GIT_PROMPT_REAL_BIN" ]]; then
    "$@" 2>/dev/null || {
      real_cmd=("$@")
      real_cmd[0]="$_DOT_GIT_PROMPT_REAL_BIN"
      "${real_cmd[@]}" 2>/dev/null
    }
  else
    "$@" 2>/dev/null
  fi
}

_dot_git_prompt_resolve_command() {
  local cache_base legacy launcher_cache scanned=""

  if [[ "$_DOT_GIT_PROMPT_BIN" != git &&
    "$_DOT_GIT_PROMPT_PATH_SNAPSHOT" == "${PATH:-}" &&
    -x "$_DOT_GIT_PROMPT_BIN" && ! -d "$_DOT_GIT_PROMPT_BIN" ]]; then
    return 0
  fi

  _DOT_GIT_PROMPT_BIN=git
  _DOT_GIT_PROMPT_REAL_BIN=git
  _DOT_GIT_PROMPT_PATH_SNAPSHOT=""
  _dot_git_prompt_cache_dir
  cache_base="$REPLY"
  legacy="$cache_base/dot/git-real"
  launcher_cache="$cache_base/dotfiles/git-real"
  if ! _dot_git_prompt_cache_accept "$legacy" &&
    ! _dot_git_prompt_cache_accept "$launcher_cache"; then
    # Both caches are missing or stale (PATH drift invalidates them): resolve
    # past the launcher directly instead of paying launcher startup on every
    # prompt until something republishes. Best-effort write-back keeps fresh
    # shells on the fast path too.
    if _dot_git_prompt_resolve_past_launcher; then
      scanned="$REPLY"
      _DOT_GIT_PROMPT_REAL_BIN="$scanned"
      _DOT_GIT_PROMPT_PATH_SNAPSHOT="${PATH:-}"
      local tmp
      if mkdir -p "${legacy%/*}" 2>/dev/null &&
        tmp="$(mktemp "${legacy}.XXXXXX" 2>/dev/null)" &&
        {
          printf '%s\n' "$scanned"
          printf '%s\n' "${PATH:-}"
        } >"$tmp" 2>/dev/null &&
        mv -f -- "$tmp" "$legacy" 2>/dev/null; then
        :
      else
        rm -f -- "${tmp:-${legacy}.XXXXXX}" 2>/dev/null
      fi
    fi
  fi

  # Prefer the system binary for read-only calls; fall back to the resolved
  # real git, or to the PATH launcher when nothing resolved. A selected
  # system binary memoizes like a resolution so PATH-stable shells pay the
  # candidate checks once.
  if _dot_git_prompt_select_system "$_DOT_GIT_PROMPT_REAL_BIN"; then
    _DOT_GIT_PROMPT_BIN="$REPLY"
    _DOT_GIT_PROMPT_PATH_SNAPSHOT="${PATH:-}"
  else
    _DOT_GIT_PROMPT_BIN="$_DOT_GIT_PROMPT_REAL_BIN"
  fi
}

# The launcher validates its cache when it publishes it. Reading that result
# once keeps prompt redraws from re-running launcher discovery; the resolver
# revalidates it cheaply so PATH changes and removed binaries fall back
# through the launcher while a stale cache re-resolves past it instead.
_dot_git_prompt_resolve_command

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
  _dot_git_prompt_resolve_command
  local -a g=("$_DOT_GIT_PROMPT_BIN")
  local gitdir="" git_status
  if [[ "$PWD" == "$HOME" && -d "$HOME/.dotfiles" ]]; then
    # The home prompt intentionally shows the base dotfiles repo. Probe it
    # directly so the prompt does not pay for the PATH-visible git launcher and
    # a separate rev-parse before the status call.
    g=("$_DOT_GIT_PROMPT_BIN" --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
    gitdir="$HOME/.dotfiles"
  else
    gitdir=$(_dot_git_prompt_gitdir 2>/dev/null) || gitdir=""
    if [[ -z "$gitdir" && -d "$HOME/.dotfiles" ]]; then
      case "$PWD" in
        # Deliberately launcher-routed: dotfiles-descendant discovery
        # depends on launcher routing that a resolved binary would skip.
        "$HOME"/*) gitdir="$(git rev-parse --git-dir 2>/dev/null)" ;;
      esac
    fi
    if [[ -n "$gitdir" ]]; then
      [[ "$gitdir" != /* ]] && gitdir="$PWD/$gitdir"
      if [[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" &&
        -d "$HOME/.dotfiles" && "$gitdir" -ef "$HOME/.dotfiles" ]]; then
        g=("$_DOT_GIT_PROMPT_BIN" --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
      fi
    fi
  fi

  # Branch, upstream, ahead/behind, and dirty state come from one authoritative
  # Git call. Common repositories expose their gitdir through a local marker,
  # avoiding a second launcher call solely for operation-state file tests.
  # A discovered gitdir means status should work: retry past the system
  # fast-path binary on failure so exotic binaries stay behavior-identical.
  local repo_signals=0
  [[ -n "$gitdir" ]] && repo_signals=1
  git_status="$(_dot_git_prompt_try "$repo_signals" "${g[@]}" --no-optional-locks status --porcelain=v2 --branch)" || return
  # Fail fast when discovery already failed: without a gitdir and without a
  # branch header in the status output there is no repository to describe,
  # so skip the rev-parse fallback. The branch parser below would find
  # nothing and return the same empty prompt after paying for the fork.
  if [[ -z "$gitdir" && "$git_status" != *"# branch.head "* ]]; then
    return
  fi
  if [[ -z "$gitdir" ]]; then
    gitdir="$("${g[@]}" rev-parse --git-dir 2>/dev/null)"
    [[ -n "$gitdir" ]] || return
    # git may return a relative path (e.g. ".git"); make it absolute
    [[ "$gitdir" != /* ]] && gitdir="$PWD/$gitdir"
    if [[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" &&
      -d "$HOME/.dotfiles" && "$gitdir" -ef "$HOME/.dotfiles" ]]; then
      # Discovery was authoritative; make the remaining prompt calls explicit
      # so HOME descendants do not pay the launcher routing cost again.
      g=("$_DOT_GIT_PROMPT_BIN" --git-dir="$HOME/.dotfiles" --work-tree="$HOME")
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
