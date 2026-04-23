# shellcheck shell=bash
# Shared loader body for ~/.bashrc and ~/.zshrc.
# Sources all files in a directory, sorted by filename. Shell-specific files
# (*.bash, *.zsh) are mixed into the sort with common files (*.sh), so numeric
# prefixes control load order across both types. Call with the shell name to
# include its files:
#   _shell_source_dir dir         — *.sh only
#   _shell_source_dir dir bash    — *.bash and *.sh, sorted together
#   _shell_source_dir dir zsh     — *.zsh and *.sh, sorted together

_shell_source_dir() {
  local dir="$1" shell_ext="${2:-}" f sorted
  local -a files=()

  # zsh: enable nullglob for the globbing step, then restore afterward.
  # MUST NOT use `setopt localoptions nullglob` — that scopes ALL option
  # changes made during this function's execution (including by nested
  # functions like set_prompt() enabling PROMPT_SUBST while being sourced)
  # and reverts them on return. Manual save/restore keeps the scope tight.
  local _ng_prev=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    [[ -o nullglob ]] && _ng_prev=1
    setopt nullglob
  fi

  for f in "$dir"/*.sh; do [ -f "$f" ] && files+=("$f"); done
  if [ -n "$shell_ext" ]; then
    for f in "$dir"/*."$shell_ext"; do [ -f "$f" ] && files+=("$f"); done
  fi

  if [ -n "${ZSH_VERSION:-}" ] && [ "$_ng_prev" -eq 0 ]; then
    unsetopt nullglob
  fi

  [ "${#files[@]}" -gt 0 ] || return 0

  # Sort portably: external `sort` + `while read`. Equivalent to zsh's
  # ${(@f)$(...)} and bash's `read -r -d '' -a`, identical in both shells.
  sorted=$(printf '%s\n' "${files[@]}" | LC_ALL=C sort)
  files=()
  while IFS= read -r f; do files+=("$f"); done <<<"$sorted"

  # shellcheck disable=SC1090  # discovered dynamically from env.d/interactive.d
  if [ -n "${SHELL_LOADER_TIMING:-}" ]; then
    # Instrumented path for `shell-time`. Uses EPOCHREALTIME (bash 5+,
    # zsh with zsh/datetime) for fork-free microsecond timing. Emits one
    # tagged line per file to stderr; totals are computed by the driver.
    [ -n "${ZSH_VERSION:-}" ] && zmodload zsh/datetime 2>/dev/null
    local _t0 _t1 _s0 _s1 _u0 _u1 _du _ms _fr
    for f in "${files[@]}"; do
      _t0="${EPOCHREALTIME:-0.000000}"
      . "$f"
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
    for f in "${files[@]}"; do . "$f"; done
  fi
}
