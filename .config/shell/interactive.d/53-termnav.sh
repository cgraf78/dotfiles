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

dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh 2>/dev/null || true
