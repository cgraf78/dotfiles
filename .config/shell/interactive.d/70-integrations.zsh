# Interactive tool integrations: shell extensions, completions, functions.

# macOS integrations
if [[ "$_UNAME" == "Darwin" ]]; then
  if [[ -z "${NVIM:-}" ]]; then
    test -e "${HOME}/.iterm2_shell_integration.zsh" && . "${HOME}/.iterm2_shell_integration.zsh"
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

# History
HISTSIZE=130000
SAVEHIST=130000
HISTFILE=~/.zsh_history
setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE

# OpenClaw TUI — launch a conversation with the main agent.
# Usage: argus [session-name]   (default: tui)
# Enforces agent:main:<session-name> session key structure.
unalias argus 2>/dev/null
argus() {
  local sess="${1:-tui}"
  openclaw tui --session "agent:main:${sess}"
}

# Ctrl-Left/Right: word movement (matches bash behavior in vi mode)
bindkey '\e[1;5D' backward-word
bindkey '\e[1;5C' forward-word
bindkey -M vicmd '\e[1;5D' backward-word
bindkey -M vicmd '\e[1;5C' forward-word

# Tool shell integrations (completions, key bindings, auto-attach)
# Zsh has native preexec/precmd hooks. Initialize the helper autoload so
# hook-based tooling can register without a bash-preexec-style shim.
autoload -Uz add-zsh-hook

# Extra completion definitions (must precede compinit).
[[ -d "$HOME/.local/share/zsh-completions/src" ]] &&
  fpath=("$HOME/.local/share/zsh-completions/src" $fpath)

# Zsh completion must be initialized before tools register `compdef` hooks.
autoload -Uz compinit
compinit

command -v fzf &>/dev/null && eval "$(fzf --zsh 2>/dev/null)"
command -v ds &>/dev/null && eval "$(ds init zsh)" || true
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v atuin &>/dev/null && eval "$(atuin init zsh --disable-up-arrow)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)" || true

# Zsh plugins (managed by shdeps/dotbootstrap).
# Order matters: autosuggestions first, syntax-highlighting late (wraps ZLE
# widgets), history-substring-search last (needs syntax-highlighting for
# colored matches).
_zsh_plugin_dir="$HOME/.local/share"

[[ -f "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"

[[ -f "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

if [[ -f "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh"
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey -M vicmd 'k' history-substring-search-up
  bindkey -M vicmd 'j' history-substring-search-down
fi

unset _zsh_plugin_dir
