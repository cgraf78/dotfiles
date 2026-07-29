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
[[ -d "$HOME/.local/share/zsh-users/zsh-completions/src" ]] &&
  fpath=("$HOME/.local/share/zsh-users/zsh-completions/src" $fpath)
[[ -d "$HOME/.local/share/zsh/site-functions" ]] &&
  fpath=("$HOME/.local/share/zsh/site-functions" $fpath)

# Zsh completion: rebuild dump daily, use cache otherwise. Once compinit has
# populated `_comps`, re-sourcing this file should not rescan completions; newly
# installed completion files need a fresh shell or a manual compinit.
if ((!${+_comps})); then
  autoload -Uz compinit
  local _zcd=(~/.zcompdump(N.mh+24))
  if ((${#_zcd})); then
    compinit
  else
    compinit -C
  fi
fi

# Completion: navigable menu, case-insensitive matching
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

_tool_init sley _tool_shdeps_source_emit cgraf78/sley share/sley/shell.sh

_tool_init fzf fzf --zsh
_tool_init ds ds init zsh
_tool_init zoxide zoxide init zsh
_tool_init atuin atuin init zsh --disable-up-arrow
_tool_init direnv direnv hook zsh

# ── Plugins (after tools — ordering within section matters) ───────────────
# autosuggestions → fast-syntax-highlighting (wraps ZLE widgets) →
# history-substring-search (needs syntax-highlighting for colored matches)

_zsh_plugin_dir="$HOME/.local/share/zsh-users"
_fzf_tab_plugin_dir="$HOME/.local/share/Aloxaf/fzf-tab"
_fsh_plugin_dir="$HOME/.local/share/zdharma-continuum/fast-syntax-highlighting"

zstyle ':fzf-tab:complete:*' fzf-flags --height=45% --reverse
zstyle ':fzf-tab:*' switch-group '<' '>'

# All widget-wrapping plugins below load before the first prompt. Bind
# autosuggestions once after that final ordering instead of rescanning and
# rebinding every ZLE widget on every subsequent prompt.
typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1

[[ -f "$_fzf_tab_plugin_dir/fzf-tab.plugin.zsh" ]] &&
  source "$_fzf_tab_plugin_dir/fzf-tab.plugin.zsh"

[[ -f "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"

[[ -f "$_fsh_plugin_dir/fast-syntax-highlighting.plugin.zsh" ]] &&
  source "$_fsh_plugin_dir/fast-syntax-highlighting.plugin.zsh"

if [[ -f "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh"
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey -M vicmd 'k' history-substring-search-up
  bindkey -M vicmd 'j' history-substring-search-down
fi

unset _zsh_plugin_dir
unset _fzf_tab_plugin_dir
unset _fsh_plugin_dir

# ── Keybindings (after plugins — avoid clobbering widget bindings) ────────

# Home/End variants emitted by macOS terminals directly, through SSH, and
# through tmux.
for _key in '\e[H' '\eOH' '\e[1~' '\e[7~'; do
  bindkey "$_key" beginning-of-line
  bindkey -M vicmd "$_key" beginning-of-line
done
for _key in '\e[F' '\eOF' '\e[4~' '\e[8~'; do
  bindkey "$_key" end-of-line
  bindkey -M vicmd "$_key" end-of-line
done
unset _key

bindkey '\e[1;5D' backward-word
bindkey '\e[1;5C' forward-word
bindkey -M vicmd '\e[1;5D' backward-word
bindkey -M vicmd '\e[1;5C' forward-word
