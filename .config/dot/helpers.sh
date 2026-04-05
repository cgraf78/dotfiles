#!/bin/bash
# Shared helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
WORK_DIR="$HOME/.dotfiles-work"

# Quiet mode — suppresses non-essential output. Set by `dot update --cron`.
DOT_QUIET="${DOT_QUIET:-0}"

# Print a message unless quiet mode is active.
_log() {
  [[ "$DOT_QUIET" -eq 1 ]] || echo "$@"
}

# Print a message to stderr regardless of quiet mode.
_warn() {
  echo "$@" >&2
}

# Restore git-tracked versions of skip-worktree files so pull won't
# conflict with work symlinks.  The work bootstrap re-symlinks and
# re-sets skip-worktree after pull.
_unstash_work_overrides() {
  [[ -d "$WORK_DIR" ]] || return 0
  local files
  files=$($GIT ls-files -v 2>/dev/null | awk '/^S /{print $2}') || true
  [[ -n "$files" ]] || return 0
  echo "$files" | while IFS= read -r f; do
    $GIT update-index --no-skip-worktree "$f" 2>/dev/null || true
    $GIT checkout -- "$f" 2>/dev/null || true
  done
}

# Pull work repo and re-run its bootstrap (symlinks, app config merges).
_pull_work_repo() {
  [[ -d "$WORK_DIR" ]] || return 0
  if [[ -d "$WORK_DIR/.git" ]]; then
    _log "==> Pulling work dotfiles..."
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      git -C "$WORK_DIR" pull --quiet "$@" || _warn "  warning: work dotfiles pull failed"
    else
      git -C "$WORK_DIR" pull "$@" || _warn "  warning: work dotfiles pull failed"
    fi
  fi
  if [[ -x "$WORK_DIR/bootstrap" ]]; then
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      "$WORK_DIR/bootstrap" >/dev/null || true
    else
      "$WORK_DIR/bootstrap" || true
    fi
  fi
}

# Push work repo.
_push_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  _log "==> Pushing work dotfiles..."
  git -C "$WORK_DIR" push "$@" || _warn "  warning: work dotfiles push failed"
}

# Run all app config merge scripts (iTerm2, Karabiner, VS Code, etc.).
_run_merges() {
  for _script in "$HOME/.config/dot"/merge-*.sh; do
    [[ -f "$_script" ]] || continue
    # shellcheck source=/dev/null
    . "$_script"
    _fn="merge_${_script##*merge-}"; _fn="${_fn%.sh}"
    if [[ "$DOT_QUIET" -eq 1 ]]; then
      "$_fn" >/dev/null || true
    else
      "$_fn" || true
    fi
  done
}

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
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    # Normalize whitespace to pipe delimiter
    local fields
    # shellcheck disable=SC2086  # intentional word splitting
    fields=$(echo $line)
    _DEPS+=("${fields// /|}")
  done < "$conf"
}

# Split a pipe-delimited registry entry into named variables.
# Sets: _name, _method, _cmd, _cmd_alt, _pkg_overrides, _repo, _dir
_dep_parse() {
  local entry="$1"
  IFS='|' read -r _name _method _cmd _cmd_alt _pkg_overrides _repo _dir <<< "$entry"
  # Replace - with empty
  [[ "$_cmd" == "-" ]] && _cmd="" || true
  [[ "$_cmd_alt" == "-" ]] && _cmd_alt="" || true
  [[ "$_pkg_overrides" == "-" ]] && _pkg_overrides="" || true
  [[ "$_repo" == "-" ]] && _repo="" || true
  [[ "$_dir" == "-" ]] && _dir="" || true
  # Default cmd to name
  [[ -z "$_cmd" ]] && _cmd="$_name" || true
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
  [[ -z "$cmd" ]] && return 1
  "$cmd" --version 2>/dev/null | head -1 | awk '{print $2}'
}

# ---------------------------------------------------------------------------
# Package manager abstraction
# ---------------------------------------------------------------------------

