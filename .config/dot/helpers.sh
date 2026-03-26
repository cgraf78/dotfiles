#!/bin/bash
# Shared helpers for dot and dotbootstrap.

DOTFILES="$HOME/.dotfiles"
# shellcheck disable=SC2034  # used by scripts that source this file
GIT="git --git-dir=$DOTFILES --work-tree=$HOME"
WORK_DIR="$HOME/.dotfiles-work"

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
    echo "==> Pulling work dotfiles..."
    git -C "$WORK_DIR" pull --quiet "$@" || echo "  warning: work dotfiles pull failed" >&2
  fi
  # shellcheck disable=SC2015  # || true is a fallback, not an else branch
  [[ -x "$WORK_DIR/bootstrap" ]] && "$WORK_DIR/bootstrap" || true
}

# Push work repo.
_push_work_repo() {
  [[ -d "$WORK_DIR/.git" ]] || return 0
  echo "==> Pushing work dotfiles..."
  git -C "$WORK_DIR" push "$@" || echo "  warning: work dotfiles push failed" >&2
}

# Run all app config merge scripts (iTerm2, Karabiner, VS Code, etc.).
_run_merges() {
  for _script in "$HOME/.config/dot"/merge-*.sh; do
    [[ -f "$_script" ]] || continue
    # shellcheck source=/dev/null
    . "$_script"
    _fn="merge_${_script##*merge-}"; _fn="${_fn%.sh}"
    "$_fn" || true
  done
}

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------

_install_hint() {
  local pkg="$1"
  if command -v brew &>/dev/null; then
    echo "  brew install $pkg"
  elif command -v apt-get &>/dev/null; then
    echo "  sudo apt-get update && sudo apt-get install -y $pkg"
  elif command -v dnf &>/dev/null; then
    echo "  sudo dnf install -y $pkg"
  elif command -v pacman &>/dev/null; then
    echo "  sudo pacman -S --needed $pkg"
  else
    echo "  (install '$pkg' with your system package manager)"
  fi
}

_check_dep() {
  # $1=command $2=pkg-name
  local cmd="$1" pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    if [[ "${_dep_header_shown:-0}" -eq 0 ]]; then echo "==> Missing dependencies..."; _dep_header_shown=1; fi
    echo "  warning: $cmd not found"
    _install_hint "$pkg"
    return 1
  fi
  return 0
}

# Check all expected system dependencies. Best-effort — warns but doesn't abort.
_check_deps() {
  _dep_header_shown=0
  _check_dep git git || true
  _check_dep jq jq || true
  _check_dep tmux tmux || true
  _check_dep fzf fzf || true
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
    echo "  $name -> $local_clone (local clone)${ver:+ -- $ver}"
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
        echo "  $name updated${ver:+ -- $ver}"
      else
        echo "  $name up to date${ver:+ -- $ver}"
      fi
    else
      echo "  warning: $name update failed" >&2
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
      echo "  warning: failed to download $name release (trying git clone)" >&2
      tarball_url=""
    fi
  fi

  # Fallback: git clone to a temp dir first so we don't destroy an existing
  # install on failure (e.g. network unreachable).
  if [[ -z "${tarball_url:-}" ]]; then
    if ! command -v git &>/dev/null; then
      echo "  warning: no curl release and no git — cannot install $name" >&2
      return 1
    fi
    local clone_tmp="${install_dir}.tmp.$$"
    rm -rf "$clone_tmp"
    if ! git clone --depth 1 "$repo" "$clone_tmp" 2>/dev/null; then
      rm -rf "$clone_tmp"
      echo "  warning: failed to clone $name (network unreachable?)" >&2
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
    echo "  $name up to date ($method)${ver:+ -- $ver}"
  else
    echo "  $name installed ($method)${ver:+ -- $ver}"
  fi
}

# Install or upgrade all managed dependencies.
_update_deps() {
  _check_deps

  local ds_repo="${DOTBOOTSTRAP_DS_REPO:-https://github.com/cgraf78/ds.git}"
  local dotsync_repo="${DOTBOOTSTRAP_DOTSYNC_REPO:-https://github.com/cgraf78/dotsync.git}"
  local vimrc_repo="${DOTBOOTSTRAP_VIMRC_REPO:-https://github.com/cgraf78/vimrc.git}"
  local gstack_repo="${DOTBOOTSTRAP_GSTACK_REPO:-https://github.com/garrytan/gstack.git}"

  echo "==> Installing/upgrading ds..."
  _install_tool ds "$ds_repo" "$HOME/.local/share/ds" || true

  echo "==> Installing/upgrading dotsync..."
  _install_tool dotsync "$dotsync_repo" "$HOME/.local/share/dotsync" || true

  echo "==> Installing/upgrading vimrc..."
  local is_fresh_vimrc=0
  if [[ ! -d "$HOME/.vim_runtime" ]]; then is_fresh_vimrc=1; fi
  _install_tool vimrc "$vimrc_repo" "$HOME/.vim_runtime" || true
  if [[ $is_fresh_vimrc -eq 1 && -f "$HOME/.vim_runtime/install_awesome_vimrc.sh" ]]; then
    sh "$HOME/.vim_runtime/install_awesome_vimrc.sh" 2>/dev/null || \
      echo "  warning: vimrc install script failed" >&2
  fi

  echo "==> Installing/upgrading gstack..."
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
}
