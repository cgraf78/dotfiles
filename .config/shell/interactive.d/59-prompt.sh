# shellcheck shell=bash
# Shared prompt helpers: git branch/status/upstream coloring, the
# long-command notification, and the terminal-mode restore. Numbered 59 so it
# loads before 60-prompt.bash/.zsh, which depend on __git_prompt,
# __cmd_notify, __term_restore, and the _PC_* color constants defined here.

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
# Accepted: resolved binaries bypass git shell functions on every path
# (the hit path already did); no such function exists here.
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
  local retry="$1" real_bin
  shift
  if [[ "$retry" == 1 && "$1" == "$_DOT_GIT_PROMPT_BIN" &&
    "$_DOT_GIT_PROMPT_BIN" != "$_DOT_GIT_PROMPT_REAL_BIN" ]]; then
    # Re-dispatch via shift instead of `cmd[0]=...`: zsh arrays are
    # 1-based, so index-zero assignment fails there. Identical argv.
    "$@" 2>/dev/null || {
      real_bin="$_DOT_GIT_PROMPT_REAL_BIN"
      shift
      "$real_bin" "$@" 2>/dev/null
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
  [[ "$branch" == "(detached)" ]] && branch="$(_dot_git_prompt_try 1 "${g[@]}" rev-parse --short HEAD)"
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
    authoritative_gitdir="$(_dot_git_prompt_try 1 "${g[@]}" rev-parse --git-dir)" ||
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

# Inside tmux, a long-running command rings the terminal and marks its pane
# pending when it finishes, through tmux-tools' term-notify-sound, so a build
# or test left running in a side pane gets noticed like an agent waiting for
# you. PROMPT_NOTIFY_SECONDS sets the threshold in seconds (default 30; 0
# turns it off). The prompt hooks in 60-prompt.bash/.zsh call __cmd_notify.

# Return whether a finished command ran long enough to notify about and ended
# on its own: Ctrl-C (130) and Ctrl-Z (148 on Linux, 146 on macOS, where
# SIGTSTP is 18) mean someone was at the keyboard.
# Args: $1 - elapsed seconds, $2 - exit status.
__cmd_notify_wanted() {
  local elapsed="$1" rc="$2" threshold="${PROMPT_NOTIFY_SECONDS:-30}"
  case "$threshold" in
    '' | *[!0-9]*) threshold=30 ;;
  esac
  # Base 10 explicitly: bash reads a leading zero as octal.
  threshold=$((10#$threshold))
  ((threshold > 0 && elapsed >= threshold)) || return 1
  [[ "$rc" != 130 && "$rc" != 146 && "$rc" != 148 ]]
}

# Notify for a finished command when __cmd_notify_wanted agrees, unless you
# were looking at its pane when it finished: the most recently active client
# shows that pane and its terminal has focus (tmux focus-events). Only that
# client counts because tmux flags every client focused when it attaches and
# clears the flag only on a focus-out, so a stale attachment (an old editor
# terminal) can stay "focused" for days. Switching to another pane, window,
# or application before a command finishes still notifies. Interactive
# programs (an editor, a pager, an fzf picker, ssh) are normally used from
# the pane you are looking at, so they do not notify, without a list of
# program names to keep current. Only a shell still in a tmux pane counts:
# TMUX and TMUX_PANE leak into programs launched from one, such as an editor
# started with `code .`, whose own terminals replace TERM_PROGRAM. Best
# effort: without tmux, tmux-tools, or a terminal, nothing happens.
# Args: $1 - elapsed seconds, $2 - exit status.
__cmd_notify() {
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" && "${TERM_PROGRAM:-}" == tmux ]] || return 0
  __cmd_notify_wanted "$1" "$2" || return 0
  # Activity is in whole seconds, and moving between two tmux terminals
  # updates both in the same second, so a tie counts as watched when any of
  # the tied clients is focused on this pane.
  tmux list-clients -F '#{client_activity} #{client_flags} #{pane_id}' 2>/dev/null |
    awk -v pane="$TMUX_PANE" '
      $1 > newest { newest = $1; watched = 0 }
      $1 == newest && $2 ~ /(^|,)focused(,|$)/ && $3 == pane { watched = 1 }
      END { exit !watched }' &&
    return 0
  command -v term-notify-sound >/dev/null 2>&1 || return 0
  term-notify-sound >/dev/null 2>&1 || true
}

# Turn off terminal modes a program left on because it died without cleaning
# up, so the prompt comes back usable. The usual cause is a dropped ssh
# session (status 255) whose remote tmux had enabled mouse and focus
# reporting, the alternate screen, and extended keys: every mouse move or
# pane switch then sends a report that the line editor beeps at, and the
# screen stays the remote's. A program killed by a signal (status > 128) can
# leave the same state. Nothing is reset while a job is stopped: `fg`
# resumes it without resending its modes, so resetting them would break, say,
# a suspended ssh session's remote tmux. The stop itself has status 128 plus
# SIGTSTP, SIGSTOP, SIGTTIN, or SIGTTOU, which span 145-150 on Linux and
# macOS (the other signals in that range, SIGCHLD and SIGCONT, cannot kill a
# process); a later failure while the job waits is caught by the job check.
# That check cannot tell a job that restores its own modes on `fg` (a
# suspended vim) from one that cannot (ssh), so any stopped job defers the
# reset to the next failure after it ends.
# Runs from the prompt hook, so the normal path is a single arithmetic test
# with no fork; it never clears the screen or scrollback, unlike `reset`.
#
# The alternate-screen exit matters most. Leaving with 1049 restores the
# cursor saved on entry, which puts the prompt right below the command that
# started the session. Where the exit has to be blind, it must not move the
# cursor when the normal screen is already showing:
#   - Inside tmux, one query says which screen is showing. tmux keeps the 1049
#     save apart from DECSC and restores it even on the normal screen, where
#     it is stale and the prompt would overwrite earlier output, so 1049 is
#     sent only when the alternate screen is on. The answer counts only when
#     the pane's tty is the shell's own: a terminal inside the pane (Neovim's
#     :terminal) or launched from it inherits the pane's variables, but its
#     screen is not the one tmux reports, so it takes the blind exit.
#   - Other terminals (xterm, WezTerm, VS Code, Terminal.app, Termux) get
#     DECSC then 1049: terminals that keep a saved cursor per screen restore
#     the entry position from the alternate screen and the just-saved one
#     (no move) from the normal screen; terminals with one shared slot should
#     end up where the alternate screen's cursor was, as 1047 would.
#   - A multiplexer that could not be asked (GNU screen, or tmux before 3.2,
#     which sets no TERM_PROGRAM and may run with an xterm TERM) separates
#     the saves like tmux, so it gets 1047, which never moves the cursor.
#
# Scroll margins: resetting them homes the cursor, so outside the alternate
# screen the cursor is saved and restored around the reset, on both screens
# where the exit is blind (a terminal may keep margins per screen). On the
# alternate screen inside tmux, margins and origin mode reset before the 1049
# exit restores the cursor. A DECRC can bring back a saved origin mode, which
# stays inert while the margins span the whole screen; remote tmux never sets
# it.
#
# The rest: mouse tracking (all encodings), focus reporting, theme-change
# reports (2031, requested by tmux 3.6), synchronized output, left/right
# margins, mintty's application escape key, modifyOtherKeys back to its
# default, a kitty keyboard pop on each screen (terminals such as WezTerm
# keep one stack per screen), cursor visibility, normal cursor keys and
# keypad, the prompt's blinking block cursor (52-cursor.sh), autowrap,
# replace mode, attributes, and the ASCII character set in G0 (shifted in).
# Terminals ignore the sequences they do not implement. Bracketed paste is
# left alone: the line editor enables it for each line.
# Args: $1 - exit status of the command that just finished.
__term_restore() {
  ((${1:-0} > 128)) || return 0
  case $1 in
    14[5-9] | 150) return 0 ;;
  esac
  [[ -t 1 ]] || return 0
  local screen alt="" term=${TERM:-} reply shell_tty
  case $term in
    '' | dumb) return 0 ;;
  esac
  # zsh reads its job table without a fork; bash needs one, which only this
  # rare path pays. eval keeps the zsh syntax away from bash's parser.
  if [[ -n ${ZSH_VERSION:-} ]]; then
    eval '[[ ${(v)jobstates} != *suspended* ]]' || return 0
  else
    [[ -z $(jobs -s) ]] || return 0
  fi
  # TMUX leaks into terminals launched from a tmux shell (`code .`), whose
  # TERM_PROGRAM differs; only a shell still in a tmux pane asks tmux.
  if [[ -n ${TMUX:-} && -n ${TMUX_PANE:-} && ${TERM_PROGRAM:-} == tmux ]]; then
    reply=$(tmux display-message -p -t "$TMUX_PANE" '#{alternate_on} #{pane_tty}' 2>/dev/null)
    # zsh's TTY is its own; bash would take an inherited one, so it asks.
    if [[ -n ${ZSH_VERSION:-} ]]; then
      shell_tty=$TTY
    else
      shell_tty=$(tty 2>/dev/null)
    fi
    if [[ -n $shell_tty && ${reply#* } == "$shell_tty" ]]; then
      alt=${reply%% *}
    fi
  elif [[ -n ${TMUX:-} && -z ${TERM_PROGRAM:-} ]]; then
    term=tmux
  fi
  case $alt:$term in
    1:*) screen=$'\e[?6l\e[r\e[?1049l' ;;
    0:*) screen=$'\e7\e[r\e8' ;;
    *:screen* | *:tmux*) screen=$'\e[?1047l\e7\e[r\e8' ;;
    *) screen=$'\e7\e[r\e8\e7\e[?1049l\e7\e[r\e8' ;;
  esac
  printf '%s' $'\e[<u' "$screen" \
    $'\e[?9l\e[?1000l\e[?1001l\e[?1002l\e[?1003l\e[?1005l\e[?1006l\e[?1015l\e[?1016l' \
    $'\e[?1004l\e[?2031l\e[?2026l\e[?69l\e[?7727l\e[>4m\e[<u' \
    $'\e[?25h\e[?1l\e>\e[1 q\e[?7h\e[4l\e[0m\e(B\017'
}
