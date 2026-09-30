# shellcheck shell=bash
# Core environment: platform cache, exports.
#
# Dotfiles-owned exports go through _shell_env_set (shell-loader.sh):
# authoritative in interactive/login shells, fill-only in non-interactive
# children so caller overrides survive. LANG and MANPATH keep their existing
# fill-if-missing forms in every mode.

_UNAME="$(uname -s)"

export LANG="${LANG:-en_US.UTF-8}"
_shell_env_set DS_SSH_AUTO_ATTACH ds
_shell_env_set RIPGREP_CONFIG_PATH "$HOME/.config/ripgrep/config"
_shell_env_set FZF_DEFAULT_OPTS '--bind=ctrl-n:down,ctrl-p:up,ctrl-d:half-page-down,ctrl-u:half-page-up,alt-j:down,alt-k:up'
# A test or tool that points shdeps at a fixture config keeps it in every
# nested script instead of silently running the live hooks.
_shell_env_set SHDEPS_CONF_DIR "$HOME/.config/shdeps"

# Man pages from shdeps-managed tools. Guard against duplicate segments: unlike
# PATH, MANPATH gets no final de-duplication pass like 90-path.sh, and every
# new shell process re-sources env.d, so nested shells would otherwise
# accumulate copies.
case ":${MANPATH:-}:" in
  *":$HOME/.local/share/man:"*) ;;
  *) export MANPATH="$HOME/.local/share/man:${MANPATH:-}" ;;
esac

# Syntax-highlighted man pages via bat.
# MANROFFOPT=-c forces groff overstrike output so col -bx works on Linux
# (without it, groff emits raw ANSI SGR that col strips partially, leaving
# garbage like "4m" / "1m" in the output).
# Check batcat before bat: Debian/Ubuntu ship the syntax highlighter as
# batcat, but also have an unrelated 'bat' tool. Aliases (bat=batcat) are
# not inherited by the sh -c subprocess that man uses to invoke MANPAGER.
if command -v batcat >/dev/null 2>&1; then
  _shell_env_set MANROFFOPT "-c"
  _shell_env_set MANPAGER "sh -c 'col -bx | batcat -l man -p'"
elif command -v bat >/dev/null 2>&1; then
  _shell_env_set MANROFFOPT "-c"
  _shell_env_set MANPAGER "sh -c 'col -bx | bat -l man -p'"
fi

# Ensure non-interactive bash subshells get the same env.d layer as interactive
# shells. BASH_ENV is sourced automatically by bash for every non-interactive
# invocation and is inherited by child processes. A caller-provided BASH_ENV
# (a tool's own bash bootstrap) is kept for bash grandchildren of zsh.
_shell_env_set BASH_ENV "$HOME/.config/shell/env-noninteractive.sh"
