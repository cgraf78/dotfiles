# shellcheck shell=bash
# Post-install hook for vimrc.

post() {
  local vimrc_dir="$HOME/.local/share/vimrc"
  [[ -f "$vimrc_dir/install_awesome_parameterized.sh" ]] || return 0
  bash "$vimrc_dir/install_awesome_parameterized.sh" "$vimrc_dir" "$(whoami)" >/dev/null ||
    shdeps_warn "  warning: vimrc install script failed"
}
