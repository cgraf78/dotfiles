# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Reconcile gstack's agent registrations on every dot update.
#
# The shdeps hook covers checkout changes; this second activation point covers
# policy edits and agents installed after the last gstack update. All reusable
# behavior belongs to the provider, leaving this consumer intentionally thin.

merge() {
  _dot_tool_present gstack || return 0
  local provider
  provider=$(command -v gstack-register) || return 0

  "$provider" sync
}
