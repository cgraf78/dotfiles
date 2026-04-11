# shellcheck shell=bash
# Dependency management for dotbootstrap.
# Sourced by init.sh. Requires _log, _warn, DOT_QUIET from core.sh.
# Set DOT_FORCE=1 to force reinstall of all deps and re-run all hooks.

# ---------------------------------------------------------------------------
# Dep registry — parse ~/.config/dot/deps.conf
# ---------------------------------------------------------------------------

# Parse deps.conf (and optional deps.local.conf) into _DEPS array.
# Each entry is pipe-delimited. deps.local.conf is untracked and
# allows machine-local dependencies (same format as deps.conf).
_dep_load() {
  _DEPS=()
  local conf="$HOME/.config/dot/deps.conf"
  local conf_local="$HOME/.config/dot/deps.local.conf"
  if [[ ! -f "$conf" && ! -f "$conf_local" ]]; then
    _warn "  warning: $conf not found — skipping dependency install"
    return 0
  fi
  local f line
  for f in "$conf" "$conf_local"; do
    [[ -f "$f" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip comments and blank lines
      if [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
      if [[ -z "${line// /}" ]]; then continue; fi
      # Normalize whitespace to pipe delimiter
      local fields
      # shellcheck disable=SC2086  # intentional word splitting
      set -- $line
      fields="$*"
      _DEPS+=("${fields// /|}")
    done <"$f"
  done
}

# Split a pipe-delimited registry entry into named variables.
# Sets: _name, _method, _cmd, _cmd_alt, _pkg_overrides, _repo, _dir, _platforms
_dep_parse() {
  local entry="$1"
  IFS='|' read -r _name _method _cmd _cmd_alt _pkg_overrides _repo _dir _platforms <<<"$entry"
  # Replace - with empty
  if [[ "$_cmd" == "-" ]]; then _cmd=""; fi
  if [[ "$_cmd_alt" == "-" ]]; then _cmd_alt=""; fi
  if [[ "$_pkg_overrides" == "-" ]]; then _pkg_overrides=""; fi
  if [[ "$_repo" == "-" ]]; then _repo=""; fi
  if [[ "$_dir" == "-" ]]; then _dir=""; fi
  if [[ "$_platforms" == "-" ]]; then _platforms=""; fi
  # Default cmd to name
  if [[ -z "$_cmd" ]]; then _cmd="$_name"; fi
}

# Check if the current platform matches a platforms spec.
# Empty spec matches all platforms. Supports include (linux,darwin)
# and exclude (!wsl,!darwin) lists.
# Returns 0 if the dep should install on this platform.
_platform_match() {
  local spec="${1:-}"
  if [[ -z "$spec" ]]; then return 0; fi

  local current
  current=$(uname -s | tr '[:upper:]' '[:lower:]')
  _is_wsl && current="wsl"

  local item has_include=0 has_exclude=0
  local IFS=','
  # Determine if this is an include or exclude list
  for item in $spec; do
    if [[ "$item" == !* ]]; then has_exclude=1; else has_include=1; fi
  done

  if [[ $has_include -eq 1 && $has_exclude -eq 1 ]]; then
    # Mixed: check excludes first, then includes
    for item in $spec; do
      [[ "$item" == "!$current" ]] && return 1
    done
    for item in $spec; do
      [[ "$item" == "$current" ]] && return 0
    done
    return 1
  elif [[ $has_exclude -eq 1 ]]; then
    # Exclude-only: match unless excluded
    for item in $spec; do
      [[ "$item" == "!$current" ]] && return 1
    done
    return 0
  else
    # Include-only: match only if listed
    for item in $spec; do
      [[ "$item" == "$current" ]] && return 0
    done
    return 1
  fi
}

# Check if a dependency is installed. Returns 0 if cmd or cmd_alt is found.
# Falls back to querying the package manager when command lookup fails
# (useful for deps like fonts that don't provide binaries).
# Requires _pkg_detect to have set _PKG_MGR before using the fallback.
_dep_exists() {
  local cmd="${1:-}" alt="${2:-}" name="${3:-}"
  if [[ -n "$cmd" ]]; then
    if command -v "$cmd" &>/dev/null; then return 0; fi
    if [[ -n "$alt" ]] && command -v "$alt" &>/dev/null; then return 0; fi
  fi
  # Command not found (or empty) — try the package manager directly.
  if [[ -n "$name" ]]; then
    case "${_PKG_MGR:-}" in
    brew) brew list "$name" &>/dev/null && return 0 ;;
    apt) dpkg -s "$name" &>/dev/null && return 0 ;;
    dnf) rpm -q "$name" &>/dev/null && return 0 ;;
    pacman) pacman -Q "$name" &>/dev/null && return 0 ;;
    esac
  fi
  return 1
}

# Get installed version of a command.
# Extracts the first version-like token (digits+dots, optional leading v)
# from the first line of --version output.
_dep_version() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then return 1; fi
  "$cmd" --version 2>/dev/null | head -1 |
    grep -o '[0-9][0-9.]*' | head -1
}

