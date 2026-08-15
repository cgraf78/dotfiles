# shellcheck shell=bash
# Install system-wide sshd policy needed by Termnav's nested SSH relay.

_sshd_effective_uid() {
  printf '%s\n' "$EUID"
}

_sshd_config_root() {
  printf '%s\n' /etc/ssh
}

_sshd_set_owner() {
  chown 0:0 "$1"
}

_sshd_ready() {
  sshd -t -f "$1" >/dev/null 2>&1
}

_sshd_validate() {
  local main_config="$1" effective
  sshd -t -f "$main_config" || return 1
  effective=$(sshd -T -f "$main_config") || return 1
  awk '
    $1 == "acceptenv" {
      for (i = 2; i <= NF; i++)
        if ($i == "TERMNAV_PARENT_RELAY") found = 1
    }
    END { exit !found }
  ' <<<"$effective"
}

_sshd_reload() {
  local unit

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

  printf 'sshd merge: no active ssh service found to reload\n' >&2
  return 1
}

_sshd_install() {
  local source="$1" destination="$2" main_config="$3"
  local candidate backup="" pending="${destination}.reload-pending"
  local had_destination=0

  # A managed system path must never redirect dot's root write elsewhere.
  [[ ! -L "$destination" ]] || {
    printf 'sshd merge: refusing symlink destination: %s\n' "$destination" >&2
    return 1
  }
  [[ ! -e "$destination" || -f "$destination" ]] || {
    printf 'sshd merge: refusing non-file destination: %s\n' "$destination" >&2
    return 1
  }

  if [[ -f "$destination" ]] && cmp -s "$source" "$destination"; then
    if [[ -f "$pending" ]]; then
      _sshd_reload || return 1
      rm -f "$pending"
    fi
    return 0
  fi

  _dot_sibling_tmp_for "$destination" || return 1
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
    _dot_sibling_tmp_for "$destination" || {
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

  mv "$candidate" "$destination" || {
    rm -f "$candidate" "$backup"
    return 1
  }

  if ! _sshd_validate "$main_config"; then
    if [[ "$had_destination" -eq 1 ]]; then
      mv "$backup" "$destination" || return 1
    else
      rm -f "$destination"
    fi
    return 1
  fi
  rm -f "$backup"

  # A validated fragment remains installed when reload fails. Record that
  # activation is pending so a later root update retries even when the source
  # bytes are unchanged.
  if ! _sshd_reload; then
    : >"$pending" || return 1
    chmod 0600 "$pending" || return 1
    _sshd_set_owner "$pending" || return 1
    return 1
  fi
  rm -f "$pending"
}

merge() {
  [[ "$(_sshd_effective_uid)" == 0 ]] || return 0
  _dot_tool_present sshd || return 0

  local source root main_config include_dir destination
  source="$(_merge_hook_source \
    sshd/sshd_config.d/60-termnav-relay.conf)"
  [[ -f "$source" ]] || return 0

  root="$(_sshd_config_root)"
  main_config="$root/sshd_config"
  include_dir="$root/sshd_config.d"
  [[ -f "$main_config" && -d "$include_dir" ]] || return 0
  _sshd_ready "$main_config" || return 0

  destination="$include_dir/60-termnav-relay.conf"
  _sshd_install "$source" "$destination" "$main_config"
}
