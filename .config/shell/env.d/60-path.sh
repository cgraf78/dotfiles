# shellcheck shell=bash
# PATH assembly and tool environment bootstraps.

[ -d "/usr/local/bin" ] && PATH="/usr/local/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"

# mise-managed formatter/linter tools (see ~/.config/mise/config.toml).
# Adding the shims dir directly (instead of `eval "$(mise activate zsh)"`)
# avoids the chpwd hook that full mise activation installs — we only
# need PATH exposure, not per-dir version switching.
[ -d "$HOME/.local/share/mise/shims" ] &&
  PATH="$HOME/.local/share/mise/shims:$PATH"

if [ -d "$HOME/.bun/bin" ]; then
  export BUN_INSTALL="$HOME/.bun"
  PATH="$BUN_INSTALL/bin:$PATH"
fi

# shellcheck disable=SC1091  # optional local tool bootstrap script
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
# shellcheck disable=SC1091  # optional local rust bootstrap script
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
true