# ---------------------------------------------------------------------------
# Package manager abstraction
# ---------------------------------------------------------------------------

# Acquire sudo. Returns 0 if root or sudo obtained.
# In quiet mode, skips interactive prompt and returns 1 silently.
_require_sudo() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  sudo -n true 2>/dev/null && return 0
  [[ "$DOT_QUIET" -eq 1 ]] && return 1
  sudo true 2>/dev/null
}

# Detect available package manager. Sets _PKG_MGR.
_pkg_detect() {
  if [[ "$(uname -s 2>/dev/null)" == "Darwin" ]] && command -v brew &>/dev/null; then
    _PKG_MGR="brew"
  elif command -v apt-get &>/dev/null; then
    _PKG_MGR="apt"
  elif command -v dnf &>/dev/null; then
    _PKG_MGR="dnf"
  elif command -v pacman &>/dev/null; then
    _PKG_MGR="pacman"
  else
    _PKG_MGR=""
  fi
}

# Resolve canonical package name to OS-specific name.
# $1=name $2=pkg_overrides (e.g. "apt:fd-find,dnf:fd-find")
_pkg_resolve() {
  local name="$1" overrides="${2:-}"
  if [[ -n "$overrides" && -n "$_PKG_MGR" ]]; then
    local pair
    IFS=',' read -ra pairs <<<"$overrides"
    for pair in "${pairs[@]}"; do
      local mgr="${pair%%:*}"
      local pkg="${pair#*:}"
      if [[ "$mgr" == "$_PKG_MGR" ]]; then
        echo "$pkg"
        return 0
      fi
    done
  fi
  echo "$name"
}

# Queue a package for batched install.
# $1=name $2=pkg_overrides
# Skips if _pkg_resolve returns NONE (platform not supported).
_pkg_queue() {
  local name="$1" overrides="${2:-}"
  local resolved
  resolved=$(_pkg_resolve "$name" "$overrides")
  if [[ "$resolved" == "NONE" ]]; then
    return 0
  fi
  _PKG_BATCH+=("$resolved")
  _PKG_BATCH_NAMES+=("$name")
  _log "  $name queued for install"
}

# Install all queued packages in a single command.
_pkg_install_batch() {
  [[ ${#_PKG_BATCH[@]} -eq 0 ]] && return 0

  if [[ -z "$_PKG_MGR" ]]; then
    _warn "  warning: no package manager found — cannot install: ${_PKG_BATCH[*]}"
    return 0
  fi

  # Cron mode: proceed if root, silently skip otherwise
  if [[ "$DOT_QUIET" -eq 1 && "$(id -u)" -ne 0 ]]; then
    return 0
  fi

  _log_ok "  installing: ${_PKG_BATCH[*]}"

  # Check sudo access for non-brew managers before attempting install
  if [[ "$_PKG_MGR" != "brew" ]] && ! _require_sudo; then
    _warn "  warning: sudo not available — cannot install: ${_PKG_BATCH[*]}"
    return 0
  fi

  local rc=0
  local log=""
  if ! _logfile_create; then
    _warn "  warning: failed to create temp log for package install"
  else
    log="$REPLY"
  fi
  case "$_PKG_MGR" in
  apt) sudo apt-get update -qq >/dev/null 2>&1 || true ;;
  esac
  # shellcheck disable=SC2024  # sudo output captured in user-owned log via _run_logged.
  case "$_PKG_MGR" in
  brew) _run_logged brew install "${_PKG_BATCH[@]}" || rc=$? ;;
  apt) _run_logged sudo apt-get install -y "${_PKG_BATCH[@]}" || rc=$? ;;
  dnf) _run_logged sudo dnf install -y "${_PKG_BATCH[@]}" || rc=$? ;;
  pacman) _run_logged sudo pacman -Sy --needed --noconfirm "${_PKG_BATCH[@]}" || rc=$? ;;
  esac

  # On batch failure, retry individually
  if [[ $rc -ne 0 ]]; then
    _logfile_print "package manager" "$log"
    _warn "  warning: batch install failed, retrying individually..."
    local pkg
    for pkg in "${_PKG_BATCH[@]}"; do
      rc=0
      [[ -n "$log" ]] && : >"$log"
      # shellcheck disable=SC2024  # Intentionally capture sudo command output in a user-owned temp log.
      case "$_PKG_MGR" in
      brew) _run_logged brew install "$pkg" || rc=$? ;;
      apt) _run_logged sudo apt-get install -y "$pkg" || rc=$? ;;
      dnf) _run_logged sudo dnf install -y "$pkg" || rc=$? ;;
      pacman) _run_logged sudo pacman -Sy --needed --noconfirm "$pkg" || rc=$? ;;
      esac
      if [[ $rc -ne 0 ]]; then
        _logfile_print "package manager for $pkg" "$log"
        _warn "  warning: failed to install $pkg"
        rc=0
      fi
    done
  fi

  rm -f "$log"

  # Mark all batch-installed deps as changed
  local _i
  for _i in "${!_PKG_BATCH_NAMES[@]}"; do
    _DEPS_CHANGED[${_PKG_BATCH_NAMES[$_i]}]=1
  done
}

