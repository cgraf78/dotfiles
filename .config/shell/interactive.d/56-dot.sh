# Shared interactive helpers for dotfiles management.

dotu() {
    dot update "$@" || return

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
}

reloadsh() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
}

shellinfo() {
    printf 'shell=%s\n' "${SHELL:-}"
    printf 'bash=%s\n' "${BASH_VERSION:-no}"
    printf 'zsh=%s\n' "${ZSH_VERSION:-no}"
    printf 'tmux=%s\n' "${TMUX:+yes}${TMUX:-no}"
    printf 'ssh=%s\n' "${SSH_CONNECTION:+yes}${SSH_CONNECTION:-no}"
    printf 'term=%s\n' "${TERM:-}"
    printf 'pwd=%s\n' "${PWD:-}"
}

cgr() {
    local root="${1:-$HOME/git}"
    local dir=""

    if [[ ! -d "$root" ]]; then
        echo "error: repo root not found: $root" >&2
        return 1
    fi

    if command -v fd >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
        dir="$(
            fd --base-directory "$root" --max-depth 1 --type d . \
                | fzf --height 40% --reverse --prompt="repo> "
        )" || return
        [[ -n "$dir" ]] || return
        cd "$root/$dir" || return
        return
    fi

    echo "error: cgr requires both fd and fzf" >&2
    return 1
}

cdf() {
    local root="${1:-.}"
    local dir=""

    if [[ ! -d "$root" ]]; then
        echo "error: directory not found: $root" >&2
        return 1
    fi

    if command -v fd >/dev/null 2>&1 && command -v fzf >/dev/null 2>&1; then
        dir="$(
            fd --base-directory "$root" --type d . \
                | fzf --height 40% --reverse --prompt="dir> "
        )" || return
        [[ -n "$dir" ]] || return
        cd "$root/$dir" || return
        return
    fi

    echo "error: cdf requires both fd and fzf" >&2
    return 1
}

rgv() {
    local hit file line

    if ! command -v rg >/dev/null 2>&1 || ! command -v fzf >/dev/null 2>&1; then
        echo "error: rgv requires both ripgrep and fzf" >&2
        return 1
    fi

    if ! command -v nvim >/dev/null 2>&1; then
        echo "error: rgv requires nvim" >&2
        return 1
    fi

    hit="$(
        rg --line-number --no-heading --color=never "$@" \
            | fzf --height 60% --reverse --prompt="rg> "
    )" || return
    [[ -n "$hit" ]] || return

    file="${hit%%:*}"
    line="${hit#*:}"
    line="${line%%:*}"
    nvim "+${line}" "$file"
}

fv() {
    local root="${1:-.}"
    local file=""

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

    if command -v fd >/dev/null 2>&1; then
        file="$(
            fd --base-directory "$root" --type f . \
                | fzf --height 60% --reverse --prompt="file> "
        )" || return
        [[ -n "$file" ]] || return
        nvim "$root/$file"
        return
    fi

    file="$(
        find "$root" -type f 2>/dev/null \
            | fzf --height 60% --reverse --prompt="file> "
    )" || return
    [[ -n "$file" ]] || return
    nvim "$file"
}
