# shellcheck shell=bash
# Interactive tool integrations: shell extensions, completions, functions.

# ── History & shell options (before tools — atuin reads HISTFILE at init) ─

HISTSIZE=130000
HISTFILESIZE=-1
HISTTIMEFORMAT="%d/%m/%y %T "
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# ── Platform ──────────────────────────────────────────────────────────────
# unalias before the if-block: bash expands aliases at parse time,
# so an alias inside a false branch still triggers a syntax error.

unalias sc 2>/dev/null || true
if [[ "$_UNAME" == "Darwin" ]]; then
  if [[ -z "${NVIM:-}" ]]; then
    # shellcheck disable=SC1091  # optional local integration script
    test -e "${HOME}/.iterm2_shell_integration.bash" && . "${HOME}/.iterm2_shell_integration.bash"
    # shellcheck disable=SC1091  # optional local app integration script
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

# ── Functions ─────────────────────────────────────────────────────────────

# OpenClaw TUI — launch a conversation with the main agent.
# Usage: argus [session-name]   (default: tui)
# unalias first: bash expands aliases before parsing function definitions,
# so if argus was previously an alias, "argus() {" becomes a syntax error.
unalias argus 2>/dev/null || true
argus() {
  local sess="${1:-tui}"
  openclaw tui --session "agent:main:${sess}"
}

# ── Tool integrations (after history) ─────────────────────────────────────
# On some Linux hosts, `fzf --bash` emits malformed `complete` commands when it
# tries to wrap distro-provided bash-completion specs. Keep the key bindings,
# but skip the completion section to avoid login-time warnings.

if command -v fzf &>/dev/null; then
  eval "$(
    fzf --bash 2>/dev/null | sed '/^### completion\.bash ###$/,$d'
  )"
fi
if command -v ds &>/dev/null; then
  eval "$(ds init bash)"
fi
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi
if [[ -f ~/.bash-preexec.sh ]]; then
  if [[ "$_UNAME" != "Linux" || -n "$TMUX" ]]; then
    # shellcheck disable=SC1090  # symlinked/generated local file path
    source ~/.bash-preexec.sh
  fi
fi
if command -v atuin &>/dev/null; then
  eval "$(atuin init bash --disable-up-arrow)"
fi
if command -v direnv &>/dev/null; then
  eval "$(direnv hook bash)"
fi