# ---------------------------------------------------------------------------
# Remote-check cache
# ---------------------------------------------------------------------------

_dep_remote_ttl() {
  echo "${DOT_DEPS_REMOTE_TTL:-3600}"
}

_dep_remote_stamp() {
  local name="$1" kind="$2"
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  echo "$state_root/${name}.${kind}.stamp"
}

_dep_remote_fresh() {
  local stamp="$1"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && return 1
  [[ -f "$stamp" ]] || return 1

  local cached="" now="" ttl=""
  read -r cached <"$stamp" || return 1
  now=$(date +%s 2>/dev/null || true)
  ttl=$(_dep_remote_ttl)

  [[ "$cached" =~ ^[0-9]+$ ]] || return 1
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  [[ "$ttl" =~ ^[0-9]+$ ]] || return 1

  ((now - cached < ttl))
}

_dep_remote_touch() {
  local stamp="$1"
  local stamp_dir
  stamp_dir=$(dirname "$stamp")
  mkdir -p "$stamp_dir" || return 1
  date +%s >"$stamp"
}

_dep_hook_stamp() {
  local name="$1"
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  echo "$state_root/${name}.hook.stamp"
}

_dep_hook_due() {
  local name="$1"
  local stamp=""
  stamp=$(_dep_hook_stamp "$name")
  ! _dep_remote_fresh "$stamp"
}

_dep_hook_touch() {
  local name="$1"
  local stamp=""
  stamp=$(_dep_hook_stamp "$name")
  _dep_remote_touch "$stamp"
}

_dep_rev_stamp() {
  local name="$1"
  local state_root="${XDG_STATE_HOME:-$HOME/.local/state}/dot/deps"
  echo "$state_root/${name}.rev"
}

_dep_rev_read() {
  local name="$1"
  local stamp=""
  stamp=$(_dep_rev_stamp "$name")
  [[ -f "$stamp" ]] || return 1
  read -r REPLY <"$stamp" || return 1
}

_dep_rev_touch() {
  local name="$1" rev="$2"
  local stamp=""
  stamp=$(_dep_rev_stamp "$name")
  local stamp_dir
  stamp_dir=$(dirname "$stamp")
  mkdir -p "$stamp_dir" || return 1
  printf '%s\n' "$rev" >"$stamp"
}

# ---------------------------------------------------------------------------
# Install methods
# ---------------------------------------------------------------------------

# Get version string for an installed tool.
# Checks: VERSION file, git describe, git log.
_get_version() {
  local dir="$1"
  if [[ -f "$dir/VERSION" ]]; then
    echo "v$(cat "$dir/VERSION")"
  elif [[ -d "$dir/.git" ]]; then
    local ver
    ver=$(git -C "$dir" describe --tags --abbrev=0 2>/dev/null || true)
    if [[ -z "$ver" ]]; then
      local hash
      hash=$(git -C "$dir" log -1 --format='%h' 2>/dev/null || true)
      if [[ -n "$hash" ]]; then ver="commit $hash"; fi
    fi
    echo "$ver"
  fi
}

