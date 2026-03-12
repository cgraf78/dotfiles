# ds profile: dev — chatbot in top pane, bash below, separate bash window
_profile_dev() {
    local session="$1" chatbot="$2" dir="$3"
    tmux rename-window -t "$session:1" "$chatbot"
    tmux send-keys -t "$session:1" "$chatbot" C-m
    tmux split-window -v -t "$session:1" -c "$dir"
    tmux new-window -t "$session" -n bash -c "$dir"
    tmux select-window -t "$session:1"
}
