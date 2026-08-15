# Muse Merge Hook

This directory declares the `muse` merge-hook instance. The executable hook at
`~/.local/lib/dotfiles/merge-hooks.d/muse.sh` prepends AgentGuard's native
`muse/hooks.json` generation plus AgentGuard's shared reconciler, resolved
through shdeps, before local `settings.d/` layers.

AgentGuard owns Muse's supported event set, matchers, commands, identity
environment, and timeouts. Keeping that knowledge under
`share/agentguard/integrations/muse/` makes the integration reusable and keeps
dotfiles from becoming a second compatibility implementation.

This directory retains only local permission policy in
`settings.d/20-permissions.json`. The provider layer comes first so overlays can
still extend normal Muse settings. AgentGuard's filter removes historical
unsupported events and replaces changed commands without a Muse deletion list
here. If either asset is temporarily unavailable, the hook reports a failed
refresh and leaves the complete live target—including a legacy symlink—intact.
