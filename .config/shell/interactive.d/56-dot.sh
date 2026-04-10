# Shared interactive helpers for dotfiles management.

# Resolve platform-specific binary names once.
_fd_cmd=""
if command -v fd >/dev/null 2>&1; then _fd_cmd="fd"
elif command -v fdfind >/dev/null 2>&1; then _fd_cmd="fdfind"
fi

# Render a file preview with `bat`/`batcat` when available.
# Args: <file> [highlight-line]
_preview_file() {
    local file="$1"
    local line="${2:-}"
    local start=1
    local end=200
    local bat_cmd=""

    if [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi

    if command -v bat >/dev/null 2>&1; then
        bat_cmd="bat"
    elif command -v batcat >/dev/null 2>&1; then
        bat_cmd="batcat"
    fi

    if [[ -n "$line" ]]; then
        start=$(( line > 20 ? line - 20 : 1 ))
        end=$(( line + 20 ))
    fi

    if [[ -n "$bat_cmd" ]]; then
        if [[ -n "$line" ]]; then
            "$bat_cmd" --style=plain --color=always --highlight-line "$line" --line-range "$start:$end" "$file"
        else
            "$bat_cmd" --style=plain --color=always --line-range "$start:$end" "$file"
        fi
        return
    fi

    sed -n "${start},${end}p" "$file"
}

# Open a file at an optional line using `$EDITOR`.
# Args: <file> [line]
_edit_file() {
    local file="$1"
    local line="${2:-}"
    local editor="${EDITOR:-vi}"
    local cmd=""

    if [[ -z "$file" ]]; then
        echo "error: missing file path" >&2
        return 1
    fi

    if [[ -n "$line" ]]; then
        printf -v cmd '%s +%q %q' "$editor" "$line" "$file"
    else
        printf -v cmd '%s %q' "$editor" "$file"
    fi

    eval "$cmd"
}

# Run `dot update` and reload the current shell config on success.
# Args: [dot update args...]
#   dotu --force
dotu() {
    dot update "$@" || return

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
}

# Reload the current shell config without updating dotfiles.
reloadsh() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
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

# Fuzzy-jump to a repo under ~/git, with optional root and initial query.
# Args: [query] or [root] [query]
# Examples:
#   cgr ds
#   cgr ~/git dot
cgr() {
    local root="$HOME/git"
    local query=""
    local dir=""

    case $# in
        0) ;;
        1)
            if [[ -d "$1" ]]; then
                root="$1"
            else
                query="$1"
            fi
            ;;
        *)
            root="$1"
            query="$2"
            ;;
    esac

    if [[ ! -d "$root" ]]; then
        echo "error: repo root not found: $root" >&2
        return 1
    fi

    if [[ -n "$_fd_cmd" ]] && command -v fzf >/dev/null 2>&1; then
        dir="$(
            "$_fd_cmd" --base-directory "$root" --max-depth 1 --type d . \
                | fzf --height 40% --reverse --prompt="repo> " --query="$query"
        )" || return
        [[ -n "$dir" ]] || return
        cd "$root/$dir" || return
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
    local root="."
    local query=""
    local dir=""

    case $# in
        0) ;;
        1)
            if [[ -d "$1" ]]; then
                root="$1"
            else
                query="$1"
            fi
            ;;
        *)
            root="$1"
            query="$2"
            ;;
    esac

    if [[ ! -d "$root" ]]; then
        echo "error: directory not found: $root" >&2
        return 1
    fi

    if [[ -n "$_fd_cmd" ]] && command -v fzf >/dev/null 2>&1; then
        dir="$(
            "$_fd_cmd" --base-directory "$root" --hidden --exclude .git --type d . \
                | fzf --height 40% --reverse --prompt="dir> " --query="$query"
        )" || return
        [[ -n "$dir" ]] || return
        cd "$root/$dir" || return
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
            | fzf --height 70% --reverse --prompt="rg> " --preview="$preview" --preview-window="bottom,60%,border-top"
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
    local root="."
    local query=""
    local file=""
    local preview=""
    local root_q=""

    case $# in
        0) ;;
        1)
            if [[ -d "$1" ]]; then
                root="$1"
            else
                query="$1"
            fi
            ;;
        *)
            root="$1"
            query="$2"
            ;;
    esac

    if [[ ! -d "$root" ]]; then
        echo "error: directory not found: $root" >&2
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

    preview="bash -lc 'file=\$1; source ~/.config/shell/interactive.d/56-dot.sh; _preview_file \"\$file\"' _ {}"
    if [[ -n "$_fd_cmd" ]]; then
        printf -v root_q '%q' "$root"
        file="$(
            "$_fd_cmd" --base-directory "$root" --hidden --exclude .git --type f . \
                | fzf --height 70% --reverse --prompt="file> " --scheme=path --query="$query" --preview="bash -lc 'root=\$1; file=\$2; source ~/.config/shell/interactive.d/56-dot.sh; _preview_file \"\$root/\$file\"' _ $root_q {}" --preview-window="bottom,60%,border-top"
        )" || return
        [[ -n "$file" ]] || return
        _edit_file "$root/$file"
        return
    fi

    file="$(
        find "$root" -name .git -prune -o -type f -print 2>/dev/null \
            | fzf --height 70% --reverse --prompt="file> " --scheme=path --query="$query" --preview="$preview" --preview-window="bottom,60%,border-top"
    )" || return
    [[ -n "$file" ]] || return
    _edit_file "$file"
}
