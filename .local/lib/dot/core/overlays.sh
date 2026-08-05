# shellcheck shell=bash
# Overlay discovery helpers shared by dot commands.

# Active overlays, populated by _discover_overlays. Each entry:
# "name|path|url|conf|optional|ssh|sync". The first six fields are kept stable
# for older repo/link helpers. A missing final field means `git`; `none` means
# the source tree already exists locally and repository synchronization is
# deliberately outside dot.
# shellcheck disable=SC2034  # used by scripts that source this file
OVERLAYS=()

# Extract overlay name from conf filename: "10-work.conf" → "work"
_overlay_name() {
  local base="${1##*/}"
  local sync="${2:-git}"
  base="${base%.conf}"
  [[ "$sync" == "none" ]] && base="${base%.local}"
  [[ "$base" =~ ^[0-9]+-(.+)$ ]] && base="${BASH_REMATCH[1]}"
  # printf, not echo: a name beginning with a dash would be eaten as an echo flag.
  printf '%s\n' "$base"
}

_overlay_descriptor_value_safe() {
  local value="$1"
  [[ "$value" != *'|'* && "$value" != *$'\t'* &&
    "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

_overlay_relative_path_safe() {
  local rel="$1"
  _overlay_descriptor_value_safe "$rel" || return 1
  case "$rel" in
    "" | /* | . | .. | ./* | ../* | */./* | */../* | */. | */.. | */ | *//*)
      return 1
      ;;
  esac
}

_overlay_conf_invalid() {
  REPLY="invalid overlay descriptor $1: $2"
  _warn "  warning: $REPLY"
  return 2
}

# Directory holding overlay conf files and their companion .ssh snippets.
_overlay_conf_dir() {
  printf '%s\n' "$HOME/.config/dot/overlays.d"
}

# Parse a single overlay conf file.
# Sets REPLY to "name|path|url|conf|optional|ssh|sync". Returns 1 when a valid
# descriptor is filtered from this host and 2 when the descriptor is invalid.
_parse_overlay_conf() {
  local file="$1"
  local url="" path="" platforms="" hosts="" optional="" sync="git"
  local seen_url=0 seen_path=0 seen_platforms=0 seen_hosts=0 seen_optional=0 seen_sync=0
  local line strict_error=""
  local -a unknown_lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      url=*)
        if ((seen_url > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate url"
        fi
        seen_url=$((seen_url + 1))
        url="${line#url=}"
        ;;
      path=*)
        if ((seen_path > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate path"
        fi
        seen_path=$((seen_path + 1))
        path="${line#path=}"
        ;;
      platforms=*)
        if ((seen_platforms > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate platforms"
        fi
        seen_platforms=$((seen_platforms + 1))
        platforms="${line#platforms=}"
        ;;
      hosts=*)
        if ((seen_hosts > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate hosts"
        fi
        seen_hosts=$((seen_hosts + 1))
        hosts="${line#hosts=}"
        ;;
      optional=*)
        if ((seen_optional > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate optional"
        fi
        seen_optional=$((seen_optional + 1))
        optional="${line#optional=}"
        ;;
      sync=*)
        if ((seen_sync > 0)) && [[ -z "$strict_error" ]]; then
          strict_error="duplicate sync"
        fi
        seen_sync=$((seen_sync + 1))
        sync="${line#sync=}"
        ;;
      \#* | "") ;;
      *)
        unknown_lines+=("$line")
        if [[ -z "$strict_error" ]]; then
          strict_error="unknown key: ${line%%=*}"
        fi
        ;;
    esac
  done <"$file"

  if ((seen_sync > 1)); then
    _overlay_conf_invalid "$file" "duplicate sync" || return
  fi
  case "$sync" in
    git | none) ;;
    *) _overlay_conf_invalid "$file" "unknown sync value: $sync" || return ;;
  esac

  local name ssh_file
  name=$(_overlay_name "$file" "$sync")
  ssh_file="${file%.conf}.ssh"
  [[ -f "$ssh_file" ]] || ssh_file=""

  if [[ "$sync" == "none" || "$seen_path" -gt 0 ]]; then
    [[ -z "$strict_error" ]] || _overlay_conf_invalid "$file" "$strict_error" || return
    [[ "$sync" == "none" ]] || _overlay_conf_invalid "$file" "path requires sync=none" || return
    [[ "$seen_path" -eq 1 && -n "$path" ]] || _overlay_conf_invalid "$file" "missing path" || return
    [[ "$seen_url" -eq 0 ]] || _overlay_conf_invalid "$file" "url is not valid with sync=none" || return
    [[ "$seen_optional" -eq 0 ]] || _overlay_conf_invalid "$file" "optional is not valid with sync=none" || return
    [[ -z "$ssh_file" ]] || _overlay_conf_invalid "$file" "SSH config is not valid with sync=none" || return
    if ! _overlay_descriptor_value_safe "$name" ||
      ! _overlay_descriptor_value_safe "$file"; then
      _overlay_conf_invalid "$file" "unrepresentable name or path" || return
    fi
    case "$path" in
      \~/*) path="$HOME/${path#\~/}" ;;
      /*) ;;
      *) _overlay_conf_invalid "$file" "path must be absolute or begin with ~/" || return ;;
    esac
    _overlay_descriptor_value_safe "$path" || _overlay_conf_invalid "$file" "unrepresentable path" || return
    case "$path" in
      / | */ | *//* | */./* | */../* | */. | */..)
        _overlay_conf_invalid "$file" "path must be normalized" || return
        ;;
    esac
    optional=false
  else
    for line in "${unknown_lines[@]+"${unknown_lines[@]}"}"; do
      _warn "  warning: unknown key in $file: $line"
    done
    [[ -n "$url" ]] || return 1
  fi

  if [[ -n "$platforms" ]] && declare -f shdeps_platform_match &>/dev/null; then
    shdeps_platform_match "$platforms" || return 1
  fi
  if [[ -n "$hosts" ]] && declare -f shdeps_host_match &>/dev/null; then
    shdeps_host_match "$hosts" || return 1
  fi
  if [[ "$sync" == "git" ]]; then
    case "$optional" in
      "" | true | false) ;;
      *) _warn "  warning: unknown optional value in $file: $optional" ;;
    esac
  fi
  # Optional overlays declare private or context-specific repos in the base
  # config without making every machine prove access to them. Store the flag on
  # the parsed active record so a filtered-out duplicate name cannot change the
  # behavior of the overlay that actually matched this machine.
  if [[ "$sync" == "git" ]]; then
    path="$HOME/.dotfiles-$name"
  fi
  REPLY="$name|$path|$url|$file|${optional:-false}|$ssh_file|$sync"
}

# Resolve an existing directory physically, then append any still-missing path
# components lexically. Overlay relative paths are normalized before this is
# called, so the suffix cannot escape the resolved ancestor.
_overlay_physical_dir_candidate() {
  local candidate="$1" suffix="" part parent physical
  [[ "$candidate" == /* ]] || return 1
  while [[ ! -d "$candidate" ]]; do
    [[ "$candidate" != "/" ]] || return 1
    part="${candidate##*/}"
    [[ -n "$part" ]] || return 1
    suffix="/$part$suffix"
    parent="${candidate%/*}"
    [[ -n "$parent" ]] || parent="/"
    [[ "$parent" != "$candidate" ]] || return 1
    candidate="$parent"
  done
  physical=$(cd -P -- "$candidate" 2>/dev/null && pwd -P) || return 1
  if [[ "$physical" == "/" ]]; then
    REPLY="/${suffix#/}"
  else
    REPLY="$physical$suffix"
  fi
}

_overlay_local_destination_safe() {
  local path="$1" rel="$2" source_root_real="${3:-}"
  local overlay_home="$path/home"
  local source_prefix rel_parent dst_parent destination_real candidate_prefix

  if ! _overlay_relative_path_safe "$rel"; then
    REPLY="$overlay_home (unrepresentable destination: $rel)"
    return 1
  fi
  if [[ -z "$source_root_real" ]]; then
    source_root_real=$(cd -P -- "$overlay_home" 2>/dev/null && pwd -P) || {
      REPLY="$overlay_home"
      return 1
    }
  fi
  source_prefix="${source_root_real%/}/"
  [[ "$source_root_real" == "/" ]] && source_prefix="/"

  rel_parent="${rel%/*}"
  if [[ "$rel_parent" == "$rel" ]]; then
    dst_parent="$HOME"
  else
    dst_parent="$HOME/$rel_parent"
  fi
  if ! _overlay_physical_dir_candidate "$dst_parent"; then
    REPLY="$overlay_home (cannot resolve destination: $rel)"
    return 1
  fi
  destination_real="$REPLY"
  candidate_prefix="${destination_real%/}/"
  [[ "$destination_real" == "/" ]] && candidate_prefix="/"
  case "$candidate_prefix" in
    "$source_prefix"*)
      REPLY="$overlay_home (destination resolves inside source: $rel)"
      return 1
      ;;
  esac
  REPLY=""
}

# No overlay writer may reach an active filesystem overlay's source through a
# symlinked destination parent. Check every local source, not just the writer's
# own source: overlay order and synchronization mode must not create a path
# that lets a later local or Git overlay mutate an earlier source tree.
_overlay_destination_outside_local_sources() {
  local rel="$1" entry path sync
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r _ path _ _ _ _ sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$sync" == "none" ]] || continue
    _overlay_local_destination_safe "$path" "$rel" || return 1
  done
  REPLY=""
}

# Revalidate one entry from a filesystem overlay inventory. This is shared by
# the initial preflight and the mutation-boundary check, because an external
# source may change while an update is running.
_overlay_local_source_entry_validate() {
  local path="$1" src="$2" rel="$3" source_root_real="$4"
  local overlay_home="$path/home"

  if [[ "$src" != "$overlay_home/$rel" ]] ||
    ! _overlay_relative_path_safe "$rel"; then
    REPLY="$overlay_home (unrepresentable entry)"
    return 1
  fi

  if [[ -L "$src" ]]; then
    if [[ ! -e "$src" ]]; then
      REPLY="$overlay_home (dangling symlink: $rel)"
      return 1
    elif [[ -d "$src" ]]; then
      if [[ ! -r "$src" || ! -x "$src" ]]; then
        REPLY="$overlay_home (unreadable symlink target: $rel)"
        return 1
      fi
    elif [[ ! -f "$src" || ! -r "$src" ]]; then
      REPLY="$overlay_home (unreadable symlink target: $rel)"
      return 1
    fi
  elif [[ ! -f "$src" || ! -r "$src" ]]; then
    REPLY="$overlay_home (unreadable entry: $rel)"
    return 1
  fi

  _overlay_local_destination_safe "$path" "$rel" "$source_root_real" || return 1
  _overlay_destination_outside_local_sources "$rel" || return 1
  REPLY=""
}

# Validate one filesystem overlay and leave a diagnostic in REPLY on failure.
# Regular entries must be readable. Source symlinks are allowed when they
# resolve to a readable regular file, or to a readable/searchable directory;
# dangling links and links to special files are rejected before HOME mutation.
_overlay_local_source_validate() {
  local path="$1"
  local overlay_home="$path/home" inventory="" src rel
  local source_root_real
  local invalid_inventory=0

  REPLY=""
  if [[ ! -d "$overlay_home" || ! -r "$overlay_home" || ! -x "$overlay_home" ]]; then
    REPLY="$overlay_home"
    return 1
  fi
  source_root_real=$(cd -P -- "$overlay_home" 2>/dev/null && pwd -P) || {
    REPLY="$overlay_home"
    return 1
  }
  inventory=$(mktemp 2>/dev/null) || {
    REPLY="could not validate inventory for $overlay_home"
    return 1
  }
  if ! find "$overlay_home" \( -type f -o -type l \) ! -name '*.~[0-9]*~' -print0 \
    >"$inventory"; then
    REPLY="could not read inventory for $overlay_home"
    rm -f -- "$inventory"
    return 1
  fi

  while IFS= read -r -d '' src; do
    rel="${src#"$overlay_home"/}"
    if ! _overlay_local_source_entry_validate \
      "$path" "$src" "$rel" "$source_root_real"; then
      invalid_inventory=1
      break
    fi
  done <"$inventory"
  rm -f -- "$inventory"
  [[ "$invalid_inventory" -eq 0 ]] || return 1
  REPLY=""
}

# Validate every active filesystem overlay before repository synchronization,
# link mutation, or update finalization. The defensive linker call closes
# re-exec and direct-library entry paths as well.
_preflight_local_overlays() {
  local entry name path sync
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path _ _ _ _ sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$sync" == "none" ]] || continue
    if ! _overlay_local_source_validate "$path"; then
      _warn "  warning: $name overlay source is unavailable: ${REPLY:-$path/home}"
      return 1
    fi
  done
}

# Ensure overlay .ssh files are merged into ~/.ssh/config so clone
# URLs using SSH host aliases resolve. Each .ssh file gets its own
# marked block, managed by the shared merge-block helpers.
_merge_overlay_ssh_configs() {
  local dst
  dst="$DOT_SSH_CONFIG"
  local -a blocks=()
  local entry f sync
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r _ _ _ _ _ f sync <<<"$entry"
    sync="${sync:-git}"
    [[ "$sync" == "git" && -n "$f" && -f "$f" ]] || continue
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

  [[ ${#blocks[@]} -gt 0 || -f "$dst" ]] || return 0
  _mb_merge_family "$dst" "# dot-managed:overlay-ssh:" "${blocks[@]}"
}

# Discover all active overlays. Populates OVERLAYS array.
# Call once after shdeps is loaded; callers iterate the cached array.
# Callers that clone overlays should call _merge_overlay_ssh_configs after
# discovery and before pull so only active Git aliases are installed.
_discover_overlays() {
  OVERLAYS=()
  unset DOT_OVERLAY_DISCOVERY_ERROR
  local conf_dir
  conf_dir="$(_overlay_conf_dir)"
  [[ -d "$conf_dir" ]] || return 0
  local f seen_names=""
  for f in "$conf_dir"/*.conf; do
    [[ -f "$f" ]] || continue
    local parse_rc=0
    if _parse_overlay_conf "$f"; then
      local name="${REPLY%%|*}"
      if [[ " $seen_names " == *" $name "* ]]; then
        _warn "  warning: duplicate overlay name '$name' in $f — skipping"
        continue
      fi
      seen_names="$seen_names $name"
      OVERLAYS+=("$REPLY")
    else
      parse_rc=$?
      [[ "$parse_rc" -eq 1 ]] && continue
      DOT_OVERLAY_DISCOVERY_ERROR="$REPLY"
      OVERLAYS=()
      return "$parse_rc"
    fi
  done
}
