# Platform-specific non-interactive setup.

if [[ "$_UNAME" == "Darwin" ]]; then
    test -x /opt/homebrew/bin/brew && eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [[ "$_UNAME" == "Linux" || "$_UNAME" == MINGW* || "$_UNAME" == MSYS* ]]; then
    stty -ixon 2>/dev/null
fi
