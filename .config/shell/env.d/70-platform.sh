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
