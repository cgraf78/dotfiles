# shellcheck shell=bash
# ds connect method: et — Eternal Terminal via x2ssh
#
# ET starts an interactive shell that triggers .bashrc auto-attach before
# running any -c command.  To avoid bouncing through a spurious default "ds"
# session, we use -c to write an attach-next state file and then exec into a
# login shell.  The attach-next check in .bashrc (which runs even inside tmux)
# reads the file and creates/joins the right session.  The momentary "ds"
# session auto-cleans when its window process exits.
# Single connection — one yubikey tap.
_connect_et() {
    local host="$1" cmd="$2" session="${3:-ds}" action="${4:-session}" ds_args="${5:-}"
    case "$action" in
        session)
            # Write ds args for auto-attach, then start a login shell.
            # The attach-next check in .bashrc reads the file and runs:
            #   exec ds <ds_args>
            local setup="mkdir -p \"\$HOME/.local/state/ds\" && printf '%s' '$ds_args' > \"\$HOME/.local/state/ds/attach-next\" && exec bash -l"
            exec x2ssh -et "$host" -c "$setup"
            ;;
        *)
            # list/kill don't need a persistent connection
            exec ssh "$host" -t "$cmd"
            ;;
    esac
}
