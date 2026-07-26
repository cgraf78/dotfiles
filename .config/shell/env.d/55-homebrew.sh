# shellcheck shell=bash
# Homebrew environment. Final PATH priority is normalized by 90-path.sh.

if [[ "$_UNAME" == "Darwin" ]]; then
  test -x /opt/homebrew/bin/brew && eval "$(/opt/homebrew/bin/brew shellenv)"
fi
