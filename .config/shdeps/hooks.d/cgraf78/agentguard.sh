# shellcheck shell=bash
# CI-only bridge for the unmerged AgentGuard integration provider.
#
# Dotfiles PR checks bootstrap dependencies before they run repository tests.
# During a cross-repository change, that bootstrap can only clone AgentGuard's
# default branch; GitHub does not make another repository's unmerged PR visible
# through a normal clone. Failing closed is the correct production behavior,
# but it would prevent this consumer PR from ever validating the exact provider
# commit it depends on.
#
# Keep the exception here, at the Shdeps dependency boundary, instead of adding
# fallback bytes or branch knowledge to any per-agent merge hook. The bridge is
# deliberately limited to pull-request jobs in the public dotfiles repository,
# stages an immutable reviewed commit, and refuses to touch a developer clone.
# Once AgentGuard PR #75 is on main, remove this hook; normal fleet updates must
# continue to consume AgentGuard's default branch without a permanent pin.

_dot_agentguard_ci_provider_commit=c56f747c8400616708c9ec9f4a9099c8613ff06b

_dot_agentguard_has_native_integrations() {
  local root="$1" asset
  for asset in \
    share/agentguard/integrations/_shared/reconcile-hooks.jq \
    share/agentguard/integrations/claude/hooks.json \
    share/agentguard/integrations/codex/hooks.toml \
    share/agentguard/integrations/gemini/hooks.json \
    share/agentguard/integrations/muse/hooks.json \
    share/agentguard/integrations/opencode/agentguard.js; do
    [[ -r "$root/$asset" ]] || return 1
  done
}

_dot_agentguard_ci_bridge_enabled() {
  [[ "${GITHUB_ACTIONS:-}" == "true" &&
    "${GITHUB_EVENT_NAME:-}" == "pull_request" &&
    "${GITHUB_REPOSITORY:-}" == "cgraf78/dotfiles" ]]
}

post() {
  local dependency="${1:-cgraf78/agentguard}" root managed_path managed_root
  root=$(shdeps_dep_root "$dependency") || root=""

  # Main already has the provider generation after PR #75 lands. Returning
  # before the CI predicate makes this hook a no-op as soon as that happens.
  if [[ -n "$root" ]] && _dot_agentguard_has_native_integrations "$root"; then
    return 0
  fi
  _dot_agentguard_ci_bridge_enabled || return 0

  managed_path="$(shdeps_install_dir)/cgraf78/agentguard"
  # Shdeps may resolve a live checkout under ~/git for development. Never
  # detach or otherwise rewrite that user-owned clone just to satisfy CI. Test
  # the unresolved install path before canonicalizing it because Shdeps uses a
  # symlink there when a developer clone owns the dependency.
  if [[ -L "$managed_path" || ! -d "$managed_path" ]]; then
    shdeps_warn "  warning: refusing to stage AgentGuard PR provider in an unmanaged checkout"
    return 1
  fi

  # Compare physical paths on both sides. In particular, macOS presents its
  # temporary directory through /var even though that path resolves beneath
  # /private/var. Canonicalizing only the managed install path would therefore
  # make the very same checkout look unrelated and reject a safe CI update.
  # This happens after the unresolved-path symlink check above so a Shdeps link
  # to a developer-owned clone can never be normalized into an allowed path.
  if [[ -z "$root" || ! -d "$root" ]]; then
    shdeps_warn "  warning: refusing to stage AgentGuard PR provider in an unmanaged checkout"
    return 1
  fi
  root=$(cd "$root" && pwd -P) || return 1
  managed_root=$(cd "$managed_path" && pwd -P) || return 1
  if [[ "$root" != "$managed_root" || ! -d "$root/.git" ]]; then
    shdeps_warn "  warning: refusing to stage AgentGuard PR provider in an unmanaged checkout"
    return 1
  fi

  command git -C "$root" fetch \
    --no-tags --depth=1 origin "$_dot_agentguard_ci_provider_commit" || return 1
  command git -C "$root" checkout \
    --detach "$_dot_agentguard_ci_provider_commit" || return 1

  if ! _dot_agentguard_has_native_integrations "$root"; then
    shdeps_warn "  warning: staged AgentGuard PR provider is incomplete"
    return 1
  fi
}
