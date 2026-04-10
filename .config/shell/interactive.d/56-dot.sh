# Shared interactive helpers for dotfiles management.

dotu() {
    dot update "$@" || return

    if [[ -n "${ZSH_VERSION:-}" ]]; then
        source "$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        source "$HOME/.bashrc"
    fi
}
