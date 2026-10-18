# shellcheck shell=bash
# Optional local GitHub authentication for every profile. Preserve caller
# overrides in every mode and keep credential-store access out of startup.

if [ -f "$HOME/.config/gh/github-pat" ]; then
  # Keep a hand-written token owner-only, but repair the mode only in
  # interactive shells. env.d also loads in every non-interactive bash
  # (BASH_ENV) and zsh (~/.zshenv), where chmod would fork on each agent tool
  # call and script, and recurse without end under a test that shadows chmod
  # with a bash script; bash has no builtin to check the mode first. The
  # gh-token merge hook also repairs it on `dot update`.
  case $- in
    *i*) chmod 600 "$HOME/.config/gh/github-pat" 2>/dev/null || true ;;
  esac
  read -r _DOT_GITHUB_PAT <"$HOME/.config/gh/github-pat" || true
  if [ -n "${_DOT_GITHUB_PAT:-}" ]; then
    _shell_env_set GH_TOKEN "${GH_TOKEN:-$_DOT_GITHUB_PAT}"
  fi
  unset _DOT_GITHUB_PAT
fi
