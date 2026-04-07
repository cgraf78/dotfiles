#!/bin/bash
# Post-install hook for bash-preexec.

post_bash_preexec() {
  [[ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]] || return 0
  ln -sfn "$HOME/.local/share/bash-preexec/bash-preexec.sh" "$HOME/.bash-preexec.sh"
}