# Symlink bin/<name> into PATH if it exists.
_link_bin() {
  local name="$1" install_dir="$2"
  if [[ -x "$install_dir/bin/$name" ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$install_dir/bin/$name" "$HOME/.local/bin/$name"
  fi
}

# Install or upgrade a tool from a local clone, GitHub release, or git clone.
# Usage: _install_from_github <name> <github-owner/repo> <install-dir>
# Priority: ~/git/<name> (symlink) > existing git clone (pull) > release tarball > fresh clone.
# If <install-dir>/bin/<name> exists after install, it is symlinked into PATH.
# Env var override: DOTBOOTSTRAP_<NAME>_REPO overrides the repo URL.

# Strategy: ~/git/<name> exists — symlink for live development.
_github_install_local_clone() {
  local name="$1" local_clone="$2" install_dir="$3"
  local link_before=""
  if [[ -L "$install_dir" ]]; then
    link_before=$(readlink "$install_dir" 2>/dev/null || true)
  fi
  local rev_before="" rev_after="" dirty_after=0
  if _dep_rev_read "$name"; then
    rev_before="$REPLY"
  fi
  rev_after=$(git -C "$local_clone" rev-parse HEAD 2>/dev/null || true)
  if [[ -n "$(git -C "$local_clone" status --porcelain --untracked-files=normal 2>/dev/null || true)" ]]; then
    dirty_after=1
  fi
  rm -rf "$install_dir"
  mkdir -p "$(dirname "$install_dir")"
  ln -sfn "$local_clone" "$install_dir"
  _link_bin "$name" "$install_dir"
  local ver
  ver=$(_get_version "$local_clone")
  if [[ -n "$rev_after" ]]; then
    _dep_rev_touch "$name" "$rev_after" || true
  fi
  if [[ "$link_before" != "$local_clone" || "$rev_before" != "$rev_after" || "$dirty_after" -eq 1 || "${DOT_FORCE:-0}" -eq 1 ]]; then
    _DEPS_CHANGED[$name]=1
    _log_ok "  $name -> $local_clone (local clone)${ver:+ -- $ver}"
  else
    _log_dim "  $name up to date${ver:+ -- $ver}"
  fi
}

# Strategy: install_dir/.git exists — pull to update.
_github_install_pull() {
  local name="$1" install_dir="$2" stamp="$3" log="$4"
  if _dep_remote_fresh "$stamp"; then
    _link_bin "$name" "$install_dir"
    local ver
    ver=$(_get_version "$install_dir")
    _log_dim "  $name up to date${ver:+ -- $ver}"
    rm -f "$log"
    return 0
  fi

  local head_before
  head_before=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
  if _run_logged git -C "$install_dir" pull --ff-only --quiet; then
    _link_bin "$name" "$install_dir"
    local head_after
    head_after=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
    local ver
    ver=$(_get_version "$install_dir")
    _dep_remote_touch "$stamp" || true
    if [[ "$head_before" != "$head_after" ]]; then
      _DEPS_CHANGED[$name]=1
      _log_ok "  $name updated${ver:+ -- $ver}"
    elif [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
      _DEPS_CHANGED[$name]=1
      _log_ok "  $name reinstalled${ver:+ -- $ver}"
    else
      _log_dim "  $name up to date${ver:+ -- $ver}"
    fi
  else
    _logfile_print "$name update" "$log"
    _warn "  warning: $name update failed"
  fi
  rm -f "$log"
}

# Strategy: no existing install — try release tarball, fall back to git clone.
_github_install_fresh() {
  local name="$1" repo="$2" install_dir="$3" stamp="$4" log="$5"
  local tarball_url="" tmp_dir

  # Capture current version before overwriting (for tarball/clone installs).
  local ver_before
  ver_before=$(_get_version "$install_dir")

  # Try GitHub release tarball. Extract owner/repo from URL.
  # Strip auth to prevent stale tokens from causing 401 on public repos.
  local gh_repo=""
  if [[ "$repo" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    gh_repo="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$gh_repo" ]] && command -v curl &>/dev/null; then
    tarball_url=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/$gh_repo/releases/latest" 2>/dev/null |
      grep -o '"browser_download_url":[[:space:]]*"[^"]*\.tar\.gz"' |
      head -1 | cut -d'"' -f4)
  fi

  if [[ -n "${tarball_url:-}" ]]; then
    tmp_dir=$(mktemp -d)
    # shellcheck disable=SC2016  # Single quotes intentional — inner script uses $1/$2.
    if _run_logged bash -c 'curl -fsSL "$1" | tar xz -C "$2"' _ "$tarball_url" "$tmp_dir"; then
      rm -rf "$install_dir"
      mkdir -p "$install_dir"
      # Tarball has a top-level dir (e.g., ds-v0.0.1/); move contents up
      mv "$tmp_dir"/*/* "$install_dir/" 2>/dev/null || mv "$tmp_dir"/* "$install_dir/"
      rm -rf "$tmp_dir"
    else
      rm -rf "$tmp_dir"
      _logfile_print "$name release download" "$log"
      _warn "  warning: failed to download $name release (trying git clone)"
      tarball_url=""
    fi
  fi

  # Fallback: git clone to a temp dir first so we don't destroy an existing
  # install on failure (e.g. network unreachable).
  if [[ -z "${tarball_url:-}" ]]; then
    if ! command -v git &>/dev/null; then
      rm -f "$log"
      _warn "  warning: no curl release and no git — cannot install $name"
      return 1
    fi
    local clone_tmp="${install_dir}.tmp.$$"
    rm -rf "$clone_tmp"
    [[ -n "${log:-}" ]] && : >"$log"
    if ! _run_logged git clone --depth 1 "$repo" "$clone_tmp"; then
      rm -rf "$clone_tmp"
      _logfile_print "$name clone" "$log"
      rm -f "$log"
      _warn "  warning: failed to clone $name (network unreachable?)"
      return 1
    fi
    rm -rf "$install_dir"
    mv "$clone_tmp" "$install_dir"
  fi

  _link_bin "$name" "$install_dir"
  rm -f "$log"
  _dep_remote_touch "$stamp" || true
  local ver
  ver=$(_get_version "$install_dir")
  local method="git clone"
  if [[ -n "${tarball_url:-}" ]]; then method="release tarball"; fi
  if [[ -n "$ver_before" && "$ver_before" == "$ver" ]] && [[ "${DOT_FORCE:-0}" -ne 1 ]]; then
    _log_dim "  $name up to date ($method)${ver:+ -- $ver}"
  else
    _DEPS_CHANGED[$name]=1
    if [[ -n "$ver_before" && "$ver_before" == "$ver" ]]; then
      _log_ok "  $name reinstalled ($method)${ver:+ -- $ver}"
    else
      _log_ok "  $name installed ($method)${ver:+ -- $ver}"
    fi
  fi
}

_install_from_github() {
  local name="$1" default_repo="$2" install_dir="$3"
  local upper="${name^^}"
  upper="${upper//-/_}"
  local env_var="DOTBOOTSTRAP_${upper}_REPO"
  local repo="${!env_var:-https://github.com/$default_repo}"
  local local_clone="$HOME/git/$name"
  local stamp=""
  stamp=$(_dep_remote_stamp "$name" git)

  if [[ -d "$local_clone" ]]; then
    _github_install_local_clone "$name" "$local_clone" "$install_dir"
    return $?
  fi

  local log=""
  if ! _logfile_create; then
    _warn "  warning: failed to create temp log for $name install"
  else
    log="$REPLY"
  fi

  if [[ -d "$install_dir/.git" ]]; then
    _github_install_pull "$name" "$install_dir" "$stamp" "$log"
    return $?
  fi

  _github_install_fresh "$name" "$repo" "$install_dir" "$stamp" "$log"
}

# Shared logic for finding and installing a binary from an extracted archive.
# After extraction, searches for the binary by name patterns and installs it
# into ~/.local/share/<name> with a symlink in ~/.local/bin.
# $1=name $2=cmd $3=extract_dir $4=orig_extract_dir $5=bin_path
_binary_install_from_extracted() {
  local name="$1" cmd="$2" extract_dir="$3" orig_extract_dir="$4" bin_path="$5"

  # If the archive has a single top-level directory, use its contents.
  local top_entries
  top_entries=$(ls "$extract_dir")
  if [[ $(echo "$top_entries" | wc -l) -eq 1 && -d "$extract_dir/$top_entries" ]]; then
    extract_dir="$extract_dir/$top_entries"
  fi

  # Find the binary inside the extracted tree.
  # 1. Exact name match (most common: bat, delta, fzf, lazygit, etc.)
  # 2. Prefix match: cmd-* (Rust triple naming: codex-x86_64-unknown-linux-gnu)
  # 3. Sole compiled-binary fallback filtered via file(1) to skip scripts
  local found_bin=""
  local pattern
  for pattern in "$cmd" "$cmd-*" "${cmd}_*"; do
    while IFS= read -r -d '' f; do
      if [[ -x "$f" ]]; then
        found_bin="$f"
        break 2
      fi
    done < <(find "$extract_dir" -name "$pattern" -type f -print0 2>/dev/null)
  done
  if [[ -z "$found_bin" ]]; then
    # Last resort: if there's exactly one compiled binary, use it.
    # Filter via file(1) to exclude shell scripts and other non-binaries.
    local -a binaries=()
    while IFS= read -r -d '' f; do
      [[ -x "$f" ]] && file "$f" | grep -qiE 'ELF|Mach-O' && binaries+=("$f")
    done < <(find "$extract_dir" -type f -print0 2>/dev/null)
    if [[ ${#binaries[@]} -eq 1 ]]; then
      found_bin="${binaries[0]}"
    fi
  fi
  if [[ -z "$found_bin" ]]; then
    rm -rf "$orig_extract_dir"
    _warn "  warning: $cmd binary not found in $name archive"
    return 1
  fi

  # Move extracted contents to ~/.local/share/<name>.
  local install_dir="$HOME/.local/share/$name"
  rm -rf "$install_dir"
  mkdir -p "$(dirname "$install_dir")"
  mv "$extract_dir" "$install_dir"
  [[ "$orig_extract_dir" != "$extract_dir" ]] && rm -rf "$orig_extract_dir"

  # Symlink the binary into PATH.
  local bin_rel="${found_bin#"$extract_dir/"}"
  ln -sf "$install_dir/$bin_rel" "$bin_path"
}

# Extract a tarball asset, find the binary, move to ~/.local/share/<name>,
# and symlink into PATH. Cleans up on failure.
# $1=name $2=cmd $3=tmp_file (downloaded archive) $4=bin_path $5=log
_binary_install_tarball() {
  local name="$1" cmd="$2" tmp_file="$3" bin_path="$4" log="$5"
  local extract_dir
  extract_dir=$(mktemp -d) || {
    rm -f "$tmp_file" "$log"
    _warn "  warning: failed to create extract dir for $name"
    return 1
  }
  if ! tar xf "$tmp_file" -C "$extract_dir" 2>/dev/null; then
    rm -rf "$extract_dir" "$tmp_file" "$log"
    _warn "  warning: failed to extract $name tarball"
    return 1
  fi
  rm -f "$tmp_file"
  _binary_install_from_extracted "$name" "$cmd" "$extract_dir" "$extract_dir" "$bin_path"
}

# Extract a zip asset, find the binary, move to ~/.local/share/<name>,
# and symlink into PATH. Cleans up on failure.
# $1=name $2=cmd $3=tmp_file (downloaded archive) $4=bin_path $5=log
_binary_install_zip() {
  local name="$1" cmd="$2" tmp_file="$3" bin_path="$4" log="$5"
  if ! command -v unzip &>/dev/null; then
    rm -f "$tmp_file" "$log"
    _warn "  warning: unzip not found — cannot install $name"
    return 1
  fi
  local extract_dir
  extract_dir=$(mktemp -d) || {
    rm -f "$tmp_file" "$log"
    _warn "  warning: failed to create extract dir for $name"
    return 1
  }
  if ! unzip -qo "$tmp_file" -d "$extract_dir" 2>/dev/null; then
    rm -rf "$extract_dir" "$tmp_file" "$log"
    _warn "  warning: failed to extract $name zip"
    return 1
  fi
  rm -f "$tmp_file"
  _binary_install_from_extracted "$name" "$cmd" "$extract_dir" "$extract_dir" "$bin_path"
}

# Install or upgrade a tool via GitHub release binary.
# Searches release assets for a single executable matching the current OS
# and arch. Prefers standalone binaries; extracts from tarballs as fallback.
# Usage: _install_binary <name> <cmd> <owner/repo>
_install_binary() {
  local name="$1" cmd="$2" gh_repo="$3"
  local bin_path="$HOME/.local/bin/$cmd"
  local current_ver="" latest_ver=""
  local log=""
  local stamp=""
  stamp=$(_dep_remote_stamp "$name" binary)
  if ! _logfile_create; then
    _warn "  warning: failed to create temp log for $name install"
  else
    log="$REPLY"
  fi
  local tmp_file
  tmp_file=$(mktemp) || {
    rm -f "$log"
    _warn "  warning: failed to create temp file for $name install"
    return 1
  }

  # Get installed version
  if [[ -x "$bin_path" ]]; then
    current_ver=$(_dep_version "$cmd")
  fi

  if [[ -n "$current_ver" ]] && _dep_remote_fresh "$stamp"; then
    rm -f "$tmp_file" "$log"
    _log_dim "  $name up to date -- $current_ver"
    return 0
  fi

  # Get latest release from GitHub API (version + asset list)
  local release_json=""
  if command -v curl &>/dev/null; then
    release_json=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/$gh_repo/releases/latest" 2>/dev/null || true)
    latest_ver=$(echo "$release_json" |
      grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  fi

  # Skip if already up to date (unless force mode)
  # Strip leading v for comparison (tags use v2.37.1, --version may not)
  if [[ "${DOT_FORCE:-0}" -ne 1 && -n "$current_ver" && -n "$latest_ver" && "${current_ver#v}" == "${latest_ver#v}" ]]; then
    rm -f "$tmp_file" "$log"
    _dep_remote_touch "$stamp" || true
    _log_dim "  $name up to date -- $current_ver"
    return 0
  fi

  if [[ -z "$latest_ver" ]]; then
    if [[ -n "$current_ver" ]]; then
      rm -f "$tmp_file" "$log"
      _log_dim "  $name $current_ver (couldn't check for updates)"
      return 0
    fi
    rm -f "$tmp_file" "$log"
    _warn "  warning: couldn't determine latest $name version"
    return 1
  fi

  # Find the right asset URL for this platform.
  local asset_url=""
  asset_url=$(_binary_find_asset "$cmd" "$gh_repo" "$latest_ver" "$release_json")

  if [[ -z "$asset_url" ]]; then
    rm -f "$tmp_file" "$log"
    _warn "  warning: no matching release asset for $name $latest_ver"
    return 1
  fi

  [[ -n "${log:-}" ]] && : >"$log"
  if ! _run_logged curl -fsSL --no-netrc "$asset_url" -o "$tmp_file"; then
    _logfile_print "$name download" "$log"
    rm -f "$tmp_file" "$log"
    _warn "  warning: failed to download $name $latest_ver"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"

  # Install: archive, compressed single binary, or direct binary.
  local asset_lower="${asset_url,,}"
  if [[ "$asset_lower" == *.tar.gz || "$asset_lower" == *.tar.xz || "$asset_lower" == *.tar.bz2 || "$asset_lower" == *.tgz ]]; then
    if ! _binary_install_tarball "$name" "$cmd" "$tmp_file" "$bin_path" "$log"; then
      return 1
    fi
  elif [[ "$asset_lower" == *.zip ]]; then
    if ! _binary_install_zip "$name" "$cmd" "$tmp_file" "$bin_path" "$log"; then
      return 1
    fi
  elif [[ "$asset_lower" == *.gz ]]; then
    if ! gzip -dc "$tmp_file" > "$bin_path" 2>/dev/null; then
      rm -f "$tmp_file" "$bin_path" "$log"
      _warn "  warning: failed to decompress $name .gz"
      return 1
    fi
    rm -f "$tmp_file"
    chmod u+x "$bin_path"
  elif [[ "$asset_lower" == *.bz2 ]]; then
    if ! bzip2 -dc "$tmp_file" > "$bin_path" 2>/dev/null; then
      rm -f "$tmp_file" "$bin_path" "$log"
      _warn "  warning: failed to decompress $name .bz2"
      return 1
    fi
    rm -f "$tmp_file"
    chmod u+x "$bin_path"
  elif [[ "$asset_lower" == *.zst ]]; then
    if ! command -v zstd &>/dev/null; then
      rm -f "$tmp_file" "$log"
      _warn "  warning: zstd not found — cannot install $name"
      return 1
    fi
    if ! zstd -df "$tmp_file" -o "$bin_path" 2>/dev/null; then
      rm -f "$tmp_file" "$log"
      _warn "  warning: failed to decompress $name .zst"
      return 1
    fi
    rm -f "$tmp_file"
    chmod u+x "$bin_path"
  else
    mv "$tmp_file" "$bin_path"
    chmod u+x "$bin_path"
  fi
  rm -f "$log"
  _dep_remote_touch "$stamp" || true

  _DEPS_CHANGED[$name]=1
  if [[ -z "$current_ver" ]]; then
    _log_ok "  $name installed -- $latest_ver"
  elif [[ "${current_ver#v}" == "${latest_ver#v}" ]]; then
    _log_ok "  $name reinstalled -- $latest_ver"
  else
    _log_ok "  $name updated -- $current_ver -> $latest_ver"
  fi
}

# Find a release asset URL matching the current OS and architecture.
# Prefers standalone binaries; falls back to .tar.gz/.tar.xz archives.
# Prints the URL to stdout; empty string if no match.
_binary_find_asset() {
  local cmd="$1" gh_repo="$2" tag="$3" release_json="$4"

  local os arch libc
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  # Detect system libc (gnu vs musl) for preferring matching assets.
  libc="gnu"
  if command -v ldd &>/dev/null && ldd --version 2>&1 | grep -qi musl; then
    libc="musl"
  fi

  # Normalize OS names (projects use various conventions)
  local os_patterns=("$os")
  case "$os" in
  darwin) os_patterns+=(macos apple osx) ;;
  linux) os_patterns+=(linux) ;;
  esac

  # Normalize arch names for matching (projects use various conventions)
  local arch_patterns=("$arch")
  case "$arch" in
  x86_64) arch_patterns+=(amd64 x64) ;;
  aarch64) arch_patterns+=(arm64) ;;
  amd64) arch_patterns+=(x86_64 x64) ;;
  arm64) arch_patterns+=(aarch64) ;;
  esac

  # Extensions to always skip (metadata, packages, installers)
  local -a _skip_exts=(
    .sha256 .sha512 .md5 .sig .asc .txt .json .zsync
    .sigstore .proof .sbom .b3 .pem .dmg .pkg .apk
    .deb .rpm .msi .appimage .flatpak .mcpb
  )

  # Archive extensions recognized for extraction.
  local -a _tar_exts=(.tar.gz .tar.xz .tar.bz2 .tgz)
  local -a _archive_exts=("${_tar_exts[@]}" .zip)

  # Try matching from the API asset list (handles any naming convention).
  # Pass 1: standalone binaries (no archives).
  # Pass 2: tar archives (.tar.gz, .tar.xz, .tar.bz2, .tgz).
  # Pass 3: zip archives (.zip) — last because tarballs are preferred.
  if [[ -n "$release_json" ]]; then
    local urls
    urls=$(echo "$release_json" |
      grep -o '"browser_download_url":[[:space:]]*"[^"]*"' |
      cut -d'"' -f4)

    if [[ -n "$urls" ]]; then
      local url url_lower arch_pat os_pat ext skip os_match is_archive
      local pass
      for pass in plain tarball zip; do
        local _pass_fallback=""
        while IFS= read -r url; do
          url_lower="${url,,}"
          # Must match at least one OS pattern (case-insensitive)
          os_match=0
          for os_pat in "${os_patterns[@]}"; do
            [[ "$url_lower" == *"$os_pat"* ]] && {
              os_match=1
              break
            }
          done
          [[ $os_match -eq 1 ]] || continue
          # Skip metadata and package files
          skip=0
          for ext in "${_skip_exts[@]}"; do
            [[ "$url_lower" == *"$ext" ]] && {
              skip=1
              break
            }
          done
          [[ $skip -eq 1 ]] && continue
          # Pass-specific filtering
          if [[ "$pass" == "plain" ]]; then
            is_archive=0
            for ext in "${_archive_exts[@]}"; do
              [[ "$url_lower" == *"$ext" ]] && { is_archive=1; break; }
            done
            [[ $is_archive -eq 0 ]] || continue
          elif [[ "$pass" == "tarball" ]]; then
            is_archive=0
            for ext in "${_tar_exts[@]}"; do
              [[ "$url_lower" == *"$ext" ]] && { is_archive=1; break; }
            done
            [[ $is_archive -eq 1 ]] || continue
          else
            [[ "$url_lower" == *.zip ]] || continue
          fi
          for arch_pat in "${arch_patterns[@]}"; do
            if [[ "$url_lower" == *"$arch_pat"* ]]; then
              # Prefer matching libc variant (gnu vs musl) on Linux
              if [[ "$os" == "linux" && "$url_lower" == *"$libc"* ]]; then
                echo "$url"
                return 0
              fi
              # Track first match as fallback (non-libc-specific or wrong libc)
              [[ -z "${_pass_fallback:-}" ]] && _pass_fallback="$url"
              break
            fi
          done
        done <<<"$urls"
        # Use fallback if no libc-preferred match found in this pass
        if [[ -n "${_pass_fallback:-}" ]]; then
          echo "$_pass_fallback"
          return 0
        fi
      done
    fi
  fi

  # Fallback: try common URL patterns when API didn't help
  local base="https://github.com/$gh_repo/releases/download/$tag"
  local o a
  for o in "${os_patterns[@]}"; do
    for a in "${arch_patterns[@]}"; do
      local candidates=(
        "$base/$cmd.${o}-${a}"
        "$base/${cmd}-${o}-${a}"
        "$base/${cmd}_${o}_${a}"
      )
      local c
      for c in "${candidates[@]}"; do
        if curl -fsSL --no-netrc --head "$c" &>/dev/null; then
          echo "$c"
          return 0
        fi
      done
    done
  done
}

# ---------------------------------------------------------------------------
# Dispatcher and hooks
# ---------------------------------------------------------------------------

# Route a dep registry entry to the appropriate install method.
_install_dep() {
  local entry="$1"
  _dep_parse "$entry"
  if ! _platform_match "$_platforms"; then
    return 0
  fi
  case "$_method" in
  pkg)
    local resolved_pkg=""
    resolved_pkg=$(_pkg_resolve "$_name" "$_pkg_overrides")
    if _dep_exists "$_cmd" "$_cmd_alt" "$resolved_pkg"; then
      _PKG_PRESENT+=("$_name")
      # If the package exists but the expected command is still missing,
      # run the post hook so it can expose wrapper/symlinked binaries.
      if ! _dep_exists "$_cmd" "$_cmd_alt"; then
        _DEPS_CHANGED[$_name]=1
      fi
      return 0
    fi
    _pkg_queue "$_name" "$_pkg_overrides"
    ;;
  git)
    _install_from_github "$_name" "$_repo" "$HOME/$_dir"
    ;;
  binary)
    _install_binary "$_name" "$_cmd" "$_repo"
    ;;
  custom)
    # Entirely managed by the post-install hook (post()).
    # Run only when the hook is due so no-op updates stay cheap.
    if _dep_hook_due "$_name"; then
      _DEPS_CHANGED[$_name]=1
    fi
    ;;
  esac
}

# Run post-install hooks for all deps.
# Each hook file defines post() and/or status() — sourced per-dep to avoid collisions.
_run_post_hooks() {
  local hooks_dir="$HOME/.config/dot/deps-hooks.d"

  for entry in "${_DEPS[@]}"; do
    local name="${entry%%|*}"
    local hook_file="$hooks_dir/$name.sh"
    [[ -f "$hook_file" ]] || continue
    unset -f status post 2>/dev/null
    # shellcheck source=/dev/null
    . "$hook_file" || {
      _warn "  warning: failed to source $hook_file"
      continue
    }
    if declare -f status &>/dev/null; then
      status || true
    fi
    unset -f status post 2>/dev/null
  done

  [[ ${#_DEPS_CHANGED[@]} -eq 0 ]] && return 0

  for entry in "${_DEPS[@]}"; do
    local name="${entry%%|*}"
    [[ -n "${_DEPS_CHANGED[$name]+x}" ]] || continue
    local hook_file="$hooks_dir/$name.sh"
    [[ -f "$hook_file" ]] || continue
    unset -f post status 2>/dev/null
    # shellcheck source=/dev/null
    . "$hook_file" || {
      _warn "  warning: failed to source $hook_file"
      continue
    }
    if declare -f post &>/dev/null; then
      if post; then
        _dep_hook_touch "$name" || true
      fi
    fi
    unset -f post status 2>/dev/null
  done
}

# Install or upgrade all managed dependencies.
_update_deps() {
  if ! command -v git &>/dev/null; then
    _warn "error: git is required for dotbootstrap"
    return 1
  fi

  _dep_load
  _pkg_detect
  _PKG_BATCH=()
  _PKG_BATCH_NAMES=()
  _PKG_PRESENT=()
  declare -gA _DEPS_CHANGED=()

  _log_header "==> Installing/upgrading tools..."

  for entry in "${_DEPS[@]}"; do
    _install_dep "$entry" || true
  done

  if [[ ${#_PKG_PRESENT[@]} -gt 0 ]]; then
    local cols=72
    _log_dim "  system:"
    local line="   "
    for pkg in "${_PKG_PRESENT[@]}"; do
      if ((${#line} + ${#pkg} + 1 > cols)); then
        _log_dim "$line"
        line="    $pkg"
      else
        line+=" $pkg"
      fi
    done
    [[ -n "$line" ]] && _log_dim "$line"
  fi
  _pkg_install_batch

  # Force mode: mark all deps as changed so all hooks run
  if [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
    for entry in "${_DEPS[@]}"; do
      _DEPS_CHANGED["${entry%%|*}"]=1
    done
  fi

  _run_post_hooks

  _install_cron || true
}
