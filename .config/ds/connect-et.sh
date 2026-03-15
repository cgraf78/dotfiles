# shellcheck shell=bash
# ds connect method: et — Eternal Terminal via x2ssh
#
# ET starts an interactive shell that triggers .bashrc auto-attach BEFORE
# running any -c command.  To direct auto-attach to the right session, we
# set LC_DS_ATTACH with the desired ds args.  SSH forwards LC_* variables
# automatically, so auto-attach reads it and creates/joins the correct
# session directly.  Single connection — one yubikey tap.
_connect_et() {
    local host="$1" cmd="$2" session="${3:-ds}" action="${4:-session}" ds_args="${5:-}"
    case "$action" in
        session)
            export LC_DS_ATTACH="$ds_args"
            exec x2ssh -et "$host"
            ;;
        *)
            # list/kill don't need a persistent connection
            exec ssh "$host" -t "$cmd"
            ;;
    esac
}