# Detect available package manager. Sets _PKG_MGR.
_pkg_detect() {
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
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
    return 1
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
  case "$_PKG_MGR" in
    brew)
      brew install "${_PKG_BATCH[@]}" 2>/dev/null || rc=$?
      ;;
    apt)
      sudo apt-get update -qq 2>/dev/null || true
      sudo apt-get install -y "${_PKG_BATCH[@]}" 2>/dev/null || rc=$?
      ;;
    dnf)
      sudo dnf install -y "${_PKG_BATCH[@]}" 2>/dev/null || rc=$?
      ;;
    pacman)
      sudo pacman -S --needed --noconfirm "${_PKG_BATCH[@]}" 2>/dev/null || rc=$?
      ;;
  esac

  # On batch failure, retry individually
  if [[ $rc -ne 0 ]]; then
    _warn "  warning: batch install failed, retrying individually..."
    local pkg
    for pkg in "${_PKG_BATCH[@]}"; do
      case "$_PKG_MGR" in
        brew)    brew install "$pkg" 2>/dev/null || _warn "  warning: failed to install $pkg" ;;
        apt)     sudo apt-get install -y "$pkg" 2>/dev/null || _warn "  warning: failed to install $pkg" ;;
        dnf)     sudo dnf install -y "$pkg" 2>/dev/null || _warn "  warning: failed to install $pkg" ;;
        pacman)  sudo pacman -S --needed --noconfirm "$pkg" 2>/dev/null || _warn "  warning: failed to install $pkg" ;;
      esac
    done
  fi

  # Mark all batch-installed deps as changed
  local _i
  for _i in "${!_PKG_BATCH_NAMES[@]}"; do
    _DEPS_CHANGED[${_PKG_BATCH_NAMES[$_i]}]=1
  done
}

