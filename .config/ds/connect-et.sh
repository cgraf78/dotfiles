# shellcheck shell=bash
# ds connect method: et — Eternal Terminal via x2ssh
#
# ET starts an interactive shell that triggers .bashrc auto-attach BEFORE
# running any -c command.  To direct auto-attach to the right session, we
# write an attach-next state file via a quick SSH call first, then connect
# with ET (no -c).  The attach-next check in .bashrc fires before the
# standard auto-attach and creates/joins the correct session directly.
_connect_et() {
    local host="$1" cmd="$2" session="${3:-ds}" action="${4:-session}" ds_args="${5:-}"
    case "$action" in
        session)
            # Write attach-next so auto-attach joins the right session
            ssh "$host" "mkdir -p \"\$HOME/.local/state/ds\" && printf '%s' '$ds_args' > \"\$HOME/.local/state/ds/attach-next\""
            # ET connects — auto-attach reads target, no spurious "ds"
            exec x2ssh -et "$host"
            ;;
        *)
            # list/kill don't need a persistent connection
            exec ssh "$host" -t "$cmd"
            ;;
    esac
}
