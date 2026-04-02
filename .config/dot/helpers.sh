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
# Dependency checks
# ---------------------------------------------------------------------------

_install_hint() {
  local pkg="$1"
  if command -v brew &>/dev/null; then
    _log "  brew install $pkg"
  elif command -v apt-get &>/dev/null; then
    _log "  sudo apt-get update && sudo apt-get install -y $pkg"
  elif command -v dnf &>/dev/null; then
    _log "  sudo dnf install -y $pkg"
  elif command -v pacman &>/dev/null; then
    _log "  sudo pacman -S --needed $pkg"
  else
    _log "  (install '$pkg' with your system package manager)"
  fi
}

_check_dep() {
  # $1=command $2=pkg-name
  local cmd="$1" pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    if [[ "${_dep_header_shown:-0}" -eq 0 ]]; then _log "==> Missing dependencies..."; _dep_header_shown=1; fi
    _log "  warning: $cmd not found"
    _install_hint "$pkg"
    return 1
  fi
  return 0
}

_check_dep_any() {
  # $1=pkg-name $2...=commands
  local pkg="$1"
  shift
  local cmd
  for cmd in "$@"; do
    if command -v "$cmd" &>/dev/null; then
      return 0
    fi
  done
  if [[ "${_dep_header_shown:-0}" -eq 0 ]]; then _log "==> Missing dependencies..."; _dep_header_shown=1; fi
  _log "  warning: $pkg not found"
  _install_hint "$pkg"
  return 1
}

# Check all expected system dependencies. Best-effort — warns but doesn't abort.
_check_deps() {
  _dep_header_shown=0
  _check_dep git git || true
  _check_dep jq jq || true
  _check_dep tmux tmux || true
  _check_dep fzf fzf || true
  _check_dep atuin atuin || true
  _check_dep zoxide zoxide || true
  _check_dep_any bat bat batcat || true
  _check_dep_any fd fd fdfind || true
  _check_dep eza eza || true
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
# Usage: _install_tool <name> <repo-url> <install-dir>
# Priority: ~/git/<name> (symlink) > existing git clone (pull) > release tarball > fresh clone.
# If <install-dir>/bin/<name> exists after install, it is symlinked into PATH.
_install_tool() {
  local name="$1" repo="$2" install_dir="$3"
  local tarball_url tmp_dir
  local local_clone="$HOME/git/$name"

  # Prefer local clone — symlink for live development
  if [[ -d "$local_clone" ]]; then
    rm -rf "$install_dir"
    mkdir -p "$(dirname "$install_dir")"
    ln -sfn "$local_clone" "$install_dir"
    _link_bin "$name" "$install_dir"
    local ver; ver=$(_get_version "$local_clone")
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

# Install or upgrade all managed dependencies.
_update_deps() {
  _check_deps

  local ds_repo="${DOTBOOTSTRAP_DS_REPO:-https://github.com/cgraf78/ds.git}"
  local vimrc_repo="${DOTBOOTSTRAP_VIMRC_REPO:-https://github.com/cgraf78/vimrc.git}"
  local gstack_repo="${DOTBOOTSTRAP_GSTACK_REPO:-https://github.com/garrytan/gstack.git}"
  local bash_preexec_repo="${DOTBOOTSTRAP_BASH_PREEXEC_REPO:-https://github.com/rcaloras/bash-preexec.git}"

  _log "==> Installing/upgrading ds..."
  _install_tool ds "$ds_repo" "$HOME/.local/share/ds" || true

  _log "==> Installing/upgrading vimrc..."
  local is_fresh_vimrc=0
  if [[ ! -d "$HOME/.vim_runtime" ]]; then is_fresh_vimrc=1; fi
  _install_tool vimrc "$vimrc_repo" "$HOME/.vim_runtime" || true
  if [[ $is_fresh_vimrc -eq 1 && -f "$HOME/.vim_runtime/install_awesome_vimrc.sh" ]]; then
    sh "$HOME/.vim_runtime/install_awesome_vimrc.sh" 2>/dev/null || \
      _warn "  warning: vimrc install script failed"
  fi

  _log "==> Installing/upgrading gstack..."
  _install_tool gstack "$gstack_repo" "$HOME/.gstack" || true
  if [[ -d "$HOME/.gstack" ]]; then
    mkdir -p "$HOME/.claude/skills"
    ln -sfn "$HOME/.gstack" "$HOME/.claude/skills/gstack"
    local _d
    for _d in "$HOME/.gstack"/*/; do
      if [[ -f "$_d/SKILL.md" && "$(basename "$_d")" != "node_modules" ]]; then
        ln -sfn "gstack/$(basename "$_d")" "$HOME/.claude/skills/$(basename "$_d")"
      fi
    done
  fi

  _log "==> Installing/upgrading bash-preexec..."
  _install_tool bash-preexec "$bash_preexec_repo" "$HOME/.local/share/bash-preexec" || true
  if [[ -f "$HOME/.local/share/bash-preexec/bash-preexec.sh" ]]; then
    ln -sfn "$HOME/.local/share/bash-preexec/bash-preexec.sh" "$HOME/.bash-preexec.sh"
  fi

  _log "==> Installing cron..."
  _install_cron || true
}
