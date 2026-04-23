# shellcheck shell=bash
# macOS-specific aliases and functions. Depends on _UNAME from env.d.

# Unconditionally drop any pre-existing `sc` alias so our function
# definition below parses cleanly and to match the pre-split behavior
# (the original did this outside the Darwin branch as a defensive step).
unalias sc 2>/dev/null || true

[[ "$_UNAME" == "Darwin" ]] || return 0

# Native ls coloring (eza takes precedence in 50-aliases.sh if installed).
command -v eza >/dev/null 2>&1 || alias ls='ls -G'

sc() {
  if [[ ! -d ~/gdrive/img ]]; then
    echo "error: ~/gdrive/img does not exist" >&2
    return 1
  fi
  screencapture -i ~/gdrive/img/"screen_$(date +%Y%m%d_%H%M%S).png"
}
