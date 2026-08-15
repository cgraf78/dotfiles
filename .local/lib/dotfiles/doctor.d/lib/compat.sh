# shellcheck shell=bash
# Client-owned doctor compatibility for application checks moved out of the
# standalone coordinator. All result publication goes through doctor API v1.

dot_doctor_source doctor.d/lib/shdeps-assets.sh || return

_dr_section() { dot_doctor_section "$@"; }
_dr_ok() { dot_doctor_ok "$@"; }
_dr_warn() { dot_doctor_warn "$@"; }
_dr_fail() { dot_doctor_fail "$@"; }
_dr_skip() { dot_doctor_skip "$@"; }
_dr_tilde() { dot_doctor_display_path "$@"; }

_merge_hook_family() {
  printf '%s/%s\n' "$HOME/.config/dot/merge-hooks.d" "$1"
}

# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOT_SHELL_ENV_DIR=$HOME/.config/shell/env.d
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOT_SHELL_INTERACTIVE_DIR=$HOME/.config/shell/interactive.d
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
DOTFILES=${DOT_CLIENT_GIT_DIR:-$HOME/.dotfiles}
# shellcheck disable=SC2034 # Consumed dynamically by sourced doctor modules.
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"

_dr_physical_path() {
  local path=$1 directory base
  while [[ $path != / && $path == */ ]]; do
    path=${path%/}
  done
  case $path in
    /)
      directory=/
      base=/
      ;;
    */*)
      directory=${path%/*}
      base=${path##*/}
      [[ -n $directory ]] || directory=/
      ;;
    *)
      directory=.
      base=$path
      ;;
  esac
  [[ -d $directory ]] || return 1
  directory=$(cd "$directory" && pwd -P) || return 1
  printf '%s/%s\n' "$directory" "$base"
}

_dr_symlink_target_path() {
  local link=$1 target link_directory
  target=$(readlink "$link") || return 1
  case $target in
    /*) _dr_physical_path "$target" ;;
    *)
      case $link in
        */*)
          link_directory=${link%/*}
          [[ -n $link_directory ]] || link_directory=/
          ;;
        *) link_directory=. ;;
      esac
      _dr_physical_path "$link_directory/$target"
      ;;
  esac
}

_dr_symlink_points_to() {
  local link=$1 expected=$2 actual expected_physical
  [[ -e $expected ]] || return 1
  actual=$(_dr_symlink_target_path "$link") || return 1
  expected_physical=$(_dr_physical_path "$expected") || return 1
  [[ $actual == "$expected_physical" ]]
}

_dr_is_dotfiles_checkout() {
  local root home_real root_real
  root=$(git -C "$HOME" rev-parse --show-toplevel 2>/dev/null) || return 1
  home_real=$(cd "$HOME" && pwd -P) || return 1
  root_real=$(cd "$root" && pwd -P) || return 1
  [[ $root_real == "$home_real" ]]
}
