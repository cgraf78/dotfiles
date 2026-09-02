# shellcheck shell=bash
# dot doctor: always-active shell integration checks.

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
        . "$HOME/.local/lib/dotfiles/shell-loader.sh"
        _shell_load_env bash
        _shell_source_dir "$HOME/.config/shell/interactive.d" bash
        printf "termnav=%s\n" "${TERMNAV_SHELL_LOADED:-0}"
      ' 2>/dev/null || true)
    else
      output=$(XDG_CACHE_HOME="$cache" zsh -f -c '
        . "$HOME/.local/lib/dotfiles/shell-loader.sh"
        _shell_load_env zsh
        _shell_source_dir "$HOME/.config/shell/interactive.d" zsh
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