# ---------------------------------------------------------------------------
# Tool install/upgrade helpers
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
      [[ -n "$hash" ]] && ver="commit $hash"
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

  # Existing git clone — pull to update
  if [[ -d "$install_dir/.git" ]]; then
    local head_before; head_before=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
    if git -C "$install_dir" pull --ff-only --quiet 2>/dev/null; then
      _link_bin "$name" "$install_dir"
      local head_after; head_after=$(git -C "$install_dir" rev-parse HEAD 2>/dev/null || true)
      local ver; ver=$(_get_version "$install_dir")
      if [[ "$head_before" != "$head_after" ]]; then
        _DEPS_CHANGED[$name]=1
        _log "  $name updated${ver:+ -- $ver}"
      else
        _log "  $name up to date${ver:+ -- $ver}"
      fi
    else
      _warn "  warning: $name update failed"
    fi
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
    if curl -fsSL "$tarball_url" | tar xz -C "$tmp_dir" 2>/dev/null; then
      rm -rf "$install_dir"
      mkdir -p "$install_dir"
      # Tarball has a top-level dir (e.g., ds-v0.0.1/); move contents up
      mv "$tmp_dir"/*/* "$install_dir/" 2>/dev/null || mv "$tmp_dir"/* "$install_dir/"
      rm -rf "$tmp_dir"
    else
      rm -rf "$tmp_dir"
      _warn "  warning: failed to download $name release (trying git clone)"
      tarball_url=""
    fi
  fi

  # Fallback: git clone to a temp dir first so we don't destroy an existing
  # install on failure (e.g. network unreachable).
  if [[ -z "${tarball_url:-}" ]]; then
    if ! command -v git &>/dev/null; then
      _warn "  warning: no curl release and no git — cannot install $name"
      return 1
    fi
    local clone_tmp="${install_dir}.tmp.$$"
    rm -rf "$clone_tmp"
    if ! git clone --depth 1 "$repo" "$clone_tmp" 2>/dev/null; then
      rm -rf "$clone_tmp"
      _warn "  warning: failed to clone $name (network unreachable?)"
      return 1
    fi
    rm -rf "$install_dir"
    mv "$clone_tmp" "$install_dir"
  fi

  _link_bin "$name" "$install_dir"
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

# ---------------------------------------------------------------------------
# Worktree dirty check
# ---------------------------------------------------------------------------

# Returns 0 (true) if there are uncommitted changes in either repo.
_is_worktree_dirty() {
  if [[ -d "$DOTFILES" ]]; then
    if ! $GIT diff-index --quiet HEAD 2>/dev/null; then
      return 0
    fi
  fi
  if [[ -d "$WORK_DIR/.git" ]]; then
    if ! git -C "$WORK_DIR" diff-index --quiet HEAD 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

# Attempt to resolve dirty worktrees caused by dotsync writing files that
# match what's on the remote.  Fetches origin, then for each dirty file
# checks whether its working-tree content matches origin/main.  If every
# dirty file matches, discards the local copy (the pull will bring the
# same content).  Returns 0 if both repos are clean after resolution.
_try_resolve_dirty() {
  local dirty=0
  if [[ -d "$DOTFILES" ]] && ! $GIT diff-index --quiet HEAD 2>/dev/null; then
    $GIT fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote personal; then
      $GIT checkout -- . 2>/dev/null || true
    else
      dirty=1
    fi
  fi
  if [[ -d "$WORK_DIR/.git" ]] && ! git -C "$WORK_DIR" diff-index --quiet HEAD 2>/dev/null; then
    git -C "$WORK_DIR" fetch --quiet origin 2>/dev/null || true
    if _dirty_files_match_remote work; then
      git -C "$WORK_DIR" checkout -- . 2>/dev/null || true
    else
      dirty=1
    fi
  fi
  return "$dirty"
}

# Check if every dirty file in a repo matches the content on a remote ref.
# $1 = "personal" or "work"
_dirty_files_match_remote() {
  local repo="$1" remote_ref="origin/main"
  local dirty_files
  if [[ "$repo" == "personal" ]]; then
    dirty_files=$($GIT diff-index --name-only HEAD 2>/dev/null) || return 1
    $GIT rev-parse --verify "$remote_ref" &>/dev/null || return 1
    while IFS= read -r f; do
      local work_hash remote_hash
      # diff-index paths are relative to work-tree ($HOME for bare repo)
      work_hash=$($GIT hash-object "$HOME/$f" 2>/dev/null) || return 1
      remote_hash=$($GIT rev-parse "$remote_ref:$f" 2>/dev/null) || return 1
      [[ "$work_hash" == "$remote_hash" ]] || return 1
    done <<< "$dirty_files"
  else
    dirty_files=$(git -C "$WORK_DIR" diff-index --name-only HEAD 2>/dev/null) || return 1
    git -C "$WORK_DIR" rev-parse --verify "$remote_ref" &>/dev/null || return 1
    while IFS= read -r f; do
      local work_hash remote_hash
      work_hash=$(git -C "$WORK_DIR" hash-object "$WORK_DIR/$f" 2>/dev/null) || return 1
      remote_hash=$(git -C "$WORK_DIR" rev-parse "$remote_ref:$f" 2>/dev/null) || return 1
      [[ "$work_hash" == "$remote_hash" ]] || return 1
    done <<< "$dirty_files"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Cron install from tracked file
# ---------------------------------------------------------------------------

DOT_CRON_FILE="$HOME/.config/dot/cron"
DOT_CRON_LOCAL="$HOME/.config/dot/cron.local"
DOT_CRON_MARKER="# dot-managed-cron"

# Build a clean PATH for cron from the current PATH.
# Keeps: $HOME dirs, /opt/homebrew, /usr/local, and standard system dirs.
# Drops: obscure system dirs (cryptex, munki, etc.) that clutter the crontab.
_cron_path() {
  local result="" dir _dirs
  IFS=: read -ra _dirs <<< "$HOME/.local/bin:$PATH"
  for dir in "${_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    [[ ":$result:" == *":$dir:"* ]] && continue
    # Keep user dirs, homebrew, /usr/local, and standard system dirs.
    case "$dir" in
      "$HOME"/*|/opt/homebrew/*|/usr/local/bin|/usr/bin|/bin|/usr/sbin|/sbin) ;;
      *) continue ;;
    esac
    result="${result:+$result:}$dir"
  done
  echo "$result"
}

# Parse a cron file: expand $HOME in entries, skip comments/blanks.
# Appends processed lines to $DOT_CRON_PARSED (caller must initialize).
_parse_cron_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    line="${line//\$HOME/$HOME}"
    if [[ -n "$DOT_CRON_PARSED" ]]; then
      DOT_CRON_PARSED="$DOT_CRON_PARSED"$'\n'"$line"
    else
      DOT_CRON_PARSED="$line"
    fi
  done < "$file"
}

# Install cron entries from ~/.config/dot/cron (tracked) and
# ~/.config/dot/cron.local (machine-local, untracked) into the user crontab.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment.
# Idempotent — skips if the installed block already matches.
_install_cron() {
  [[ -f "$DOT_CRON_FILE" || -f "$DOT_CRON_LOCAL" ]] || return 0

  DOT_CRON_PARSED=""
  _parse_cron_file "$DOT_CRON_FILE"
  _parse_cron_file "$DOT_CRON_LOCAL"

  local block_start="$DOT_CRON_MARKER begin"
  local block_end="$DOT_CRON_MARKER end"
  local current
  current=$(crontab -l 2>/dev/null || true)

  # No active entries — strip any existing managed block and return.
  if [[ -z "$DOT_CRON_PARSED" ]]; then
    if [[ "$current" == *"$block_start"* ]]; then
      local stripped
      stripped=$(echo "$current" | sed "/$block_start/,/$block_end/d")
      if [[ -n "$stripped" ]]; then
        echo "$stripped" | crontab -
      else
        crontab -r 2>/dev/null || true
      fi
      _log "  cron entries removed"
    fi
    return 0
  fi

  local cron_path
  cron_path=$(_cron_path)
  local managed_block="$block_start"$'\n'"PATH=$cron_path"$'\n'"$DOT_CRON_PARSED"$'\n'"$block_end"

  # Already installed with same content — nothing to do.
  if [[ "$current" == *"$managed_block"* ]]; then
    _log "  cron up to date"
    return 0
  fi

  # Strip any existing managed block.
  local filtered
  if [[ "$current" == *"$block_start"* ]]; then
    filtered=$(echo "$current" | sed "/$block_start/,/$block_end/d")
  else
    filtered="$current"
  fi

  # Append the new managed block.
  local new_crontab
  if [[ -n "$filtered" ]]; then
    new_crontab="$filtered"$'\n\n'"$managed_block"
  else
    new_crontab="$managed_block"
  fi

  echo "$new_crontab" | crontab -
  _log "  cron installed"
}

# Install or upgrade a tool via GitHub AppImage release.
# Linux-only — macOS fallback to pkg is handled by the dispatcher.
# Usage: _install_appimage <name> <cmd> <owner/repo>
_install_appimage() {
  local name="$1" cmd="$2" gh_repo="$3"
  local bin_path="$HOME/.local/bin/$cmd"
  local current_ver="" latest_ver=""

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

  # Skip if already up to date
  if [[ -n "$current_ver" && -n "$latest_ver" && "$current_ver" == "$latest_ver" ]]; then
    _log "  $name up to date -- $current_ver"
    return 0
  fi

  if [[ -z "$latest_ver" ]]; then
    if [[ -n "$current_ver" ]]; then
      _log "  $name $current_ver (couldn't check for updates)"
      return 0
    fi
    _warn "  warning: couldn't determine latest $name version"
    return 1
  fi

  # Try platform-specific AppImage name, then legacy name
  local tmp_file
  tmp_file=$(mktemp)
  local arch
  arch=$(uname -m)
  local urls=(
    "https://github.com/$gh_repo/releases/download/$latest_ver/$cmd-linux-${arch}.appimage"
    "https://github.com/$gh_repo/releases/download/$latest_ver/$cmd.appimage"
  )

  local downloaded=0
  for url in "${urls[@]}"; do
    if curl -fsSL "$url" -o "$tmp_file" 2>/dev/null; then
      downloaded=1
      break
    fi
  done

  if [[ $downloaded -eq 0 ]]; then
    rm -f "$tmp_file"
    _warn "  warning: failed to download $name $latest_ver"
    return 1
  fi

  mkdir -p "$HOME/.local/bin"
  mv "$tmp_file" "$bin_path"
  chmod u+x "$bin_path"

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
# Hook functions are defined in dep-hooks.sh.
_run_post_hooks() {
  [[ ${#_DEPS_CHANGED[@]} -eq 0 ]] && return 0
  local hooks_file="$HOME/.config/dot/dep-hooks.sh"
  # shellcheck source=dep-hooks.sh
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
  _run_post_hooks

  _install_cron || true
}
