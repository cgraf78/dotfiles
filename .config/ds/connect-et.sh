# shellcheck shell=bash
# ds connect method: et — Eternal Terminal via x2ssh
_connect_et() { exec x2ssh -et "$1" -c "$2" --noexit; }
