# shellcheck shell=bash
# Core environment: platform cache, exports.

_UNAME="$(uname -s)"

export EDITOR=nvim
export DS_DEV_CHATBOT="${DS_DEV_CHATBOT:-claude}"
export DS_CHAT_CHATBOT="${DS_CHAT_CHATBOT:-argus}"
export DS_UPTERM_PRIVATE_KEY="$HOME/.ssh/argus_github_ed25519"
export DS_SSH_AUTO_ATTACH=ds
export PHOTOCAD_ENV_FILE=/var/lib/photocad/.env
export PHOTOCAD_LIVE_TEST_ENV_FILE=~/.config/photocad/live-test-env
export NVIM_COLORSCHEME=night-owl
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"

# GitHub PAT for Claude Code's GitHub MCP server. Avoids calling `gh auth token`
# at shell startup (which triggers D-Bus/keyring on headless hosts).
# To create: gh auth token > ~/.config/gh/github-pat && chmod 600 ~/.config/gh/github-pat
[ -f "$HOME/.config/gh/github-pat" ] && {
  read -r GITHUB_PERSONAL_ACCESS_TOKEN <"$HOME/.config/gh/github-pat" &&
    export GITHUB_PERSONAL_ACCESS_TOKEN
}
