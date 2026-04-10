# Shared interactive helpers for dotfiles management.

# Resolve platform-specific binary names once.
_fd_cmd=""
if command -v fd >/dev/null 2>&1; then _fd_cmd="fd"
elif command -v fdfind >/dev/null 2>&1; then _fd_cmd="fdfind"
fi

_bat_cmd=""
if command -v bat >/dev/null 2>&1; then _bat_cmd="bat"
elif command -v batcat >/dev/null 2>&1; then _bat_cmd="batcat"
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
        start=$(( line > 20 ? line - 20 : 1 ))
        end=$(( line + 20 ))
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

# Re-source the current shell's rc file.
_reload_shell() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
}

# Run `dot update` and reload the current shell config on success.
# Args: [dot update args...]
#   dotu --force
dotu() {
    dot update "$@" || return
    _reload_shell
}

# Reload the current shell config without updating dotfiles.
reloadsh() {
    _reload_shell
}

# Print shell/session context for quick environment debugging.
shellinfo() {
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
    _root="$1"; shift
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
            "$_fd_cmd" --base-directory "$_root" --max-depth 1 --type d . \
                | fzf "${_fzf_pick[@]}" --prompt="repo> " --query="$_query"
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
            "$_fd_cmd" --base-directory "$_root" --hidden --exclude .git --type d . \
                | fzf "${_fzf_pick[@]}" --prompt="dir> " --query="$_query"
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

    if ! command -v rg >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
        echo "error: rgv requires both ripgrep and fzf" >&2
        return 1
    fi

    if [[ -z "${EDITOR:-}" ]]; then
        echo "error: rgv requires \$EDITOR to be set" >&2
        return 1
    fi

    preview="bash -lc 'hit=\$1; file=\${hit%%:*}; rest=\${hit#*:}; line=\${rest%%:*}; source ~/.config/shell/interactive.d/56-dot.sh; _preview_file \"\$file\" \"\$line\"' _ {}"
    hit="$(
        rg --hidden --glob '!.git' --line-number --no-heading --color=never "$@" \
            | fzf "${_fzf_preview[@]}" --prompt="rg> " --preview="$preview"
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

    if ! command -v fzf >/dev/null 2>&1; then
        echo "error: fv requires fzf" >&2
        return 1
    fi

    if [[ -z "${EDITOR:-}" ]]; then
        echo "error: fv requires \$EDITOR to be set" >&2
        return 1
    fi

    printf -v root_q '%q' "$_root"
    preview="bash -lc 'source ~/.config/shell/interactive.d/56-dot.sh; _preview_file \"\$1\"' _ $root_q/{}"

    local listing
    if [[ -n "$_fd_cmd" ]]; then
        listing() { "$_fd_cmd" --base-directory "$_root" --hidden --exclude .git --type f .; }
    else
        listing() { (cd "$_root" && find . -name .git -prune -o -type f -print 2>/dev/null) | sed 's|^\./||'; }
    fi

    file="$(
        listing \
            | fzf "${_fzf_preview[@]}" --prompt="file> " --scheme=path --query="$_query" --preview="$preview"
    )" || return
    unset -f listing

    [[ -n "$file" ]] || return
    _edit_file "$_root/$file"
}
