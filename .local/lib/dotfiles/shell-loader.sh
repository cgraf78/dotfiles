# shellcheck shell=bash
# Shared loader body for ~/.bashrc and ~/.zshrc.
# Sources all files in a directory in byte order of name. Shell-specific files
# (*.bash, *.zsh) are mixed into the sort with common files (*.sh), so numeric
# prefixes control load order across both types. Call with the shell name to
# include its files:
#   _shell_source_dir dir         — *.sh only
#   _shell_source_dir dir bash    — *.bash and *.sh, sorted together
#   _shell_source_dir dir zsh     — *.zsh and *.sh, sorted together

# Environment ownership for env.d fragments.
#
# Interactive and login loads (~/.bashrc, ~/.zshrc, ~/.zprofile) are
# authoritative: a new tmux pane inherits the tmux server's global environment,
# which goes stale, so those shells must re-apply every dotfiles value.
#
# Non-interactive loads (env-noninteractive.sh via BASH_ENV and ~/.zshenv, and
# ~/.bashrc when bash reads it for a socket-stdin or sshd `bash -c`) run in
# every nested `bash -c`, script, and git hook. Their inherited environment
# is the caller's choice (`EDITOR=vim git commit`, `TZ=UTC ./script`), so they
# only fill values the caller did not pass down. Shell-local state (functions,
# shopt/setopt, arrays, fpath, system rc bootstraps) is never inherited and
# still loads in every shell; only exported values are subject to this rule.
#
# Loader state is shell-local, never exported, and cleared after the load, so
# it cannot leak into children the way the retired exported load guard did:
#   _SHELL_ENV_MODE             "fill" only while a fill-only load runs
#   _SHELL_ENV_OWNED            names _shell_env_set exported during this load
#   _SHELL_ENV_INHERITED_PATH   PATH as inherited, for 90-path.sh
_shell_load_env() {
  local shell_ext="${1:-}" _env_mode="${2:-authoritative}" _pid
  _pid="${BASHPID:-$$}"
  [ "${_SHELL_ENV_LOADED_PID:-}" = "$_pid" ] && return 0
  _SHELL_ENV_LOADED_PID="$_pid"
  # Scrub the retired exported guard from env-noninteractive.sh. Long-lived
  # tmux servers keep it in their global environment; unsetting it here stops
  # new shells from re-exporting a stale value to their children.
  unset _SHELL_ENV_NONINTERACTIVE_LOADED_SHELLS
  # Unset before assigning so an inherited (exported) copy can neither force
  # a mode nor survive as an exported variable.
  unset _SHELL_ENV_MODE _SHELL_ENV_OWNED _SHELL_ENV_INHERITED_PATH
  if [ "$_env_mode" = fill ]; then
    _SHELL_ENV_MODE=fill
    _SHELL_ENV_OWNED=" "
    _SHELL_ENV_INHERITED_PATH=${PATH-}
  fi
  # env.d sources system rc code written without `set -u` in mind (the work
  # bootstrap's /etc/profile.d fragments). Since nested shells load env.d
  # again, a `bash -u` or `bash -euo pipefail script` child would print
  # "unbound variable" and abort the rest of that fragment. Suspend nounset
  # for the load and restore the caller's setting for its own command. The
  # flag's name must not collide with anything a sourced fragment assigns.
  local _shell_env_nounset=0
  case $- in *u*)
    _shell_env_nounset=1
    set +u
    ;;
  esac
  _shell_source_dir "$HOME/.config/shell/env.d" "$shell_ext"
  unset _SHELL_ENV_MODE _SHELL_ENV_OWNED _SHELL_ENV_INHERITED_PATH
  if [ "$_shell_env_nounset" = 1 ]; then
    set -u
  fi
}

# _shell_env_inherited NAME
# Succeed only during a fill-only load when NAME is set and no earlier
# _shell_env_set call in this load exported it, i.e. the caller passed it
# down. A later fragment may therefore replace an earlier fragment's value
# (base's RIPGREP_CONFIG_PATH, then the editor overlay's), and a fragment that
# unsets NAME (a dead agent socket) makes it missing again. An inherited empty
# value counts as present: `VAR= cmd` is a deliberate caller choice.
#
# Ownership is tracked instead of snapshotting the inherited environment: the
# bash snapshot needs a `compgen -e` fork plus a slow glob over a multi-KB
# name list per lookup (~6 ms per bash shell here). The cost of tracking is one
# rule: every env.d writer of a name managed here must use _shell_env_set; a
# plain export from an earlier fragment looks inherited to later fragments.
_shell_env_inherited() {
  [ "${_SHELL_ENV_MODE:-}" = fill ] || return 1
  case "$_SHELL_ENV_OWNED" in *" $1 "*) return 1 ;; esac
  case "$1" in '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;; esac
  eval "[ -n \"\${$1+x}\" ]"
}

# _shell_env_set NAME VALUE
# Export a dotfiles-owned value: always in authoritative loads, and in
# fill-only loads only when the caller did not pass NAME down. Use it for
# every env.d export of a dotfiles default. Keep `${NAME:-default}` for values
# that should yield to an existing value in every mode, and use plain `export`
# with a comment for a value that must win even over a caller (none today).
# Overlays guard calls with a plain-export fallback so they keep working on a
# base checkout that predates this helper.
#
# The fill-only check is inlined rather than calling _shell_env_inherited:
# env.d makes dozens of these calls in every non-interactive shell, and the
# extra function call doubles their cost in bash.
_shell_env_set() {
  if [ "${_SHELL_ENV_MODE:-}" = fill ]; then
    case "$_SHELL_ENV_OWNED" in
      *" $1 "*) ;;
      *)
        case "$1" in '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;; esac
        eval "[ -z \"\${$1+x}\" ]" || return 0
        _SHELL_ENV_OWNED="$_SHELL_ENV_OWNED$1 "
        ;;
    esac
  fi
  export "$1=$2"
}

