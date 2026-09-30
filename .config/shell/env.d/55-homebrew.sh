# shellcheck shell=bash
# Homebrew environment. Final PATH priority is normalized by 90-path.sh.

if [[ "$_UNAME" == "Darwin" ]] && test -x /opt/homebrew/bin/brew; then
  if command -v _shell_env_inherited >/dev/null 2>&1 &&
    _shell_env_inherited HOMEBREW_PREFIX; then
    # Fill-only child of a shell that already ran `brew shellenv`: its exports
    # and PATH are inherited, and re-running it would fork brew, overwrite
    # caller values, and prepend another INFOPATH copy per nesting level.
    # Only zsh's fpath is shell-local, so restore brew's completion dir.
    if [ -n "${ZSH_VERSION:-}" ] &&
      [ -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]; then
      eval '(( ${fpath[(Ie)$HOMEBREW_PREFIX/share/zsh/site-functions]} )) ||
        fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)'
    fi
  else
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
