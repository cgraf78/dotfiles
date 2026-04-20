# shellcheck shell=bash
# Core environment: platform cache, exports.

_UNAME="$(uname -s)"

# Cache expensive shell-init output (brew shellenv, fzf/zoxide/atuin/direnv
# init) to ~/.cache/shell/ and source the cache on subsequent startups.
# Each cached init forks a subprocess per shell; for 5-6 tools that adds
# up to ~100-200ms per new shell/tmux pane/ssh login.
#
# Invalidation:
#   - ~/.config/shell edited: dir mtime comparison, per _cached_init call
#   - `dot update` runs: _finalize_update purges the whole cache dir
#   - Weekly TTL: first _cached_init per shell purges files older than 7d
#   - Manual: rm -rf ~/.cache/shell
_cached_init() {
  # Amortized per-shell: one `find` fork on the first _cached_init call.
  if [[ -z "${__shell_cache_ttl_checked:-}" ]]; then
    __shell_cache_ttl_checked=1
    [[ -d "$HOME/.cache/shell" ]] &&
      find "$HOME/.cache/shell" -maxdepth 1 -name '*.sh' -mtime +7 -delete 2>/dev/null
  fi
  local name="$1"
  shift
  local cache="$HOME/.cache/shell/${name}.sh"
  if [[ ! -f "$cache" || "$HOME/.config/shell" -nt "$cache" ]]; then
    [[ -d "${cache%/*}" ]] || mkdir -p "${cache%/*}"
    # shellcheck disable=SC2294  # caller-controlled command, may include pipelines
    eval "$@" >"$cache" 2>/dev/null
  fi
  # shellcheck disable=SC1090  # cache path resolved at runtime
  source "$cache"
}

export EDITOR=nvim
export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-claude}"
export DS_CHAT_CHATBOT="${DS_CHAT_CHATBOT:-argus}"
export DS_UPTERM_PRIVATE_KEY="$HOME/.ssh/argus_github_ed25519"
export DS_SSH_AUTO_ATTACH=ds
export PHOTOCAD_ENV_FILE=/var/lib/photocad/.env
export PHOTOCAD_LIVE_TEST_ENV_FILE=~/.config/photocad/live-test-env
export NVIM_COLORSCHEME=night-owl
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
export SHDEPS_CONF_DIR="$HOME/.config/shdeps"

# Man pages from shdeps-managed tools
export MANPATH="$HOME/.local/share/man:${MANPATH:-}"

# GitHub PAT for Claude Code's GitHub MCP server. Avoids calling `gh auth token`
# at shell startup (which triggers D-Bus/keyring on headless hosts).
# To create: gh auth token > ~/.config/gh/github-pat && chmod 600 ~/.config/gh/github-pat
[ -f "$HOME/.config/gh/github-pat" ] && {
  read -r GITHUB_PERSONAL_ACCESS_TOKEN <"$HOME/.config/gh/github-pat" &&
    export GITHUB_PERSONAL_ACCESS_TOKEN
}
