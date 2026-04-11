# shellcheck shell=bash
# ds profile: argus — single window running the Argus chatbot
_profile_argus() {
  local session="$1"
  tmux rename-window -t "$session:1" "argus"
  tmux send-keys -t "$session:1" "argus" C-m
}
