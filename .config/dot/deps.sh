#!/bin/bash
# Dependency management for dotbootstrap.
# Sourced by helpers.sh. Requires _log, _warn, DOT_QUIET from helpers.sh.
# Set DOT_FORCE=1 to force reinstall of all deps and re-run all hooks.

# ---------------------------------------------------------------------------
# Dep registry — parse ~/.config/dot/deps.conf
# ---------------------------------------------------------------------------

# Parse deps.conf into _DEPS array. Each entry is pipe-delimited.
_dep_load() {
  _DEPS=()
  local conf="$HOME/.config/dot/deps.conf"
  if [[ ! -f "$conf" ]]; then
    _warn "  warning: $conf not found — skipping dependency install"
    return 0
  fi
  local line
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
  done < "$conf"
}

# Split a pipe-delimited registry entry into named variables.
# Sets: _name, _method, _cmd, _cmd_alt, _pkg_overrides, _repo, _dir
_dep_parse() {
  local entry="$1"
  IFS='|' read -r _name _method _cmd _cmd_alt _pkg_overrides _repo _dir <<< "$entry"
  # Replace - with empty
  if [[ "$_cmd" == "-" ]]; then _cmd=""; fi
  if [[ "$_cmd_alt" == "-" ]]; then _cmd_alt=""; fi
  if [[ "$_pkg_overrides" == "-" ]]; then _pkg_overrides=""; fi
  if [[ "$_repo" == "-" ]]; then _repo=""; fi
  if [[ "$_dir" == "-" ]]; then _dir=""; fi
  # Default cmd to name
  if [[ -z "$_cmd" ]]; then _cmd="$_name"; fi
}

# Check if a dependency is installed. Returns 0 if cmd or cmd_alt is found.
_dep_exists() {
  local cmd="${1:-}" alt="${2:-}"
  if [[ -z "$cmd" ]]; then return 1; fi
  if command -v "$cmd" &>/dev/null; then return 0; fi
  if [[ -n "$alt" ]] && command -v "$alt" &>/dev/null; then return 0; fi
  return 1
}

# Get installed version of a command.
_dep_version() {
  local cmd="${1:-}"
  if [[ -z "$cmd" ]]; then return 1; fi
  "$cmd" --version 2>/dev/null | head -1 | awk '{print $2}'
}

