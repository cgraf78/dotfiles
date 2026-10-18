# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Install the system-wide sshd policy Termnav's nested SSH relay needs.
#
# `termnav ssh` hands the remote side its relay socket only through
# `SendEnv=TERMNAV_PARENT_RELAY`; a server without the matching `AcceptEnv`
# silently drops it and nested routing stops at the SSH boundary. Termnav owns
# the fragment (`share/termnav/sshd_config`), so dotfiles resolves it through
# shdeps instead of carrying a copy.
#
# The hook runs as root, or as the Android app user owning a Termux sshd
# installation, on a host with an `sshd_config.d` directory. A main config
# that never Includes that directory fails validation loudly rather than being
# guessed at.
#
# No serial barrier, although an overlay hook may also change and reload
# root's sshd config: this hook only renames an always-valid AcceptEnv fragment
# into place, so it can never fail the other hook's validation. The reverse
# overlap (validating while the other hook is mid-write) needs a fragment
# change in the same root run, rolls back cleanly, and the next update
# retries, which is cheaper than a barrier every update pays for.

_sshd_effective_uid() {
  printf '%s\n' "$EUID"
}

# Android's sshd belongs to the app user, not root. PREFIX alone must not
# authorize a non-root Linux run, nor redirect writes through a symlink.
_sshd_is_termux() {
  local target
  dot_hook_platform_match android || return 1
  [[ "${PREFIX:-}" == /* && "$PREFIX" != / ]] || return 1
  for target in "$PREFIX" "$PREFIX/etc" "$PREFIX/etc/ssh" \
    "$PREFIX/etc/ssh/sshd_config" "$PREFIX/etc/ssh/sshd_config.d"; do
    [[ -O "$target" && ! -L "$target" ]] || return 1
  done
  # The pending marker is opened before publication; refuse a pre-existing
  # redirect or foreign-owned fragment before any staging or truncation.
  for target in "$PREFIX/etc/ssh/sshd_config.d/60-termnav-relay.conf" \
    "$PREFIX/etc/ssh/.60-termnav-relay.reload-pending"; do
    [[ -e "$target" || -L "$target" ]] || continue
    [[ -f "$target" && -O "$target" && ! -L "$target" ]] || return 1
  done
}

_sshd_can_manage() {
  [[ "$(_sshd_effective_uid)" == 0 ]] || _sshd_is_termux
}

_sshd_config_root() {
  if dot_hook_platform_match android; then
    _sshd_is_termux || return 1
    printf '%s/etc/ssh\n' "${PREFIX%/}"
  else
    printf '%s\n' /etc/ssh
  fi
}

_sshd_fragment_source() {
  dot_shdeps_dep_file cgraf78/termnav share/termnav/sshd_config 2>/dev/null
}

_sshd_set_owner() {
  if dot_hook_platform_match android; then
    _sshd_is_termux || return 1
    # The app cannot chown to root. Newly staged files and pending markers
    # already belong to it; refuse an unexpected owner instead.
    [[ -O "$1" ]]
  else
    chown 0:0 "$1"
  fi
}

_sshd_ready() {
  sshd -t -f "$1" >/dev/null 2>&1
}

# Root copies this file from another repository on every unattended update, so
# bound what it may say: only AcceptEnv lines naming Termnav's own variables.
# Anything else (a typo, a compromised dependency) must never reach the system
# sshd config. The bound is a namespace rather than an exact line so Termnav can
# accept further TERMNAV_* variables without a lockstep dotfiles change.
_sshd_fragment_allowed() {
  awk '
    /^[[:space:]]*(#|$)/ { next }
    tolower($1) == "acceptenv" && NF > 1 {
      for (i = 2; i <= NF; i++) {
        if ($i !~ /^TERMNAV_[A-Z0-9_]+$/) bad = 1
        if ($i == "TERMNAV_PARENT_RELAY") found = 1
      }
      next
    }
    { bad = 1 }
    END { exit (bad || !found) }
  ' "$1"
}

# Syntax alone is not enough: a later fragment or Match block could shadow the
# directive, and a main config without the Include never loads it. Require the
# effective config to accept the variable. OpenSSH 10.5 prints effective keys
# in title case, hence the lowercase match.
_sshd_validate() {
  local main_config="$1" effective
  sshd -t -f "$main_config" || return 1
  effective=$(sshd -T -f "$main_config") || return 1
  awk '
    tolower($1) == "acceptenv" {
      for (i = 2; i <= NF; i++)
        if ($i == "TERMNAV_PARENT_RELAY") found = 1
    }
    END { exit !found }
  ' <<<"$effective"
}

# A stopped server reads the new fragment when it next starts, so having no
# active service to reload is success, not a pending activation.
_sshd_reload() {
  local unit service_dir pid_file pid

  if _sshd_is_termux; then
    # Use the canonical service rather than caller-controlled SVDIR. runsv's
    # PID file is a structured interface; `sv status` succeeds even when down.
    service_dir="${PREFIX%/}/var/service/sshd"
    pid_file="$service_dir/supervise/pid"
    [[ -e "$service_dir" ]] || return 0
    [[ -e "$service_dir/supervise" ]] || return 0
    [[ -O "$service_dir" && -O "$service_dir/supervise" &&
      ! -L "$service_dir/supervise" ]] || return 1
    [[ -e "$pid_file" ]] || return 0
    [[ -f "$pid_file" && -O "$pid_file" && ! -L "$pid_file" ]] || return 1
    IFS= read -r pid <"$pid_file" || return 1
    case "$pid" in
      '' | *[!0-9]*) return 1 ;;
      0) return 0 ;;
    esac
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 0
    command -v sv >/dev/null 2>&1 || return 1
    # HUP asks the listening sshd to reread policy while established session
    # children stay alive. The supervisor must never stop/start the service.
    sv hup "$service_dir"
    return $?
  fi

  if command -v systemctl >/dev/null 2>&1; then
    for unit in sshd.service ssh.service; do
      systemctl is-active --quiet "$unit" || continue
      systemctl reload "$unit"
      return $?
    done
  fi

  if command -v service >/dev/null 2>&1; then
    for unit in sshd ssh; do
      service "$unit" status >/dev/null 2>&1 || continue
      service "$unit" reload
      return $?
    done
  fi

  if command -v launchctl >/dev/null 2>&1 &&
    launchctl print system/com.openssh.sshd >/dev/null 2>&1; then
    launchctl kickstart -k system/com.openssh.sshd
    return $?
  fi

  return 0
}

_sshd_mark_pending() {
  : >"$1" || return 1
  chmod 0600 "$1" || return 1
  _sshd_set_owner "$1"
}

# Staging, backup, and pending-marker files live beside the main config, never
# inside sshd_config.d: macOS Includes `sshd_config.d/*` without a suffix, so
# any sibling there would be parsed as live server policy.
_sshd_install() {
  local source="$1" destination="$2" main_config="$3" pending="$4"
  local candidate backup="" had_destination=0 had_pending=0

  # A managed system path must never redirect a root write elsewhere.
  [[ ! -L "$destination" ]] || {
    dot_hook_warn "    warning: sshd merge: refusing symlink destination: $destination"
    return 1
  }
  [[ ! -e "$destination" || -f "$destination" ]] || {
    dot_hook_warn "    warning: sshd merge: refusing non-file destination: $destination"
    return 1
  }

  if [[ -f "$destination" ]] && dot_config_files_equal "$source" "$destination"; then
    [[ -f "$pending" ]] || return 0
    # A previous run changed the fragment but did not finish activating it,
    # possibly before validation ran. Revalidate what is live before reloading.
    _sshd_validate "$main_config" || {
      dot_hook_warn "    warning: sshd merge: $main_config rejected or did not load pending $destination"
      return 1
    }
    _sshd_reload || return 1
    rm -f "$pending"
    return 0
  fi

  dot_hook_log "  SSHD"
  dot_sibling_tmp_for "$main_config" || return 1
  candidate="$REPLY"
  cp "$source" "$candidate" || {
    rm -f "$candidate"
    return 1
  }
  chmod 0644 "$candidate" || {
    rm -f "$candidate"
    return 1
  }
  _sshd_set_owner "$candidate" || {
    rm -f "$candidate"
    return 1
  }

  if [[ -f "$destination" ]]; then
    dot_sibling_tmp_for "$main_config" || {
      rm -f "$candidate"
      return 1
    }
    backup="$REPLY"
    cp -p "$destination" "$backup" || {
      rm -f "$candidate" "$backup"
      return 1
    }
    had_destination=1
  fi

  # Mark activation pending before the live fragment changes, so a run killed
  # anywhere between here and a successful reload is revalidated and reloaded
  # by the next update even though the bytes then match.
  [[ -f "$pending" ]] && had_pending=1
  _sshd_mark_pending "$pending" || {
    rm -f "$candidate" "$backup"
    return 1
  }

  mv "$candidate" "$destination" || {
    rm -f "$candidate" "$backup"
    return 1
  }

  if ! _sshd_validate "$main_config"; then
    dot_hook_warn "    warning: sshd merge: $main_config rejected or did not load $destination — restoring previous state"
    if [[ "$had_destination" -eq 1 ]]; then
      mv "$backup" "$destination" || return 1
    else
      rm -f "$destination"
    fi
    # The restored state is exactly what existed before this run, including
    # whether it still awaited activation.
    [[ "$had_pending" -eq 1 ]] || rm -f "$pending"
    return 1
  fi
  rm -f "$backup"

  # A validated fragment remains installed when reload fails; the pending
  # marker makes a later update retry even when the bytes are unchanged.
  _sshd_reload || return 1
  rm -f "$pending"
}

merge() {
  _sshd_can_manage || return 0
  _dot_tool_present sshd || return 0

  local source root main_config include_dir
  # No Termnav install means nothing needs the relay variable.
  source="$(_sshd_fragment_source)" || return 0
  [[ -f "$source" ]] || return 0

  root="$(_sshd_config_root)" || return 0
  main_config="$root/sshd_config"
  include_dir="$root/sshd_config.d"
  [[ -f "$main_config" && -d "$include_dir" ]] || return 0
  # Never stack a change on a server config that is already broken.
  _sshd_ready "$main_config" || return 0

  _sshd_fragment_allowed "$source" || {
    dot_hook_warn "    warning: sshd merge: refusing unexpected directives in $source"
    return 1
  }

  _sshd_install "$source" "$include_dir/60-termnav-relay.conf" \
    "$main_config" "$root/.60-termnav-relay.reload-pending"
}
