# ds profile: orc — orc in top pane, bash below
_layout_orc() {
    local session="$1" dir="$3"
    tmux rename-window -t "$session:1" "orc"
    tmux send-keys -t "$session:1" "orc --new" C-m
    tmux split-window -v -t "$session:1" -c "$dir"
}
