# shellcheck shell=bash
# Activate Termnav before later interactive integrations and user commands.
#
# Termnav owns the inherited SSH shim, terminal classification, and prompt
# publication behavior. Dotfiles deliberately knows only the provider asset:
# shdeps remains the single authority for choosing a development checkout or
# installed dependency. Missing dependencies stay non-fatal during shell
# startup; `dot doctor` reports the installation problem without making a
# partially updated machine unable to open a recovery shell.

# shellcheck source=../../../.local/lib/dotfiles/shdeps-assets.sh
. "$HOME/.local/lib/dotfiles/shdeps-assets.sh"

# Termnav owns the portable MCP interface; dotfiles owns the generated token's
# location. Keep it below the same absolute XDG state root used by the merge
# hook, and leave explicit caller overrides intact for diagnostics or alternate
# installations.
case "${XDG_STATE_HOME:-}" in
  /*) _dot_termnav_state_home="$XDG_STATE_HOME" ;;
  *) _dot_termnav_state_home="$HOME/.local/state" ;;
esac
if [[ -z "${TERMNAV_VSCODE_MCP_TOKEN_FILE:-}" ]]; then
  export TERMNAV_VSCODE_MCP_TOKEN_FILE="$_dot_termnav_state_home/dot/vscode-mcp-auth-token"
fi
unset _dot_termnav_state_home

dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh 2>/dev/null || true
