# shellcheck shell=bash
# Post-install hook for mise — syncs the tools declared in the
# tracked config at `~/.config/mise/config.toml` whenever mise
# itself is installed or updated.
#
# Trust the config first: mise silently refuses to parse untrusted
# files (including our XDG config on a fresh host), and `mise
# install` no-ops without any error. Trusting is idempotent.
#
# `mise install` is run from `$HOME` so mise picks up the XDG
# config regardless of the caller's cwd.

post() {
  command -v mise &>/dev/null || return 0
  mise trust "$HOME/.config/mise/config.toml" &>/dev/null || true
  (cd "$HOME" && mise install) || true
}
