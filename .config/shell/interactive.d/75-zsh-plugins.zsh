# Zsh plugins (managed by shdeps/dotbootstrap).

_zsh_plugin_dir="$HOME/.local/share"

# Fish-style history suggestions as you type.
[[ -f "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Syntax highlighting — must be sourced late (wraps ZLE widgets).
[[ -f "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

# History substring search — source after syntax-highlighting for colored matches.
# Up/Down arrows search history filtered by the current line content.
if [[ -f "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "$_zsh_plugin_dir/zsh-history-substring-search/zsh-history-substring-search.zsh"
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey -M vicmd 'k' history-substring-search-up
  bindkey -M vicmd 'j' history-substring-search-down
fi

unset _zsh_plugin_dir
