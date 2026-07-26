# shellcheck shell=bash
# Repo-set iteration and Git invocation helpers.
#
# The base dotfiles repo is bare with $HOME as its work tree, while overlays
# are normal Git repos. Keep that command-shape difference centralized so
# higher-level operations can work with repo records instead of reimplementing
# bare-vs-normal Git dispatch.

# Run a callback for every repo that already exists locally: the base dotfiles
# repo first, followed by cloned overlays in discovery order. Missing overlays
# are deliberately skipped here; cloning is pull/update behavior, while simple
# commands like status, diff, fetch, and push should only operate on installed
# repos.
_repo_each_existing() {
  local callback="$1"
  shift

  if [[ -d "$DOTFILES" ]]; then
    "$callback" base dotfiles "$HOME" "" "$@" || return $?
  fi

  local entry name path url
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    IFS='|' read -r name path url _ <<<"$entry"
    [[ -d "$path/.git" ]] || continue
    "$callback" overlay "$name" "$path" "$url" "$@" || return $?
  done
}

# Execute git for a repo record emitted by _repo_each_existing. Keeping this as
# a helper avoids scattering the base repo's bare-repo command shape beside
# normal `git -C` overlay commands.
_repo_git() {
  local kind="$1" path="$2"
  shift 2

  case "$kind" in
    base)
      # shellcheck disable=SC2086  # $GIT is intentionally word-split.
      $GIT "$@"
      ;;
    overlay)
      git -C "$path" "$@"
      ;;
    *)
      return 2
      ;;
  esac
}
