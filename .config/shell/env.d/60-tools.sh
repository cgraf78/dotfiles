# shellcheck shell=bash
# Tool environment bootstraps. Final PATH priority is owned by 90-path.sh.

# shellcheck disable=SC1091  # optional local tool bootstrap script
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
true
