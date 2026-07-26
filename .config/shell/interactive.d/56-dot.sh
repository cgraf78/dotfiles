# shellcheck shell=bash
# Shared interactive helpers for dotfiles management.
# _fd_cmd and _bat_cmd are normally set by 50-aliases.sh. When this file
# is sourced standalone (e.g., fzf preview subprocesses), detect them here.
if [[ -z "${_bat_cmd:-}" ]]; then
  if command -v bat >/dev/null 2>&1; then
    _bat_cmd="bat"
  elif command -v batcat >/dev/null 2>&1; then
    _bat_cmd="batcat"
  fi
fi

# Shared fzf layout options.
_fzf_pick=(--height 40% --reverse)
_fzf_preview=(--height 70% --reverse --preview-window="bottom,60%,border-top")

# Render a file preview with `bat`/`batcat` when available.
# Args: <file> [highlight-line]
_preview_file() {
  local file="$1"
  local line="${2:-}"
  local start=1
  local end=200

  if [[ -z "$file" || ! -f "$file" ]]; then
    return 1
  fi

  if [[ -n "$line" ]]; then
    start=$((line > 20 ? line - 20 : 1))
    end=$((line + 20))
  fi

  if [[ -n "$_bat_cmd" ]]; then
    local -a bat_args=(--style=plain --color=always --line-range "$start:$end")
    [[ -n "$line" ]] && bat_args+=(--highlight-line "$line")
    "$_bat_cmd" "${bat_args[@]}" "$file"
    return
  fi

  sed -n "${start},${end}p" "$file"
}

# Open a file at an optional line using `$EDITOR`.
# Args: <file> [line]
_edit_file() {
  local file="$1"
  local line="${2:-}"

  if [[ -z "$file" ]]; then
    echo "error: missing file path" >&2
    return 1
  fi

  if [[ -n "$line" ]]; then
    "${EDITOR:-vi}" "+$line" "$file"
  else
    "${EDITOR:-vi}" "$file"
  fi
}

# Guard for git helpers: fail with a consistent message unless run inside a
# git work tree. Callers use: _require_git_repo || return
_require_git_repo() {
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "error: not in a git repo" >&2
    return 1
  fi
}

# Require external commands, reporting any missing ones. The caller name is
# passed explicitly because these helpers are sourced in zsh too, where bash's
# $FUNCNAME is unavailable. Callers use: _need_cmds <name> <cmd>... || return
_need_cmds() {
  local caller="$1" missing=() cmd
  shift
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]})); then
    echo "error: $caller requires ${missing[*]}" >&2
    return 1
  fi
}

# Require $EDITOR for helpers that open files. Callers use:
# _need_editor <name> || return
_need_editor() {
  if [[ -z "${EDITOR:-}" ]]; then
    echo "error: $1 requires \$EDITOR to be set" >&2
    return 1
  fi
}

# Reload the current shell config.
_reload_shell() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    # ZLE-wrapping plugins are not reliably idempotent in a live zsh session.
    exec zsh
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    source "$HOME/.bashrc"
  fi
}

# Run `dot update` and reload the current shell config on success.
# Args: [dot update args...]
#   dotu --force
dotu() {
  DOT_UPDATE_RELOADS_SHELL=1 dot update "$@" || return
  _clear_tool_cache
  _reload_shell
}

# Shortcut for 'dot status'
dots() {
  dot status "$@" || return
}

# Reload the current shell config without updating dotfiles.
# Clears the tool-init cache and re-source guards so integrations reinitialize.
reloadsh() {
  _clear_tool_cache
  _reload_shell
}

# Print shell/session context for quick environment debugging.
shinfo() {
  printf 'shell=%s\n' "${SHELL:-}"
  printf 'bash=%s\n' "${BASH_VERSION:-no}"
  printf 'zsh=%s\n' "${ZSH_VERSION:-no}"
  printf 'tmux=%s\n' "${TMUX:+yes}${TMUX:-no}"
  printf 'ssh=%s\n' "${SSH_CONNECTION:+yes}${SSH_CONNECTION:-no}"
  printf 'term=%s\n' "${TERM:-}"
  printf 'pwd=%s\n' "${PWD:-}"
}

