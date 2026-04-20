# shellcheck shell=bash
# Core constants and logging helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"

# ---------------------------------------------------------------------------
# Colors — disabled when not a terminal or NO_COLOR is set.
# ---------------------------------------------------------------------------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\033[0m'
  _C_BOLD=$'\033[1m'
  _C_DIM=$'\033[0;90m'
  _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'
  _C_WHITE=$'\033[38;2;255;255;255m'
else
  _C_RESET="" _C_BOLD="" _C_DIM="" _C_GREEN="" _C_YELLOW="" _C_WHITE=""
fi

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

# Print a message unless quiet mode is active.
_log() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "$@"
}

# Section header (bright bold white, always prints).
_header() {
  echo "${_C_BOLD}${_C_WHITE}$*${_C_RESET}"
}

# Section header (bright bold white, respects quiet mode).
_log_header() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_BOLD}${_C_WHITE}$*${_C_RESET}"
}

# Success message (green, respects quiet mode).
_log_ok() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_GREEN}$*${_C_RESET}"
}

# Muted message (dim, respects quiet mode).
_log_dim() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "${_C_DIM}$*${_C_RESET}"
}

# Warning message (yellow, always prints to stderr).
_warn() {
  echo "${_C_YELLOW}$*${_C_RESET}" >&2
}

_logfile_create() {
  local log=""
  if ! log=$(mktemp 2>/dev/null); then
    REPLY=""
    return 1
  fi
  REPLY="$log"
}

_logfile_print() {
  local label="$1"
  local log="$2"
  [[ -n "$log" && -s "$log" ]] || return 0
  _warn "  $label output:"
  sed 's/^/    /' "$log" >&2
}

# Run a command, capturing output to the caller's $log if set.
# Returns the command's exit code.
_run_logged() {
  if [[ -n "${log:-}" ]]; then
    "$@" >"$log" 2>&1
  else
    "$@" >/dev/null 2>&1
  fi
}

_run_quiet_logged() {
  local label="$1"
  local warning="$2"
  shift 2

  local log=""
  if ! _logfile_create; then
    "$@" >/dev/null 2>&1 || _warn "  warning: $warning"
    return 0
  fi
  log="$REPLY"

  if "$@" >"$log" 2>&1; then
    rm -f "$log"
    return 0
  fi

  _logfile_print "$label" "$log"
  rm -f "$log"
  _warn "  warning: $warning"
  return 0
}

# ---------------------------------------------------------------------------
# Platform helpers
# ---------------------------------------------------------------------------

_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qi "microsoft" /proc/sys/kernel/osrelease
}

# Acquire sudo. Returns 0 if root or sudo obtained.
# In quiet mode, skips interactive prompt and returns 1 silently.
_require_sudo() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  sudo -n true 2>/dev/null && return 0
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && return 1
  sudo true 2>/dev/null
}

# ---------------------------------------------------------------------------
# Overlay discovery
# ---------------------------------------------------------------------------

# Active overlays, populated by _discover_overlays. Each entry: "name|path|url"
# shellcheck disable=SC2034  # used by scripts that source this file
OVERLAYS=()

# Extract overlay name from conf filename: "10-work.conf" → "work"
# Sets REPLY so callers avoid a `$(...)` subshell fork.
_overlay_name() {
  local base="${1##*/}"
  base="${base%.conf}"
  [[ "$base" =~ ^[0-9]+-(.+)$ ]] && base="${BASH_REMATCH[1]}"
  REPLY="$base"
}

# Parse a single overlay conf file.
# Sets REPLY to "name|path|url". Returns 1 if filtered out or missing url.
_parse_overlay_conf() {
  local file="$1"
  local url="" platforms="" hosts=""
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      url=*) url="${line#url=}" ;;
      platforms=*) platforms="${line#platforms=}" ;;
      hosts=*) hosts="${line#hosts=}" ;;
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

  _overlay_name "$file"
  local name="$REPLY"
  REPLY="$name|$HOME/.dotfiles-$name|$url"
}

# Ensure overlay .ssh files are merged into ~/.ssh/config so clone
# URLs using SSH host aliases resolve. Each .ssh file gets its own
# marked block, managed by the shared merge-block helpers.
_merge_overlay_ssh_configs() {
  local conf_dir="$HOME/.config/dot/overlays.d"
  local dst="$HOME/.ssh/config"
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
  local conf_dir="$HOME/.config/dot/overlays.d"
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

# ---------------------------------------------------------------------------
# Shared finalize sequence
# ---------------------------------------------------------------------------

# Common post-pull steps shared by dot update, dot pull, and dotbootstrap.
# Installs/upgrades deps, links overlay files, merges app configs, and
# cleans up phantom dirty files.
_finalize_update() {
  _ensure_repo_config
  _ensure_shdeps
  if declare -f shdeps_update &>/dev/null; then
    shdeps_update
  else
    _warn "  warning: shdeps not available — skipping dependency install"
  fi
  _link_overlays
  _run_merges
  if [[ -d "$DOTFILES" ]]; then
    _normalize_filtered
  fi
  # shdeps may have upgraded tools whose init output is cached by the
  # _cached_init helper. Purge so the next shell regenerates.
  rm -rf "$HOME/.cache/shell"
  _log_header "==> Done! Run 'source ~/.bashrc' or 'source ~/.zshrc' to activate."
}
