# shellcheck shell=bash
# shellcheck disable=SC2088  # tilde strings here are display text.
# dot doctor: shell startup behaviour.
#
# Instead of checking that startup files exist and mention the loader (core
# already reports tracked-file drift), start each shell flavor tools and
# terminals use and check that the shared loader actually ran:
#
#   bash login   ~/.bash_profile -> ~/.bashrc, as `bash -lc` reads them
#   bash -c      non-interactive bash through the BASH_ENV that ~/.bashrc
#                exports (env-noninteractive.sh, fill-only)
#   zsh -c       non-login, non-interactive zsh: ~/.zshenv (fill-only)
#   zsh login    ~/.zshenv (skipped for logins) and ~/.zprofile, as
#                `zsh -lc` reads them
#
# The login flavors are real login shells that source the user's login
# files in their real order but skip the host's system profile
# (/etc/profile, /etc/zprofile; zsh still reads /etc/zshenv, as every zsh
# does). Those are
# not dotfiles, and running them made the doctor write login history,
# start agents the worker supervisor then reports as leftovers, and pay
# hundreds of milliseconds per probe on some hosts.
#
# Each probe prints one line: the loader's shell-local marker
# (_SHELL_ENV_LOADED_PID, set to the loading shell's own PID and never
# exported, so an inherited value cannot fake it), its own PID, whether
# ~/.local/bin is on PATH, and bash's major version. Any other output fails
# the probe: startup text on stdout corrupts scp, rsync, and command
# substitution, and on stderr it corrupts every tool's output. The probes
# run in parallel with stdin closed, under a deadline where a timeout
# command exists, and each costs one shell startup.

# Probe body run by every flavor. Literal on purpose: each child expands its
# own variables. zsh has no BASH_VERSINFO, so its bash field stays empty.
# shellcheck disable=SC2016
_DR_SHELL_PROBE='case ":$PATH:" in *":$HOME/.local/bin:"*) _dr_lb=1 ;; *) _dr_lb=0 ;; esac; printf "dot-doctor-probe marker=%s pid=%s local_bin=%s bash=%s\n" "${_SHELL_ENV_LOADED_PID:-}" "$$" "$_dr_lb" "${BASH_VERSINFO[0]:-}"'

# Login-file sequences, in the order the shells read them for a login,
# non-interactive invocation (bash stops at the first readable file).
# shellcheck disable=SC2016
_DR_SHELL_BASH_LOGIN='for _dr_f in .bash_profile .bash_login .profile; do if [ -r "$HOME/$_dr_f" ]; then . "$HOME/$_dr_f"; break; fi; done'
# shellcheck disable=SC2016
_DR_SHELL_ZSH_LOGIN='for _dr_f in .zshenv .zprofile .zlogin; do [[ -r ${ZDOTDIR:-$HOME}/$_dr_f ]] && source "${ZDOTDIR:-$HOME}/$_dr_f"; done'

# Start one probe flavor by absolute shell path under the probe PATH (see
# _dr_check_shell), bounded by _DR_SHELL_RUN when a timeout command exists.
_dr_shell_probe_exec() {
  local flavor=$1 bash_env
  case $flavor in
    bash-login)
      # --login sets `login_shell` (so ~/.bashrc takes its authoritative
      # path), while --noprofile keeps bash from reading any profile itself.
      ${_DR_SHELL_RUN[@]+"${_DR_SHELL_RUN[@]}"} "$_DR_SHELL_BASH" --login --noprofile --norc \
        -c "$_DR_SHELL_BASH_LOGIN; $_DR_SHELL_PROBE"
      ;;
    bash-env)
      # The doctor worker strips BASH_ENV, so ask ~/.bashrc which file it
      # publishes, then start the real non-interactive child with only that
      # added. The asking shell is bare and reads nothing but ~/.bashrc; an
      # empty inherited BASH_ENV would otherwise survive the fill-only load.
      local query=0
      # shellcheck disable=SC2016 # The child expands its own variables.
      bash_env=$(BASH_ENV='' ${_DR_SHELL_RUN[@]+"${_DR_SHELL_RUN[@]}"} \
        "$_DR_SHELL_BASH" --noprofile --norc -c '
          unset BASH_ENV
          . "$HOME/.bashrc" >/dev/null 2>&1
          printf "%s" "${BASH_ENV:-}"
        ' 2>/dev/null) || query=$?
      # A query that timed out says nothing about BASH_ENV.
      if [[ $query == 124 || $query == 137 ]]; then
        return "$query"
      fi
      [[ -n $bash_env ]] || return 3
      BASH_ENV=$bash_env ${_DR_SHELL_RUN[@]+"${_DR_SHELL_RUN[@]}"} \
        "$_DR_SHELL_BASH" -c "$_DR_SHELL_PROBE"
      ;;
    zsh-env)
      ${_DR_SHELL_RUN[@]+"${_DR_SHELL_RUN[@]}"} "$_DR_SHELL_ZSH" -c "$_DR_SHELL_PROBE"
      ;;
    zsh-login)
      # -f skips the startup files zsh would read itself, apart from
      # /etc/zshenv; -o login makes the user's files see a login shell, as
      # `zsh -lc` would.
      ${_DR_SHELL_RUN[@]+"${_DR_SHELL_RUN[@]}"} "$_DR_SHELL_ZSH" -f -o login \
        -c "$_DR_SHELL_ZSH_LOGIN; $_DR_SHELL_PROBE"
      ;;
  esac
}