# ---------------------------------------------------------------------------
# Package manager abstraction
# ---------------------------------------------------------------------------

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
    IFS=',' read -ra pairs <<< "$overrides"
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
_pkg_queue() {
  local name="$1" overrides="${2:-}"
  local resolved
  resolved=$(_pkg_resolve "$name" "$overrides")
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

  # Check sudo access for non-brew managers before attempting install
  if [[ "$_PKG_MGR" != "brew" && "$(id -u)" -ne 0 ]]; then
    if ! sudo -n true 2>/dev/null; then
      # No passwordless sudo — try interactively, but don't abort on failure
      if ! sudo true 2>/dev/null; then
        _warn "  warning: sudo not available — cannot install: ${_PKG_BATCH[*]}"
        return 0
      fi
    fi
  fi

  _log "  installing: ${_PKG_BATCH[*]}"
  local rc=0
  local log=""
  if ! _logfile_create log; then
    _warn "  warning: failed to create temp log for package install"
  fi
  # shellcheck disable=SC2024  # Intentionally capture sudo command output in a user-owned temp log.
  case "$_PKG_MGR" in
    brew)
      if [[ -n "$log" ]]; then
        brew install "${_PKG_BATCH[@]}" >"$log" 2>&1 || rc=$?
      else
        brew install "${_PKG_BATCH[@]}" || rc=$?
      fi
      ;;
    apt)
      sudo apt-get update -qq >/dev/null 2>&1 || true
      if [[ -n "$log" ]]; then
        sudo apt-get install -y "${_PKG_BATCH[@]}" >"$log" 2>&1 || rc=$?
      else
        sudo apt-get install -y "${_PKG_BATCH[@]}" || rc=$?
      fi
      ;;
    dnf)
      if [[ -n "$log" ]]; then
        sudo dnf install -y "${_PKG_BATCH[@]}" >"$log" 2>&1 || rc=$?
      else
        sudo dnf install -y "${_PKG_BATCH[@]}" || rc=$?
      fi
      ;;
    pacman)
      if [[ -n "$log" ]]; then
        sudo pacman -Sy --needed --noconfirm "${_PKG_BATCH[@]}" >"$log" 2>&1 || rc=$?
      else
        sudo pacman -Sy --needed --noconfirm "${_PKG_BATCH[@]}" || rc=$?
      fi
      ;;
  esac

  # On batch failure, retry individually
  if [[ $rc -ne 0 ]]; then
    _logfile_print "package manager" "$log"
    _warn "  warning: batch install failed, retrying individually..."
    local pkg
    for pkg in "${_PKG_BATCH[@]}"; do
      rc=0
      [[ -n "$log" ]] && : > "$log"
      # shellcheck disable=SC2024  # Intentionally capture sudo command output in a user-owned temp log.
      case "$_PKG_MGR" in
        brew)
          if [[ -n "$log" ]]; then
            brew install "$pkg" >"$log" 2>&1 || rc=$?
          else
            brew install "$pkg" || rc=$?
          fi
          ;;
        apt)
          if [[ -n "$log" ]]; then
            sudo apt-get install -y "$pkg" >"$log" 2>&1 || rc=$?
          else
            sudo apt-get install -y "$pkg" || rc=$?
          fi
          ;;
        dnf)
          if [[ -n "$log" ]]; then
            sudo dnf install -y "$pkg" >"$log" 2>&1 || rc=$?
          else
            sudo dnf install -y "$pkg" || rc=$?
          fi
          ;;
        pacman)
          if [[ -n "$log" ]]; then
            sudo pacman -Sy --needed --noconfirm "$pkg" >"$log" 2>&1 || rc=$?
          else
            sudo pacman -Sy --needed --noconfirm "$pkg" || rc=$?
          fi
          ;;
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
      local hash; hash=$(git -C "$dir" log -1 --format='%h' 2>/dev/null || true)
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
_install_from_github() {
  local name="$1" default_repo="$2" install_dir="$3"
  local upper="${name^^}"; upper="${upper//-/_}"
  local env_var="DOTBOOTSTRAP_${upper}_REPO"
  local repo="${!env_var:-https://github.com/$default_repo}"
  local tarball_url tmp_dir
  local local_clone="$HOME/git/$name"

  # Prefer local clone — symlink for live development
  if [[ -d "$local_clone" ]]; then
    rm -rf "$install_dir"
    mkdir -p "$(dirname "$install_dir")"
    ln -sfn "$local_clone" "$install_dir"
    _link_bin "$name" "$install_dir"
    local ver; ver=$(_get_version "$local_clone")
    _DEPS_CHANGED[$name]=1
    _log "  $name -> $local_clone (local clone)${ver:+ -- $ver}"
    return 0
  fi

  local log=""
  if ! _logfile_create log; then
    _warn "  warning: failed to create temp log for $name install"
  fi

  # Existing git clone — pull to update
  if [[ -d "$install_dir/.git" ]]; then
    local head_before; head_before=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
    if [[ -n "$log" ]] && git -C "$install_dir" pull --ff-only --quiet >"$log" 2>&1; then
      _link_bin "$name" "$install_dir"
      local head_after; head_after=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
      local ver; ver=$(_get_version "$install_dir")
      if [[ "$head_before" != "$head_after" ]]; then
        _DEPS_CHANGED[$name]=1
        _log "  $name updated${ver:+ -- $ver}"
      elif [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
        _DEPS_CHANGED[$name]=1
        _log "  $name reinstalled${ver:+ -- $ver}"
      else
        _log "  $name up to date${ver:+ -- $ver}"
      fi
    elif [[ -z "$log" ]] && git -C "$install_dir" pull --ff-only --quiet 2>/dev/null; then
      _link_bin "$name" "$install_dir"
      local head_after; head_after=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
      local ver; ver=$(_get_version "$install_dir")
      if [[ "$head_before" != "$head_after" ]]; then
        _DEPS_CHANGED[$name]=1
        _log "  $name updated${ver:+ -- $ver}"
      elif [[ "${DOT_FORCE:-0}" -eq 1 ]]; then
        _DEPS_CHANGED[$name]=1
        _log "  $name reinstalled${ver:+ -- $ver}"
      else
        _log "  $name up to date${ver:+ -- $ver}"
      fi
    else
      _logfile_print "$name update" "$log"
      _warn "  warning: $name update failed"
    fi
    rm -f "$log"
    return 0
  fi

  # Capture current version before overwriting (for tarball/clone installs).
  local ver_before; ver_before=$(_get_version "$install_dir")

  # Try GitHub release tarball. Extract owner/repo from URL.
  # Strip auth to prevent stale tokens from causing 401 on public repos.
  local gh_repo=""
  if [[ "$repo" =~ github\.com[:/]([^/]+/[^/.]+) ]]; then
    gh_repo="${BASH_REMATCH[1]}"
  fi
  if [[ -n "$gh_repo" ]] && command -v curl &>/dev/null; then
    tarball_url=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/$gh_repo/releases/latest" 2>/dev/null \
      | grep -o '"browser_download_url":[[:space:]]*"[^"]*\.tar\.gz"' \
      | head -1 | cut -d'"' -f4)
  fi

  if [[ -n "${tarball_url:-}" ]]; then
    tmp_dir=$(mktemp -d)
    if [[ -n "$log" ]] \
      && curl -fsSL "$tarball_url" 2>"$log" | tar xz -C "$tmp_dir" >>"$log" 2>&1; then
      rm -rf "$install_dir"
      mkdir -p "$install_dir"
      # Tarball has a top-level dir (e.g., ds-v0.0.1/); move contents up
      mv "$tmp_dir"/*/* "$install_dir/" 2>/dev/null || mv "$tmp_dir"/* "$install_dir/"
      rm -rf "$tmp_dir"
    elif [[ -z "$log" ]] && curl -fsSL "$tarball_url" | tar xz -C "$tmp_dir" 2>/dev/null; then
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
    [[ -n "$log" ]] && : > "$log"
    if [[ -n "$log" ]] && ! git clone --depth 1 "$repo" "$clone_tmp" >"$log" 2>&1; then
      rm -rf "$clone_tmp"
      _logfile_print "$name clone" "$log"
      rm -f "$log"
      _warn "  warning: failed to clone $name (network unreachable?)"
      return 1
    elif [[ -z "$log" ]] && ! git clone --depth 1 "$repo" "$clone_tmp" 2>/dev/null; then
      rm -rf "$clone_tmp"
      _warn "  warning: failed to clone $name (network unreachable?)"
      return 1
    fi
    rm -rf "$install_dir"
    mv "$clone_tmp" "$install_dir"
  fi

  _link_bin "$name" "$install_dir"
  rm -f "$log"
  local ver; ver=$(_get_version "$install_dir")
  local method="git clone"
  if [[ -n "${tarball_url:-}" ]]; then method="release tarball"; fi
  if [[ -n "$ver_before" && "$ver_before" == "$ver" ]]; then
    _log "  $name up to date ($method)${ver:+ -- $ver}"
  else
    _DEPS_CHANGED[$name]=1
    _log "  $name installed ($method)${ver:+ -- $ver}"
  fi
}

# Install or upgrade a tool via GitHub AppImage release.
# Linux-only — macOS fallback to pkg is handled by the dispatcher.
# Usage: _install_appimage <name> <cmd> <owner/repo>
_install_appimage() {
  local name="$1" cmd="$2" gh_repo="$3"
  local bin_path="$HOME/.local/bin/$cmd"
  local current_ver="" latest_ver=""
  local log=""
  if ! _logfile_create log; then
    _warn "  warning: failed to create temp log for $name install"
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

  # Get latest release version from GitHub API
  if command -v curl &>/dev/null; then
    latest_ver=$(curl -fsSL --no-netrc -H "Authorization:" \
      "https://api.github.com/repos/$gh_repo/releases/latest" 2>/dev/null \
      | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  fi

  # Skip if already up to date (unless force mode)
  if [[ "${DOT_FORCE:-0}" -ne 1 && -n "$current_ver" && -n "$latest_ver" && "$current_ver" == "$latest_ver" ]]; then
    rm -f "$tmp_file" "$log"
    _log "  $name up to date -- $current_ver"
    return 0
  fi

  if [[ -z "$latest_ver" ]]; then
    if [[ -n "$current_ver" ]]; then
      rm -f "$tmp_file" "$log"
      _log "  $name $current_ver (couldn't check for updates)"
      return 0
    fi
    rm -f "$tmp_file" "$log"
    _warn "  warning: couldn't determine latest $name version"
    return 1
  fi

  # Try platform-specific AppImage name, then legacy name
  local arch
  arch=$(uname -m)
  local urls=(
    "https://github.com/$gh_repo/releases/download/$latest_ver/$cmd-linux-${arch}.appimage"
    "https://github.com/$gh_repo/releases/download/$latest_ver/$cmd.appimage"
  )

  local downloaded=0
  for url in "${urls[@]}"; do
    [[ -n "$log" ]] && : > "$log"
    if [[ -n "$log" ]] && curl -fsSL "$url" -o "$tmp_file" >"$log" 2>&1; then
      downloaded=1
      break
    fi
    if [[ -z "$log" ]] && curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
      downloaded=1
      break
    fi
  done

  if [[ $downloaded -eq 0 ]]; then
    _logfile_print "$name download" "$log"
    rm -f "$tmp_file" "$log"
    _warn "  warning: failed to download $name $latest_ver"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  mv "$tmp_file" "$bin_path"
  chmod u+x "$bin_path"
  rm -f "$log"

  _DEPS_CHANGED[$name]=1
  if [[ -n "$current_ver" ]]; then
    _log "  $name updated -- $current_ver -> $latest_ver"
  else
    _log "  $name installed -- $latest_ver"
  fi
}

# ---------------------------------------------------------------------------
# Dispatcher and hooks
# ---------------------------------------------------------------------------

# Route a dep registry entry to the appropriate install method.
_install_dep() {
  local entry="$1"
  _dep_parse "$entry"
  case "$_method" in
    pkg)
      if _dep_exists "$_cmd" "$_cmd_alt"; then
        _PKG_PRESENT+=("$_name")
        return 0
      fi
      _pkg_queue "$_name" "$_pkg_overrides"
      ;;
    git)
      _install_from_github "$_name" "$_repo" "$HOME/$_dir"
      ;;
    appimage)
      if [[ "$(uname -s)" == "Darwin" ]]; then
        if _dep_exists "$_cmd" "$_cmd_alt"; then return 0; fi
        _pkg_queue "$_name" "$_pkg_overrides"
      else
        _install_appimage "$_name" "$_cmd" "$_repo"
      fi
      ;;
  esac
}

# Run post-install hooks for all deps.
# Hook functions are defined in deps-hooks.sh.
_run_post_hooks() {
  [[ ${#_DEPS_CHANGED[@]} -eq 0 ]] && return 0
  local hooks_file="$HOME/.config/dot/deps-hooks.sh"
  # shellcheck source=deps-hooks.sh
  [[ -f "$hooks_file" ]] && . "$hooks_file"
  for entry in "${_DEPS[@]}"; do
    local name="${entry%%|*}"
    [[ -n "${_DEPS_CHANGED[$name]+x}" ]] || continue
    local hook="_post_${name//-/_}"
    if declare -f "$hook" &>/dev/null; then
      "$hook" || true
    fi
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

  _log "==> Installing/upgrading tools..."

  for entry in "${_DEPS[@]}"; do
    _install_dep "$entry" || true
  done

  [[ ${#_PKG_PRESENT[@]} -gt 0 ]] && _log "  system: ${_PKG_PRESENT[*]}"
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
