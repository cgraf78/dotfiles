#!/usr/bin/env bash
# Shared presentation helpers for dot CLIs.
#
# Keep common boxes here so commands like `dot doctor` and `dot-test` do not
# drift in visual treatment while still letting callers own their command-
# specific pass/fail content.

_dot_ui_color_hex() {
  case "$1" in
    green) printf '#3fb950' ;;
    red) printf '#f85149' ;;
    yellow) printf '#d29922' ;;
    magenta) printf '#bc8cff' ;;
    dim) printf '#8b949e' ;;
    *) printf '%s' "$1" ;;
  esac
}

_dot_ui_hex_to_rgb() {
  local hex="${1#\#}"
  printf '%d;%d;%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

_dot_ui_has_gum() {
  local gum_bin
  gum_bin=$(type -P gum 2>/dev/null) || return 1

  # `command -v` only proves that a name resolves. Some platform packages can
  # leave an executable that starts but cannot parse a subcommand, which would
  # otherwise leak Gum's usage error into every styled dot command.
  [[ -x "$gum_bin" ]] || return 1
  "$gum_bin" style --help >/dev/null 2>&1
}

_dot_ui_title() {
  if _dot_ui_has_gum; then
    # This is the canonical dot command title treatment. Keep it byte-for-byte
    # aligned with `dot doctor`'s historical look: gum palette 212, normal
    # border, horizontal padding, and bottom margin.
    gum style --bold --foreground 212 --border normal --padding '0 2' "$*"
  elif [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    printf '\n\033[1m%s\033[0m\n\n' "$*"
  else
    printf '\n%s\n\n' "$*"
  fi
}

_dot_ui_summary_box() {
  local color="$1"
  shift
  local hex
  hex=$(_dot_ui_color_hex "$color")
  if _dot_ui_has_gum; then
    # Match `dot doctor`: the box border stays the terminal/default color,
    # while the summary text carries the semantic pass/warn/fail color.
    gum style --bold --foreground "$hex" --border rounded --padding '0 2' "$*"
  elif [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    local rgb
    rgb=$(_dot_ui_hex_to_rgb "$hex")
    printf '════════════════════════════════\n'
    printf '\033[1;38;2;%sm%s\033[0m\n' "$rgb" "$*"
    printf '════════════════════════════════\n'
  else
    printf '════════════════════════════════\n'
    printf '%s\n' "$*"
    printf '════════════════════════════════\n'
  fi
}
