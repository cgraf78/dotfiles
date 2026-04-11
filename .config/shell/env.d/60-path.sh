# shellcheck shell=bash
# PATH assembly and tool environment bootstraps.

[ -d "/usr/local/bin" ] && PATH="/usr/local/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"

if [ -d "$HOME/.bun/bin" ]; then
  export BUN_INSTALL="$HOME/.bun"
  PATH="$BUN_INSTALL/bin:$PATH"
fi

[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
# shellcheck disable=SC1091  # optional local rust bootstrap script
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
