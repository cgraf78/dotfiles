# shellcheck shell=bash
# Keep registration coupled to the upstream checkout lifecycle. The provider
# owns every agent-specific transform and cleanup rule; this hook owns only the
# decision to reconcile immediately after shdeps changes gstack.

post() {
  gstack-register sync
}

uninstall() {
  # The provider can identify its outputs after the checkout is gone, so this
  # remains safe regardless of whether shdeps calls cleanup before or after
  # removing the upstream source directory.
  gstack-register uninstall
}
