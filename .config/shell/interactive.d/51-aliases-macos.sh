# shellcheck shell=bash
# macOS-specific aliases and functions. Depends on _UNAME from env.d.

[[ "$_UNAME" == "Darwin" ]] || return 0

# Drop any pre-existing `sc` alias so the sc() function below parses cleanly.
# Scoped to Darwin: sc() is only defined here, so there's no need to touch a
# user's `sc` alias on Linux/WSL.
unalias sc 2>/dev/null || true

# Native ls coloring (eza takes precedence in 50-aliases.sh if installed).
command -v eza >/dev/null 2>&1 || alias ls='ls -G'

sc() {
  local dir="$HOME/gdrive/img"
  [[ -d "$dir" ]] || dir="$HOME/Desktop"
  screencapture -i "$dir/screen_$(date +%Y%m%d_%H%M%S).png"
}