# Parse [query] or [root] [query] args into _root and _query.
# Args: <default-root> [caller args...]
_parse_root_query() {
  _root="$1"
  shift
  _query=""

  case $# in
    0) ;;
    1)
      if [[ -d "$1" ]]; then
        _root="$1"
      else
        _query="$1"
      fi
      ;;
    *)
      _root="$1"
      _query="$2"
      ;;
  esac
}

# Fuzzy-jump to a repo under ~/git, with optional root and initial query.
# Args: [query] or [root] [query]
# Examples:
#   cgr ds
#   cgr ~/git dot
cgr() {
  local _root _query dir
  _parse_root_query "$HOME/git" "$@"

  if [[ ! -d "$_root" ]]; then
    echo "error: repo root not found: $_root" >&2
    return 1
  fi

  if [[ -n "$_fd_cmd" ]] && command -v fzf >/dev/null 2>&1; then
    dir="$(
      "$_fd_cmd" --base-directory "$_root" --max-depth 1 --type d . |
        fzf "${_fzf_pick[@]}" --prompt="repo> " --query="$_query"
    )" || return
    [[ -n "$dir" ]] || return
    cd "$_root/$dir" || return
    return
  fi

  echo "error: cgr requires both fd and fzf" >&2
  return 1
}

# Fuzzy-jump to a directory, with optional search root and initial query.
# Args: [query] or [root] [query]
# Examples:
#   cdf shell
#   cdf ~/.config nvim
cdf() {
  local _root _query dir
  _parse_root_query "." "$@"

  if [[ ! -d "$_root" ]]; then
    echo "error: directory not found: $_root" >&2
    return 1
  fi

  if [[ -n "$_fd_cmd" ]] && command -v fzf >/dev/null 2>&1; then
    dir="$(
      "$_fd_cmd" --base-directory "$_root" --hidden --exclude .git --type d . |
        fzf "${_fzf_pick[@]}" --prompt="dir> " --query="$_query"
    )" || return
    [[ -n "$dir" ]] || return
    cd "$_root/$dir" || return
    return
  fi

  echo "error: cdf requires both fd and fzf" >&2
  return 1
}

# Ripgrep for content, preview matches, and open the selected hit in `$EDITOR`.
# Args: <rg pattern> [rg args...]
# Examples:
#   rgv shellcheck
#   rgv "dot update"
#   rgv --glob '*.sh' direnv
rgv() {
  local hit file line preview

  _need_cmds rgv rg fzf || return
  _need_editor rgv || return

  preview="bash -c 'source ~/.config/shell/interactive.d/56-dot.sh; hit=\$1; file=\${hit%%:*}; rest=\${hit#*:}; line=\${rest%%:*}; _preview_file \"\$file\" \"\$line\"' _ {}"
  hit="$(
    rg --hidden --glob '!.git' --line-number --no-heading --color=never "$@" |
      fzf "${_fzf_preview[@]}" --prompt="rg> " --preview="$preview"
  )" || return
  [[ -n "$hit" ]] || return

  file="${hit%%:*}"
  line="${hit#*:}"
  line="${line%%:*}"
  _edit_file "$file" "$line"
}

# Fuzzy-pick a file, preview it, and open it in `$EDITOR`.
# Args: [query] or [root] [query]
# Examples:
#   fv dot.sh
#   fv ~/.config dot.sh
fv() {
  local _root _query file root_q preview
  _parse_root_query "." "$@"

  if [[ ! -d "$_root" ]]; then
    echo "error: directory not found: $_root" >&2
    return 1
  fi

  _need_cmds fv fzf || return
  _need_editor fv || return

  printf -v root_q '%q' "$_root"
  preview="bash -c 'source ~/.config/shell/interactive.d/56-dot.sh; _preview_file \"\$1\"' _ $root_q/{}"

  if [[ -n "$_fd_cmd" ]]; then
    listing() { "$_fd_cmd" --base-directory "$_root" --hidden --exclude .git --type f .; }
  else
    listing() { (cd "$_root" && find . -name .git -prune -o \( -type f -o -type l \) -print 2>/dev/null) | sed 's|^\./||'; }
  fi

  file="$(
    listing |
      fzf "${_fzf_preview[@]}" --prompt="file> " --scheme=path --query="$_query" --preview="$preview"
  )"
  local fzf_rc=$?
  unset -f listing
  [[ $fzf_rc -ne 0 ]] && return $fzf_rc

  [[ -n "$file" ]] || return
  _edit_file "$_root/$file"
}
