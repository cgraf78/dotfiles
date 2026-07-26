# shellcheck shell=bash
# Core environment: platform cache, exports.

_UNAME="$(uname -s)"

export LANG="${LANG:-en_US.UTF-8}"
export EDITOR=nvim
export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-claude}"
export DS_SSH_AUTO_ATTACH=ds
export NVIM_COLORSCHEME=night-owl
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
export LG_CONFIG_FILE="$HOME/.config/lazygit/config.yml"
export FZF_DEFAULT_OPTS='--bind=ctrl-n:down,ctrl-p:up,ctrl-d:half-page-down,ctrl-u:half-page-up,alt-j:down,alt-k:up'
export GITHOOK_PRECOMMIT_STRICT_LINT=1
export SHDEPS_CONF_DIR="$HOME/.config/shdeps"

# Man pages from shdeps-managed tools. Guard against duplicate segments: unlike
# 90-path.sh's PATH, MANPATH is prepended here with no dedup, so nested shells of
# differing flavors (which re-source this file) would otherwise accumulate copies.
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
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | batcat -l man -p'"
elif command -v bat >/dev/null 2>&1; then
  export MANROFFOPT="-c"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# Ensure non-interactive bash subshells get the same env.d layer as interactive
# shells. BASH_ENV is sourced automatically by bash for every non-interactive
# invocation and is inherited by child processes.
export BASH_ENV="$HOME/.config/shell/env-noninteractive.sh"

# GitHub PAT for GitHub API callers. Avoids calling `gh auth token` at shell
# startup (which triggers D-Bus/keyring on headless hosts). Dot update seeds
# this file when possible; manual fallback:
#   gh auth token > ~/.config/gh/github-pat && chmod 600 ~/.config/gh/github-pat
if [ -f "$HOME/.config/gh/github-pat" ]; then
  # Keep the credential owner-only at rest (idempotent self-heal). This only
  # hardens the file; the token is still exported into the environment and
  # inherited by child processes — scoping that export is tracked separately.
  chmod 600 "$HOME/.config/gh/github-pat" 2>/dev/null || true
  read -r _DOT_GITHUB_PAT <"$HOME/.config/gh/github-pat" || true
  if [ -n "${_DOT_GITHUB_PAT:-}" ]; then
    export GH_TOKEN="${GH_TOKEN:-$_DOT_GITHUB_PAT}"
    export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
    export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
  fi
  unset _DOT_GITHUB_PAT
fi
