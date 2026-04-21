# shellcheck shell=bash
# ds profile: vimdev — claude (top-left), terminal (bottom-left), vim (right)
_profile_vimdev() {
  local session="$1"
  tmux rename-window -t "$session:1" "vimdev"

  # Right pane: vim
  tmux split-window -h -t "$session:1"
  tmux send-keys -t "$session:1.2" "nvim" C-m

  # Split left column: claude on top, terminal below
  tmux split-window -v -t "$session:1.1"
  tmux send-keys -t "$session:1.1" "claude" C-m

  # Focus the terminal pane
  tmux select-pane -t "$session:1.3"
}