# Run one probe flavor; stdout, stderr, and the exit status land in
# $2.out, $2.err, and $2.status. Runs as a background job of the worker, so
# a failing probe must not trip errexit before its status is recorded.
_dr_shell_probe_run() {
  local rc=0
  PATH=$_DR_SHELL_PATH _dr_shell_probe_exec "$1" </dev/null >"$2.out" 2>"$2.err" ||
    rc=$?
  printf '%s\n' "$rc" >"$2.status"
}

# Report the first non-blank line of $1 via REPLY as one line of display
# text: the record format forbids tabs and line breaks in a detail, and
# terminal escapes do not belong in it.
_dr_shell_first_line() {
  local line
  REPLY=
  while IFS= read -r line; do
    [[ -n ${line//[[:space:]]/} ]] || continue
    REPLY=${line//[$'\t\r']/ }
    # Drop terminal escape sequences, then any stray escape characters.
    while [[ $REPLY =~ $'\e'\[[0-9\;?]*[A-Za-z] ]]; do
      REPLY=${REPLY/"${BASH_REMATCH[0]}"/}
    done
    REPLY=${REPLY//$'\e'/}
    REPLY=${REPLY:0:160}
    return 0
  done <<<"$1"
}

# Render one probe's verdict.
_dr_shell_probe_report() {
  local flavor=$1 base=$2 label repro status out err line noise=''
  local marker='' pid='' local_bin='' bash_major=''
  case $flavor in
    bash-login) label='bash login' repro="bash -lc :" ;;
    bash-env) label='bash -c (BASH_ENV)' repro="BASH_ENV=<value ~/.bashrc exports> bash -c :" ;;
    zsh-env) label='zsh -c' repro="zsh -c :" ;;
    zsh-login) label='zsh login' repro="zsh -lc :" ;;
  esac
  status=1 out='' err=''
  IFS= read -r status 2>/dev/null <"$base.status" || status=1
  IFS= read -r -d '' out 2>/dev/null <"$base.out" || true
  IFS= read -r -d '' err 2>/dev/null <"$base.err" || true

  if [[ $flavor == bash-env && $status == 3 ]]; then
    _dr_warn "$label startup not configured" \
      "~/.bashrc does not export BASH_ENV, so non-interactive bash skips env.d; run 'dot update'"
    return 0
  fi
  if [[ $status == 124 || $status == 137 ]]; then
    _dr_fail "$label startup timed out" \
      "a startup file waits on something; run '$repro' to see where"
    return 0
  fi
  if [[ -n ${err//[[:space:]]/} ]]; then
    _dr_shell_first_line "$err"
    _dr_fail "$label startup prints to stderr" \
      "$REPLY; non-interactive output must stay clean (try '$repro')"
    return 0
  fi
  while IFS= read -r line; do
    if [[ $line =~ ^dot-doctor-probe\ marker=([0-9]*)\ pid=([0-9]+)\ local_bin=([01])\ bash=([0-9]*)$ ]]; then
      marker=${BASH_REMATCH[1]}
      pid=${BASH_REMATCH[2]}
      local_bin=${BASH_REMATCH[3]}
      bash_major=${BASH_REMATCH[4]}
    elif [[ -n ${line//[[:space:]]/} && -z $noise ]]; then
      noise=$line
    fi
  done <<<"$out"
  if [[ -n $noise ]]; then
    _dr_shell_first_line "$noise"
    _dr_fail "$label startup prints to stdout" \
      "$REPLY; non-interactive output must stay clean (try '$repro')"
  elif [[ $status != 0 || -z $pid ]]; then
    _dr_fail "$label startup failed" "exit $status; run '$repro' to see why"
  elif [[ $marker != "$pid" ]]; then
    _dr_fail "$label does not load the shell environment" \
      "the shared loader did not run; check the startup files with 'dot status'"
  elif [[ $local_bin != 1 ]]; then
    _dr_fail "$label leaves ~/.local/bin off PATH" \
      "dot and its helper commands live there; check ~/.config/shell/env.d"
  else
    _dr_ok "$label loads the shell environment"
  fi
  # Scripts run `#!/usr/bin/env bash` with the first bash on PATH, which
  # core's runtime row does not cover (it picks the first Bash 4+). The
  # login probe always runs that same binary.
  if [[ $flavor == bash-login && -n $bash_major ]] && ((bash_major < 4)); then
    _dr_warn "first bash on PATH is version $bash_major" \
      "scripts using '/usr/bin/env bash' need Bash 4+; install a newer bash ahead of it on PATH"
  fi
}

_dr_check_shell() {
  _dr_section "Shell environment"

  local tmp flavor entry rest
  local -a flavors=()
  _DR_SHELL_BASH=$(type -P bash 2>/dev/null) || _DR_SHELL_BASH=
  _DR_SHELL_ZSH=$(type -P zsh 2>/dev/null) || _DR_SHELL_ZSH=
  if [[ -n $_DR_SHELL_BASH ]]; then
    flavors+=(bash-login bash-env)
  fi
  if [[ -n $_DR_SHELL_ZSH ]]; then
    flavors+=(zsh-env zsh-login)
  fi
  # Absolute path: the probe PATH below may no longer contain it.
  _DR_SHELL_RUN=()
  if entry=$(type -P timeout 2>/dev/null) || entry=$(type -P gtimeout 2>/dev/null); then
    _DR_SHELL_RUN=("$entry" -k 2 10)
  fi
  # Probe PATH: the inherited one minus ~/.local/bin, so "startup puts
  # ~/.local/bin on PATH" is something the probes prove rather than inherit
  # from the shell that ran `dot doctor`. Everything else stays, so startup
  # code finds its usual tools on every platform.
  _DR_SHELL_PATH=
  rest=${PATH:-}:
  while [[ -n $rest ]]; do
    entry=${rest%%:*}
    rest=${rest#*:}
    [[ -n $entry && $entry != "$HOME/.local/bin" && $entry != "$HOME/.local/bin/" ]] || continue
    _DR_SHELL_PATH+=${_DR_SHELL_PATH:+:}$entry
  done

  if ((${#flavors[@]} == 0)); then
    _dr_fail "bash not found on PATH" "dot and its scripts need Bash 4+ on PATH"
  elif tmp=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-shell.XXXXXX" 2>/dev/null); then
    for flavor in "${flavors[@]}"; do
      _dr_shell_probe_run "$flavor" "$tmp/$flavor" &
    done
    wait
    for flavor in "${flavors[@]}"; do
      _dr_shell_probe_report "$flavor" "$tmp/$flavor"
    done
    rm -rf "$tmp"
  else
    _dr_warn "shell startup unchecked" "could not create a temporary directory"
  fi
  if [[ -z $_DR_SHELL_ZSH ]]; then
    _dr_skip "zsh startup" "zsh not installed"
  fi

  # Report a vendor installer block in the thin loaders. Doctor is
  # diagnostics-only: the grok-rc merge hook strips it during `dot update`.
  local rc grok_rc='' grok_linked='' grok_open=''
  if dot_doctor_source shell-grok-rc.sh; then
    while IFS= read -r rc; do
      dot_grok_rc_has_block "$rc" || continue
      # The hook never replaces a symlinked loader, and refuses a block with
      # no end marker, so `dot update` would clear neither.
      if [[ -L $rc ]]; then
        grok_linked+=${grok_linked:+, }$(_dr_tilde "$rc")
      elif ! dot_grok_rc_filter "$rc" >/dev/null 2>&1; then
        grok_open+=${grok_open:+, }$(_dr_tilde "$rc")
      else
        grok_rc+=${grok_rc:+, }$(_dr_tilde "$rc")
      fi
    done < <(dot_grok_rc_files)
    if [[ -n $grok_rc ]]; then
      _dr_warn "Grok installer block in $grok_rc" \
        "cron updates skip while a tracked loader is dirty; run 'dot update' to strip it"
    fi
    if [[ -n $grok_linked ]]; then
      _dr_warn "Grok installer block in $grok_linked" \
        "the loader is a symlink, which dot update leaves alone; remove the block by hand"
    fi
    if [[ -n $grok_open ]]; then
      _dr_warn "unterminated Grok installer block in $grok_open" \
        "the block has no end marker, so dot update leaves it alone; edit the file by hand"
    fi
  else
    _dr_skip "Grok installer block unchecked" "shell-grok-rc.sh unavailable"
  fi
}