_shell_source_dir() {
  local dir="$1" shell_ext="${2:-}" f _src_f
  local _src_lc_set=${LC_ALL+x} _src_lc_prev=${LC_ALL-}
  local _src_gs_set=${GLOBSORT+x} _src_gs_prev=${GLOBSORT-}
  local -a _src_entries=() files=()

  # A missing directory loads nothing. Checking first also keeps bash's
  # failglob from aborting the glob below with LC_ALL still pinned.
  [ -d "$dir" ] || return 0

  # zsh: enable nullglob and disable numericglobsort for the globbing step,
  # then restore afterward. MUST NOT use `setopt localoptions nullglob` —
  # that scopes ALL option changes made during this function's execution
  # (including by nested functions like set_prompt() enabling PROMPT_SUBST
  # while being sourced) and reverts them on return. Manual save/restore
  # keeps the scope tight.
  local _ng_prev=0 _ngs_prev=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    [[ -o nullglob ]] && _ng_prev=1
    [[ -o numericglobsort ]] && _ngs_prev=1
    setopt nullglob
    unsetopt numericglobsort
  fi

  # Sort without forking: one glob over the whole directory comes back
  # sorted by both shells, so common and shell-specific files interleave by
  # name without an external `sort`. That keeps a caller's PATH out of it
  # (a script that runs `bash` with a PATH lacking coreutils still loads
  # env.d) and saves the pipeline's two forks in every shell. Globs collate
  # by locale, so pin byte order for the expansion alone: fragments must see
  # the caller's locale, and it must not differ by host (en_US puts
  # 30-ab.sh before 30-a-c.sh and 40-alpha.sh before 40-Zed.sh). An empty
  # GLOBSORT (bash 5.3+; inert elsewhere) and zsh's numericglobsort reset
  # likewise keep a user's glob-sort preference out of load order.
  # Restoring an unusable inherited locale makes bash warn, which the
  # redirect keeps quiet since the shell already runs without it.
  LC_ALL=C
  [ -n "$_src_gs_set" ] && GLOBSORT=
  _src_entries=("$dir"/*)
  [ -n "$_src_gs_set" ] && GLOBSORT=$_src_gs_prev
  if [ -n "$_src_lc_set" ]; then
    { LC_ALL=$_src_lc_prev; } 2>/dev/null
  else
    { unset LC_ALL; } 2>/dev/null
  fi

  if [ -n "${ZSH_VERSION:-}" ]; then
    [ "$_ng_prev" -eq 0 ] && unsetopt nullglob
    [ "$_ngs_prev" -eq 1 ] && setopt numericglobsort
  fi

  # Without zsh's nullglob, an empty bash glob stays the literal pattern,
  # which the suffix or -f test drops. An empty shell_ext selects *.sh only.
  for f in ${_src_entries[@]+"${_src_entries[@]}"}; do
    case $f in
      *.sh | *."${shell_ext:-sh}") [ -f "$f" ] && files+=("$f") ;;
    esac
  done

  [ "${#files[@]}" -gt 0 ] || return 0

  # shellcheck disable=SC1090  # discovered dynamically from env.d/interactive.d
  # Sourced files share this function's dynamic scope: a top-level `for f`
  # in a sourced file (master.zshrc walks its completion list that way)
  # rebinds the loop variable. Pin the values still needed after each
  # source so timing labels and iteration stay correct. The loop list is
  # expanded once up front, so a fragment that reuses `files` cannot
  # change which files load.
  if [ -n "${SHELL_LOADER_TIMING:-}" ]; then
    # Instrumented path for `shell-time`. Uses EPOCHREALTIME (bash 5+,
    # zsh with zsh/datetime) for fork-free microsecond timing. Emits one
    # tagged line per file to stderr; totals are computed by the driver.
    [ -n "${ZSH_VERSION:-}" ] && zmodload zsh/datetime 2>/dev/null
    local _t0 _t1 _s0 _s1 _u0 _u1 _du _ms _fr
    for f in "${files[@]}"; do
      _t0="${EPOCHREALTIME:-0.000000}"
      _src_f=$f
      . "$f"
      f=$_src_f
      _t1="${EPOCHREALTIME:-0.000000}"
      _s0=${_t0%.*}
      _u0=${_t0#*.}
      _u0="${_u0}000000"
      _u0="${_u0:0:6}"
      _s1=${_t1%.*}
      _u1=${_t1#*.}
      _u1="${_u1}000000"
      _u1="${_u1:0:6}"
      _du=$(((10#$_s1 - 10#$_s0) * 1000000 + 10#$_u1 - 10#$_u0))
      _ms=$((_du / 1000))
      _fr=$((_du % 1000))
      printf 'SHELL_TIMING\t%d.%03d\t%s\n' "$_ms" "$_fr" "$f" >&2
    done
  else
    for f in "${files[@]}"; do
      _src_f=$f
      . "$f"
      f=$_src_f
    done
  fi
}
