# Interactive tool integrations: shell extensions, completions, functions.

# ── History (before tools — atuin reads HISTFILE at init) ─────────────────

HISTSIZE=130000
SAVEHIST=130000
HISTFILE=~/.zsh_history
setopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS
setopt AUTO_CD

# ── Platform ──────────────────────────────────────────────────────────────

if [[ "$_UNAME" == "Darwin" ]]; then
  if [[ -z "${NVIM:-}" ]]; then
    test -e "${HOME}/.iterm2_shell_integration.zsh" && . "${HOME}/.iterm2_shell_integration.zsh"
    # Guard: wezterm.sh has no re-source protection for zsh — it appends
    # duplicate hooks to precmd/preexec_functions on every source, causing
    # gradual prompt slowdown in long-lived shells.
    if [[ -z "${__wezterm_sourced:-}" ]]; then
      test -e "/Applications/WezTerm.app/Contents/Resources/wezterm.sh" && . "/Applications/WezTerm.app/Contents/Resources/wezterm.sh"
      __wezterm_sourced=1
    fi
  fi
fi

# ── Tool integrations (after history, before plugins) ─────────────────────

# Extra completion definitions (must precede compinit).
[[ -d "$HOME/.local/share/zsh-completions/src" ]] &&
  fpath=("$HOME/.local/share/zsh-completions/src" $fpath)
[[ -d "$HOME/.local/share/zsh/site-functions" ]] &&
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)

# Zsh completion: rebuild dump daily, use cache otherwise.
autoload -Uz compinit
if [[ -n ~/.zcompdump(#qN-.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# Completion: navigable menu, case-insensitive matching
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

command -v fzf &>/dev/null && eval "$(fzf --zsh 2>/dev/null)"
command -v ds &>/dev/null && eval "$(ds init zsh)"
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v atuin &>/dev/null && eval "$(atuin init zsh --disable-up-arrow)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# ── Plugins (after tools — ordering within section matters) ───────────────
# autosuggestions → syntax-highlighting (wraps ZLE widgets) →
# history-substring-search (needs syntax-highlighting for colored matches)

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

# ── Keybindings (after plugins — avoid clobbering widget bindings) ────────

bindkey '\e[1;5D' backward-word
bindkey '\e[1;5C' forward-word
bindkey -M vicmd '\e[1;5D' backward-word
bindkey -M vicmd '\e[1;5C' forward-word
