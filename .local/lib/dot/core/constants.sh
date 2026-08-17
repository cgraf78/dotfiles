# shellcheck shell=bash
# Core constants shared by dot runtime modules.

if ! declare -F _dot_xdg_path >/dev/null 2>&1; then
  # shellcheck source=xdg.sh disable=SC1091
  . "${BASH_SOURCE[0]%/*}/xdg.sh"
fi

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"

# Overlay link manifest — the authoritative record of which overlay owns each
# symlinked path. Written by `_link_overlays` (core/repos/overlays.sh) and read
# by the overlay doctor check (core/doctor/overlays.sh). Both must agree on the
# location, so it is single-sourced here rather than retyped in each module.
_dot_xdg_path state "dot/overlay-links" || return
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_OVERLAY_MANIFEST="$REPLY"
# Read the pre-XDG location once when adopting an existing installation. New
# writes always use DOT_OVERLAY_MANIFEST.
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_OVERLAY_LEGACY_MANIFEST="$HOME/.local/state/dot/overlay-links"

# Overlay .ssh config merge target — written by `_merge_overlay_ssh_configs`
# (core/overlays.sh) and validated by the merges doctor check
# (core/doctor/merges.sh); single-sourced so writer and checker agree.
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_SSH_CONFIG="$HOME/.ssh/config"

# The dot launcher on PATH — referenced by the self-update re-exec
# (core/update.sh) and the repo/PATH doctor checks (core/doctor/repos.sh).
# Git-worktree-relative pathspecs derive the relative form via
# "${DOT_BIN#"$HOME/"}".
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_BIN="$HOME/.local/bin/dot"

# Shell config directories. The shell-startup hot path (.bashrc, .zshrc,
# core/shell-loader.sh, .config/shell/env-noninteractive.sh) intentionally keeps
# these as literals so startup never sources this file. These constants are the
# canonical value the cold-path doctor checks validate against; a static test
# (tests/core/static.sh) asserts the hot-path literals stay in sync with them.
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_SHELL_ENV_DIR="$HOME/.config/shell/env.d"
# shellcheck disable=SC2034  # used by scripts that source the runtime modules
DOT_SHELL_INTERACTIVE_DIR="$HOME/.config/shell/interactive.d"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"
