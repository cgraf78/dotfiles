# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Reload the running default tmux server after dot has updated its config.
#
# Explicitly select the default socket even from a pane on a named server.
# A scheduled `dot update` never starts a server.
#
# The stamp ties the config path and checksums to the server instance
# that loaded them. A replacement server must reload even if the config
# is unchanged. Unrelated updates leave runtime options alone.

_tmux_hook_stamp_file() {
  local base=${XDG_CACHE_HOME:-}
  case $base in
    /*) ;;
    *) base=$HOME/.cache ;;
  esac
  printf '%s\n' "$base/dot/merge-tmux.stamp"
}

# Print the config fingerprint (config path plus one checksum line per
# input), or fail. Any unreadable input fails closed into a reload.
_tmux_hook_fingerprint() {
  local config=$1 conf_dir=$2 sum file fp
  command -v cksum >/dev/null 2>&1 || return 1
  sum=$(cksum <"$config" 2>/dev/null) || return 1
  fp="path=$config"$'\n'"$sum $config"
  for file in "$conf_dir"/*.conf; do
    [[ -f $file ]] || continue
    sum=$(cksum <"$file" 2>/dev/null) || return 1
    fp+=$'\n'"$sum $file"
  done
  printf '%s\n' "$fp"
}

# Succeed when every fingerprint input is older than the stamp file.
# Pure recency: content is compared separately by the caller.
_tmux_hook_inputs_older() {
  local stamp=$1 config=$2 conf_dir=$3 file
  [[ $config -ot $stamp ]] || return 1
  for file in "$conf_dir"/*.conf; do
    [[ -f $file ]] || continue
    [[ $file -ot $stamp ]] || return 1
  done
  return 0
}

merge() {
  _dot_tool_present tmux || return 0
  local config="$HOME/.config/tmux/tmux.conf"
  local conf_dir="$HOME/.config/tmux/conf.d" stamp fp fresh stored tmp
  local server_format='#{socket_path}:#{pid}:#{start_time}' server loaded_server

  [[ -r "$config" ]] || return 0
  # Ask for a server before applying the account guard, so the guard warns
  # only when it actually withholds a reload. A disposable HOME (CI fixtures,
  # `HOME=... dot update`) usually has no server, and then there is nothing
  # to protect. `has-session` is a client query: it never starts a server,
  # reads no config, and creates nothing beyond tmux's own per-uid socket
  # directory. With an explicit socket name it honors TMUX_TMPDIR and the uid
  # instead of inheriting the socket in TMUX. Test mode skips this probe
  # because the account guard must supply the test double first.
  if [[ "${DOT_TEST:-0}" != "1" ]] &&
    ! command tmux -N -L default has-session >/dev/null 2>&1; then
    return 0
  fi
  _dot_account_scoped_command \
    "tmux merge" tmux "${DOT_TEST_TMUX:-}" || return 0
  local -a tmux_default=("$REPLY" -N -L default)
  server=$(
    "${tmux_default[@]}" has-session \; display-message -p "$server_format" 2>/dev/null
  ) || return 0

  stamp=$(_tmux_hook_stamp_file)
  fp=$(_tmux_hook_fingerprint "$config" "$conf_dir") 2>/dev/null || fp=
  if [[ -f $stamp && -r $stamp && -n $server && -n $fp ]] &&
    _tmux_hook_inputs_older "$stamp" "$config" "$conf_dir" &&
    stored=$(cat -- "$stamp" 2>/dev/null) &&
    [[ $stored == "$server"$'\n'"$fp" ]]; then
    return 0
  fi

  dot_hook_log "  tmux"
  "${tmux_default[@]}" source-file "$config" || return $?
  # A config edit or server restart racing the reload invalidates the proof.
  # Leave the previous stamp in place so the next update tries again.
  fresh=$(_tmux_hook_fingerprint "$config" "$conf_dir") 2>/dev/null || return 0
  [[ $fresh == "$fp" ]] || return 0
  loaded_server=$("${tmux_default[@]}" display-message -p "$server_format" 2>/dev/null) ||
    return 0
  [[ -n $server && $loaded_server == "$server" ]] || return 0
  mkdir -p "${stamp%/*}" 2>/dev/null || return 0
  if tmp=$(mktemp "${stamp}.tmp.XXXXXX" 2>/dev/null) &&
    printf '%s\n' "$server" "$fresh" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$stamp" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  return 0
}
