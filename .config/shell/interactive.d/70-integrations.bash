# Interactive tool integrations: shell extensions, completions, functions.

# macOS integrations
if [[ "$_UNAME" == "Darwin" ]]; then
    if [[ -z "${NVIM:-}" ]]; then
        test -e "${HOME}/.iterm2_shell_integration.bash" && . "${HOME}/.iterm2_shell_integration.bash"
        test -e "/Applications/WezTerm.app/Contents/Resources/wezterm.sh" && . "/Applications/WezTerm.app/Contents/Resources/wezterm.sh"
    fi

    # Screenshot capture to Google Drive
    sc() {
        if [[ ! -d ~/gdrive/img ]]; then
            echo "error: ~/gdrive/img does not exist" >&2
            return 1
        fi
        screencapture -i ~/gdrive/img/"screen_$(date +%Y%m%d_%H%M%S).png"
    }
fi

# Shell options
HISTSIZE=130000
HISTFILESIZE=-1
HISTTIMEFORMAT="%d/%m/%y %T "
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# OpenClaw TUI — launch a conversation with the main agent.
# Usage: argus [session-name]   (default: tui)
# Enforces agent:main:<session-name> session key structure.
# unalias first: bash expands aliases before parsing function definitions,
# so if argus was previously an alias, "argus() {" becomes a syntax error.
unalias argus 2>/dev/null || true
argus() {
    local sess="${1:-tui}"
    openclaw tui --session "agent:main:${sess}"
}

# Tool shell integrations (completions, key bindings, auto-attach)
#
# On some Linux hosts, `fzf --bash` emits malformed `complete` commands when it
# tries to wrap distro-provided bash-completion specs. Keep the key bindings,
# but skip the completion section to avoid login-time warnings.
if command -v fzf &>/dev/null; then
    eval "$(
        fzf --bash 2>/dev/null | sed '/^### completion\.bash ###$/,$d'
    )" || true
fi
command -v ds &>/dev/null && eval "$(ds init bash)" || true
command -v zoxide &>/dev/null && eval "$(zoxide init bash)" || true
if [[ -f ~/.bash-preexec.sh ]]; then
    if [[ "$_UNAME" != "Linux" || -n "$TMUX" ]]; then
        source ~/.bash-preexec.sh
    fi
fi
command -v atuin &>/dev/null && eval "$(atuin init bash --disable-up-arrow)" || true
command -v direnv &>/dev/null && eval "$(direnv hook bash)" || true
