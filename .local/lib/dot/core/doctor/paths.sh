# shellcheck shell=bash
# dot doctor: Paths checks.
#
# shellcheck disable=SC2088  # tilde strings here are display text.

_dr_physical_path() {
  local path="$1"
  local dir base
  dir=$(dirname "$path")
  base=$(basename "$path")
  [[ -d "$dir" ]] || return 1
  dir=$(cd "$dir" && pwd -P) || return 1
  printf '%s/%s\n' "$dir" "$base"
}
_dr_symlink_target_path() {
  local link="$1"
  local target
  target=$(readlink "$link") || return 1
  case "$target" in
    /*) _dr_physical_path "$target" ;;
    *) _dr_physical_path "$(dirname "$link")/$target" ;;
  esac
}
_dr_symlink_points_to() {
  local link="$1" expected="$2"
  local actual expected_physical
  [[ -e "$expected" ]] || return 1
  actual=$(_dr_symlink_target_path "$link") || return 1
  expected_physical=$(_dr_physical_path "$expected") || return 1
  [[ "$actual" == "$expected_physical" ]]
}
_dr_tilde() {
  local p="$1"
  case "$p" in
    "$HOME") echo "~" ;;
    "$HOME"/*) echo "~/${p#"$HOME"/}" ;;
    *) echo "$p" ;;
  esac
}
