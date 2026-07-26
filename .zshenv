# ~/.zshenv: runs for every zsh invocation (login, interactive, scripts).
# Login zsh loads env.d through ~/.zprofile, and interactive non-login zsh
# loads it through ~/.zshrc. Non-login non-interactive zsh has no later startup
# hook, so delegate to the same lightweight loader that bash gets through
# BASH_ENV.
if [[ ! -o interactive && ! -o login ]] &&
  [[ -f "$HOME/.config/shell/env-noninteractive.sh" ]]; then
  . "$HOME/.config/shell/env-noninteractive.sh"
fi
