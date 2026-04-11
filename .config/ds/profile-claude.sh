# shellcheck shell=bash
# ds profile: claude — single window running Claude Code
_profile_claude() {
  local session="$1"
  tmux rename-window -t "$session:1" "claude"
  tmux send-keys -t "$session:1" "claude" C-m
}
