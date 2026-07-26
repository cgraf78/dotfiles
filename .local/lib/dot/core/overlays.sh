# shellcheck shell=bash
# Overlay discovery helpers shared by dot commands.

# Active overlays, populated by _discover_overlays. Each entry:
# "name|path|url|conf|optional|ssh". The first three fields are kept stable for
# older repo/link helpers; later fields carry metadata from the exact active
# conf file so filtered duplicate names cannot affect pull/doctor policy.
# shellcheck disable=SC2034  # used by scripts that source this file
OVERLAYS=()

# Extract overlay name from conf filename: "10-work.conf" → "work"
_overlay_name() {
  local base="${1##*/}"
  base="${base%.conf}"
  [[ "$base" =~ ^[0-9]+-(.+)$ ]] && base="${BASH_REMATCH[1]}"
  # printf, not echo: a name beginning with a dash would be eaten as an echo flag.
  printf '%s\n' "$base"
}

# Directory holding overlay conf files and their companion .ssh snippets.
_overlay_conf_dir() {
  printf '%s\n' "$HOME/.config/dot/overlays.d"
}

# Parse a single overlay conf file.
# Sets REPLY to "name|path|url|conf|optional|ssh". Returns 1 if filtered out or
# missing url.
_parse_overlay_conf() {
  local file="$1"
  local url="" platforms="" hosts="" optional=""
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      url=*) url="${line#url=}" ;;
      platforms=*) platforms="${line#platforms=}" ;;
      hosts=*) hosts="${line#hosts=}" ;;
      optional=*) optional="${line#optional=}" ;;
      \#* | "") ;;
      *) _warn "  warning: unknown key in $file: $line" ;;
    esac
  done <"$file"

  [[ -n "$url" ]] || return 1

  if [[ -n "$platforms" ]] && declare -f shdeps_platform_match &>/dev/null; then
    shdeps_platform_match "$platforms" || return 1
  fi
  if [[ -n "$hosts" ]] && declare -f shdeps_host_match &>/dev/null; then
    shdeps_host_match "$hosts" || return 1
  fi
  case "$optional" in
    "" | "true" | "false") ;;
    *) _warn "  warning: unknown optional value in $file: $optional" ;;
  esac

  local name
  name=$(_overlay_name "$file")

  # Optional overlays declare private or context-specific repos in the base
  # config without making every machine prove access to them. Store the flag on
  # the parsed active record so a filtered-out duplicate name cannot change the
  # behavior of the overlay that actually matched this machine.
  local ssh_file="${file%.conf}.ssh"
  [[ -f "$ssh_file" ]] || ssh_file=""
  REPLY="$name|$HOME/.dotfiles-$name|$url|$file|${optional:-false}|$ssh_file"
}

# Ensure overlay .ssh files are merged into ~/.ssh/config so clone
# URLs using SSH host aliases resolve. Each .ssh file gets its own
# marked block, managed by the shared merge-block helpers.
_merge_overlay_ssh_configs() {
  local conf_dir dst
  conf_dir="$(_overlay_conf_dir)"
  dst="$DOT_SSH_CONFIG"
  local -a blocks=()
  local f
  for f in "$conf_dir"/*.ssh; do
    [[ -f "$f" ]] || continue
    grep -qm1 "^Host " "$f" 2>/dev/null || continue

    local name
    name="$(basename "$f" .ssh)"
    local origin
    origin="$(realpath "$f")"
    local body
    body=$(<"$f")
    body="${body%$'\n'}"

    # Inherit ProxyCommand from the target host if the alias doesn't
    # define one. E.g., if Host github.com has a ProxyCommand for a
    # corporate proxy, the alias needs it too.
    if [[ "$body" != *ProxyCommand* ]]; then
      local target_host
      target_host=$(echo "$body" | awk '/^[[:space:]]+HostName /{print $2; exit}')
      if [[ -n "$target_host" && -f "$dst" ]]; then
        local proxy_cmd
        proxy_cmd=$(awk -v host="$target_host" '
          /^Host / { active=($2 == host) }
          active && /^[[:space:]]+ProxyCommand / { sub(/^[[:space:]]+/, "  "); print; exit }
        ' "$dst")
        if [[ -n "$proxy_cmd" ]]; then
          body="$body"$'\n'"$proxy_cmd"
        fi
      fi
    fi

    blocks+=("$(_mb_build "# dot-managed:overlay-ssh:$name" "$origin" "$body")")
  done

  [[ ${#blocks[@]} -gt 0 ]] || return 0
  _mb_merge "$dst" "${blocks[@]}"
}

# Discover all active overlays. Populates OVERLAYS array.
# Call once after shdeps is loaded; callers iterate the cached array.
# Callers that clone overlays should call _merge_overlay_ssh_configs
# first so SSH host aliases resolve.
_discover_overlays() {
  OVERLAYS=()
  local conf_dir
  conf_dir="$(_overlay_conf_dir)"
  [[ -d "$conf_dir" ]] || return 0
  local f seen_names=""
  for f in "$conf_dir"/*.conf; do
    [[ -f "$f" ]] || continue
    if _parse_overlay_conf "$f"; then
      local name="${REPLY%%|*}"
      if [[ " $seen_names " == *" $name "* ]]; then
        _warn "  warning: duplicate overlay name '$name' in $f — skipping"
        continue
      fi
      seen_names="$seen_names $name"
      OVERLAYS+=("$REPLY")
    fi
  done
}
