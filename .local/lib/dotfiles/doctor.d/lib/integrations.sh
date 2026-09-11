# shellcheck shell=bash
# dot doctor: always-active shell integration checks.
#
# The termnav verdict probes the provider asset directly: resolve
# `cgraf78/termnav share/termnav/shell.sh` through the shdeps adapter
# and source only it in a minimal shell. A full interactive boot costs
# two shells and ~750ms, yet the verdict depends solely on whether the
# asset loads -- no other interactive file sets or clears the marker --
# so the narrow probe reports identical verdicts. The temp cache, the
# zsh presence gate, and every message stay exactly as before.
# Known exotic-setup edge: the old probe inherited env.d-built PATH
# (~/bin, mise shims, homebrew...); the narrow probe sees ambient PATH
# plus the adapter fallbacks, so a shdeps reachable only via an
# env-added dir would flip ok to warn. Standard installs resolve via
# the ~/.local/bin fallback.

_dr_check_shell_integrations() {
  _dr_section "Shell integrations"

  local cache output shell_name
  for shell_name in bash zsh; do
    if [[ $shell_name == zsh ]] && ! command -v zsh >/dev/null 2>&1; then
      _dr_skip "termnav zsh integration" "zsh not installed"
      continue
    fi

    cache=$(mktemp -d 2>/dev/null || mktemp -d -t dot-doctor-shell) || {
      _dr_warn "termnav $shell_name integration unchecked" \
        "could not create temp cache"
      continue
    }

    if [[ $shell_name == bash ]]; then
      output=$(XDG_CACHE_HOME="$cache" bash --noprofile --norc -c '
        . "$HOME/.local/lib/dotfiles/shdeps-assets.sh"
        dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh
        printf "termnav=%s\n" "${TERMNAV_SHELL_LOADED:-0}"
      ' 2>/dev/null || true)
    else
      output=$(XDG_CACHE_HOME="$cache" zsh -f -c '
        . "$HOME/.local/lib/dotfiles/shdeps-assets.sh"
        dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh
        print -r -- "termnav=${TERMNAV_SHELL_LOADED:-0}"
      ' 2>/dev/null || true)
    fi

    if [[ $output == *"termnav=1"* ]]; then
      _dr_ok "termnav $shell_name integration"
    else
      _dr_warn "termnav $shell_name integration unavailable" \
        "interactive $shell_name did not load termnav shell integration"
    fi
    rm -rf "$cache"
  done
}
