# Dotfiles Merge Hooks

These are the application-specific hooks discovered by standalone `dot` from
the configured extension root. Declarative inputs remain under
`~/.config/dot/merge-hooks.d/<identity>/`; executable policy and private helper
code live here.

Each readable top-level `*.sh` file defines `merge()` with no arguments. The
filename supplies the public identity. A `*.serial.sh` suffix creates a barrier
for hooks that mutate singleton external state; current examples are the
crontab writer and the system SSH policy installer. `.serial` is stripped from
the hook identity and sort key.

Hooks run in fresh Bash workers with private temporary storage. They use the
documented hook API and load client support through `dot_hook_source`. A hook
should return quietly when its application or configuration is absent. Any
nonzero hook status is recorded as a configuration failure, later hooks still
run, and the aggregate `dot update` status is exactly 1.

The paired config tree contains user-editable source fragments. Do not move
executable helpers back under `.config/dot`: configuration is organized by the
program consuming it, while code is organized by the repository implementing
it.
