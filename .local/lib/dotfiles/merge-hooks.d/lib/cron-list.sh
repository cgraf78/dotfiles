# shellcheck shell=bash
# List the user crontab and say why when it cannot be listed.
#
# Shared by the cron merge hook and `dot doctor`, so both agree on what "no
# crontab yet" means: the hook must replace the crontab only when it really
# read it (or there was none), never after a listing that failed, and the
# doctor must not advise `dot update` where crontab cannot be used at all.
# Plain Bash with no hook or doctor API, so either runtime can source it.

# List the user crontab with CMD (crontab or its test double), running it
# once and keeping its streams apart without a temporary file: its output
# goes to REPLY (trailing newlines dropped, as $(...) drops them; empty
# unless it succeeded) and the first non-blank line of its error message
# to _CRON_LIST_ERR. Returns 0 when it listed, 1 when the account simply
# has no crontab yet, and 2 when the listing failed: crontab cannot be used
# here (cron.allow or cron.deny, PAM, a binary that lost its setuid or
# setgid bit, or one that cannot run at all) or it failed for some other,
# possibly transient, reason.
#
# crontab exits 1 both for no crontab and for a refusal, so only its message
# tells them apart: Vixie, cronie, and the BSD and macOS crontabs say "no
# crontab for USER" (matched as "no crontab"); BusyBox reports the missing
# spool file as "No such file or directory". LC_ALL=C keeps those messages
# untranslated. Any other message or exit status (126 and 127 when crontab
# cannot run) is a failure, the safe side for both callers.
_CRON_LIST_ERR=
_cron_list() {
  local sep=$'\x1f''dot-crontab-list'$'\x1f' captured err status line
  # crontab's stdout goes straight to the outer capture (fd 3), its stderr
  # to the inner one; the status and message follow the separator.
  captured=$(
    {
      if err=$(LC_ALL=C "$1" -l 2>&1 >&3 3>&-); then
        status=0
      else
        status=$?
      fi
    } 3>&1
    printf '%s%s\n%s' "$sep" "$status" "$err"
  )
  REPLY=${captured%"$sep"*}
  captured=${captured##*"$sep"}
  status=${captured%%$'\n'*}
  # $(...) dropped the newline after the status when there is no message.
  err=
  [[ $captured != *$'\n'* ]] || err=${captured#*$'\n'}
  _CRON_LIST_ERR=
  while IFS= read -r line; do
    [[ -z ${line//[[:space:]]/} ]] || {
      _CRON_LIST_ERR=${line//[[:cntrl:]]/ }
      break
    }
  done <<<"$err"
  if [[ $status == 0 ]]; then
    while [[ $REPLY == *$'\n' ]]; do
      REPLY=${REPLY%$'\n'}
    done
    return 0
  fi
  REPLY=
  [[ -n $_CRON_LIST_ERR ]] || _CRON_LIST_ERR="crontab -l exited $status"
  if [[ $status == 1 ]]; then
    case $err in
      *[Nn]'o crontab'* | *'No such file or directory'*) return 1 ;;
    esac
  fi
  return 2
}
