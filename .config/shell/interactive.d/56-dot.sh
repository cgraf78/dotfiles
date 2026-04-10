# Shared interactive helpers for dotfiles management.

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

    if command -v fd >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
        dir="$(
            fd --base-directory "$root" --max-depth 1 --type d . \
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

    if command -v fd >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
        dir="$(
            fd --base-directory "$root" --hidden --exclude .git --type d . \
                | fzf --height 40% --reverse --prompt="dir> " --query="$query"
        )" || return
        [[ -n "$dir" ]] || return
        cd "$root/$dir" || return
        return
    fi

    echo "error: cdf requires both fd and fzf" >&2
    return 1
}

# Ripgrep for content, preview matches, and open the selected hit in nvim.
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

    if ! command -v nvim >/dev/null 2>&1; then
        echo "error: rgv requires nvim" >&2
        return 1
    fi

    preview="bash -c 'hit=\$1; file=\${hit%%:*}; rest=\${hit#*:}; line=\${rest%%:*}; if command -v bat >/dev/null 2>&1; then start=\$(( line > 20 ? line - 20 : 1 )); end=\$(( line + 20 )); bat --style=plain --color=always --highlight-line \"\$line\" --line-range \"\$start:\$end\" \"\$file\"; else start=\$(( line > 20 ? line - 20 : 1 )); end=\$(( line + 20 )); sed -n \"\${start},\${end}p\" \"\$file\"; fi' _ {}"
    hit="$(
        rg --hidden --glob '!.git' --line-number --no-heading --color=never "$@" \
            | fzf --height 70% --reverse --prompt="rg> " --preview="$preview" --preview-window="right,60%,border-left"
    )" || return
    [[ -n "$hit" ]] || return

    file="${hit%%:*}"
    line="${hit#*:}"
    line="${line%%:*}"
    nvim "+${line}" "$file"
}

# Fuzzy-pick a file, preview it, and open it in nvim.
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

    if ! command -v nvim >/dev/null 2>&1; then
        echo "error: fv requires nvim" >&2
        return 1
    fi

    preview="bash -c 'file=\$1; if command -v bat >/dev/null 2>&1; then bat --style=plain --color=always --line-range :200 \"\$file\"; else sed -n \"1,200p\" \"\$file\"; fi' _ {}"
    if command -v fd >/dev/null 2>&1; then
        printf -v root_q '%q' "$root"
        file="$(
            fd --base-directory "$root" --hidden --exclude .git --type f . \
                | fzf --height 70% --reverse --prompt="file> " --scheme=path --query="$query" --preview="bash -c 'root=\$1; file=\$2; if command -v bat >/dev/null 2>&1; then bat --style=plain --color=always --line-range :200 \"\$root/\$file\"; else sed -n \"1,200p\" \"\$root/\$file\"; fi' _ $root_q {}" --preview-window="right,60%,border-left"
        )" || return
        [[ -n "$file" ]] || return
        nvim "$root/$file"
        return
    fi

    file="$(
        find "$root" -name .git -prune -o -type f -print 2>/dev/null \
            | fzf --height 70% --reverse --prompt="file> " --scheme=path --query="$query" --preview="$preview" --preview-window="right,60%,border-left"
    )" || return
    [[ -n "$file" ]] || return
    nvim "$file"
}
