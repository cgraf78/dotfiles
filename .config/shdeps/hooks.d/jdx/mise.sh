# shellcheck shell=bash
# Post-install hook for mise — syncs the tools declared in the
# tracked config at `~/.config/mise/config.toml` whenever mise
# itself is installed or updated.
#
# Trust the config first: mise silently refuses to parse untrusted
# files (including our XDG config on a fresh host), and `mise
# install` no-ops without any error. Trusting is idempotent.
#
# Some Linux hosts hit GitHub API rate limits during aqua artifact
# attestation verification unless `MISE_GITHUB_TOKEN` is set
# explicitly, even when mise can read the token from `gh`'s
# `hosts.yml`. Seed the env var from `gh auth token` only for this
# hook so normal shell startup stays cheap.
#
# `mise install` is run from `$HOME` so mise picks up the XDG
# config regardless of the caller's cwd.

post() {
  command -v mise &>/dev/null || return 0
  mise trust "$HOME/.config/mise/config.toml" &>/dev/null || true

  local github_token
  github_token="${MISE_GITHUB_TOKEN:-}"
  if [[ -z "$github_token" ]] && command -v gh &>/dev/null; then
    github_token="$(gh auth token 2>/dev/null || true)"
  fi

  if [[ -n "$github_token" ]]; then
    (cd "$HOME" && MISE_GITHUB_TOKEN="$github_token" mise install) || true
  else
    (cd "$HOME" && mise install) || true
  fi
}
