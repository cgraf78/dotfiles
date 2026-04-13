# shellcheck shell=bash
# ~/.bashrc: thin loader — config lives in ~/.config/shell/

# Source all files in a directory, sorted by filename.
# Shell-specific files (*.bash, *.zsh) are mixed into the sort with
# common files (*.sh), so numeric prefixes control load order across
# both types.  Call with the shell name to include its files:
#   _shell_source_dir dir         — *.sh only
#   _shell_source_dir dir bash    — *.bash and *.sh, sorted together
_shell_source_dir() {
  local f
  local -a files=()
  for f in "$1"/*.sh; do [ -f "$f" ] && files+=("$f"); done
  if [ -n "${2:-}" ]; then
    for f in "$1"/*."$2"; do [ -f "$f" ] && files+=("$f"); done
  fi
  IFS=$'\n' read -r -d '' -a files < <(printf '%s\n' "${files[@]}" | LC_ALL=C sort) || true
  # shellcheck disable=SC1090  # files are discovered dynamically from env.d/interactive.d
  for f in "${files[@]}"; do . "$f"; done
}

# Environment
_shell_source_dir ~/.config/shell/env.d bash

# Non-interactive? Stop here.
case $- in *i*) ;; *) return ;; esac

# Interactive
_shell_source_dir ~/.config/shell/interactive.d bash
