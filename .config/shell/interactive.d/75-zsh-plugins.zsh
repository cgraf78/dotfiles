# Zsh plugins (managed by shdeps/dotbootstrap).

_zsh_plugin_dir="$HOME/.local/share"

# Fish-style history suggestions as you type.
[[ -f "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-autosuggestions/zsh-autosuggestions.zsh"

# Syntax highlighting — must be sourced last (wraps ZLE widgets).
[[ -f "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] &&
  source "$_zsh_plugin_dir/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

unset _zsh_plugin_dir
