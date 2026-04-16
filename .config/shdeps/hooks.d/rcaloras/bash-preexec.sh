# shellcheck shell=bash
# Post-install hook for bash-preexec.

post() {
  [[ -f "$HOME/.local/share/rcaloras/bash-preexec/bash-preexec.sh" ]] || return 0
  ln -sfn "$HOME/.local/share/rcaloras/bash-preexec/bash-preexec.sh" "$HOME/.bash-preexec.sh"
}

uninstall() {
  rm -f "$HOME/.bash-preexec.sh"
}
