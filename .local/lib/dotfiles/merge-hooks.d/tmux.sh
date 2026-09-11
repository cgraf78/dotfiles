# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Reload the running default tmux server after dot has updated its config.
#
# `tmux source-file` without a socket target deliberately follows tmux's normal
# client contract: it updates the user's default server and does not create one
# just because a scheduled `dot update` ran.
#
# The ~500ms reload is skipped when the server already runs this exact
# config: the stamp records the config path plus checksums of the config
# and every conf.d include, and a reload happens unless all inputs are
# older than the stamp with matching checksums. Only a successful
# reload writes the stamp, so a failed reload, a config change, a new
# include, or a missing server all behave exactly as before. Runtime
# option drift is no longer reset by unrelated updates: only a config
# change reloads.

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
  local config="$HOME/.config/tmux/tmux.conf" tmux_command
  local conf_dir="$HOME/.config/tmux/conf.d" stamp fp fresh stored tmp

  [[ -r "$config" ]] || return 0
  _dot_account_scoped_command \
    "tmux merge" tmux "${DOT_TEST_TMUX:-}" || return 0
  tmux_command="$REPLY"
  "$tmux_command" has-session >/dev/null 2>&1 || return 0

  stamp=$(_tmux_hook_stamp_file)
  fp=$(_tmux_hook_fingerprint "$config" "$conf_dir") 2>/dev/null || fp=
  if [[ -f $stamp && -r $stamp && -n $fp ]] &&
    _tmux_hook_inputs_older "$stamp" "$config" "$conf_dir" &&
    stored=$(cat -- "$stamp" 2>/dev/null) &&
    [[ $fp == "$stored" ]]; then
    return 0
  fi

  dot_hook_log "  tmux"
  "$tmux_command" source-file "$config" || return $?
  # The stamp records only bytes proven stable across the reload: a
  # config change racing the reload skips the write so the next run
  # heals instead of trusting possibly torn server state.
  fresh=$(_tmux_hook_fingerprint "$config" "$conf_dir") 2>/dev/null || return 0
  [[ $fresh == "$fp" ]] || return 0
  mkdir -p "${stamp%/*}" 2>/dev/null || return 0
  if tmp=$(mktemp "${stamp}.tmp.XXXXXX" 2>/dev/null) &&
    printf '%s\n' "$fresh" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$stamp" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  return 0
}
