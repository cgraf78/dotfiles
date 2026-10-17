# shellcheck shell=bash
# Platform-specific non-interactive setup.

if [[ "$_UNAME" == "Linux" || "$_UNAME" == MINGW* || "$_UNAME" == MSYS* ]]; then
  case $- in
    *i*)
      # BASH_ENV and ~/.zshenv also source env.d for non-interactive helpers.
      # Touching tty state from an async prompt/background job can be stopped
      # by job control before the helper reaches its own script body.
      if [ -t 0 ]; then
        stty -ixon 2>/dev/null
      fi
      ;;
  esac
fi

# Programs that open links themselves (Claude Code's Ctrl-click, `gh --web`,
# Python's webbrowser) run $BROWSER where they run. On a Linux host without a
# display, such as a remote build host reached over SSH or ET, that is not
# where the user sits, so browser-open forwards the URL to the desktop's
# terminal. macOS, WSL, Termux, and Linux desktops keep their own openers. A VS Code integrated
# terminal keeps VS Code's BROWSER, which opens in that VS Code window; inside
# tmux, TERM_PROGRAM is always tmux, so tmux panes never match this exception.
if [ "$_UNAME" = Linux ] && [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] &&
  [ -z "${WSL_DISTRO_NAME:-}${TERMUX_VERSION:-}" ] &&
  [ "${TERM_PROGRAM:-}" != vscode ] && [ -x "$HOME/.local/bin/browser-open" ]; then
  _shell_env_set BROWSER "$HOME/.local/bin/browser-open"
fi
