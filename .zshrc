# ~/.zshrc: thin loader — config lives in ~/.config/shell/

# Source all files in a directory, sorted by filename.
# Shell-specific files (*.bash, *.zsh) are mixed into the sort with
# common files (*.sh), so numeric prefixes control load order across
# both types.  Call with the shell name to include its files:
#   _shell_source_dir dir         — *.sh only
#   _shell_source_dir dir zsh     — *.zsh and *.sh, sorted together
_shell_source_dir() {
  local f
  local -a files=()
  for f in "$1"/*.sh; do [ -f "$f" ] && files+=("$f"); done
  if [ -n "${2:-}" ]; then
    for f in "$1"/*."$2"; do [ -f "$f" ] && files+=("$f"); done
  fi
  files=(${(o)files})
  for f in "${files[@]}"; do . "$f"; done
}

# Environment
_shell_source_dir ~/.config/shell/env.d zsh

# Non-interactive? Stop here.
[[ -o interactive ]] || return

# Interactive
_shell_source_dir ~/.config/shell/interactive.d zsh
