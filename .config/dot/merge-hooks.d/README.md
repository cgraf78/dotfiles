# Base Merge-Hook Inputs

This directory contains declarative input for the merge hooks owned by the
always-active `dotfiles` repository. Executable hooks live under
`~/.local/lib/dotfiles/merge-hooks.d/`.

Base owns agent-rule aggregation, cron, global ignore policy, SSH, tmux,
WezTerm, iTerm2, and Karabiner integration. Some instance directories here
(`ssh/`, `tmux/`, `wezterm/`) hold only a README. Two base hooks have no
directory in this tree at all: `sshd.sh` installs Termnav's system sshd
`AcceptEnv` fragment when `dot update` runs as root, and `grok-rc.sh` strips
the block Grok's installer appends to the tracked `~/.zshrc` and `~/.bashrc`.
Editor and development applications contribute their own same-named input
directories from `dotfiles-nvim` and `dotfiles-dev`; their documentation lives
in those repositories.

Ordered source families use direct files and `<name>.replace/` groups. Direct
files aggregate in lexical order. A replace group contributes only its last
lexical file, and that winner is sorted back into the family by relative path.
Numeric prefixes belong inside a family, not on the top-level hook name.

The standalone Dot runtime discovers executable hooks in lexical order and
runs independent hooks in isolated workers. `cron.sh` replaces the user
crontab as one unit, but no other hook touches it, so it runs in the parallel
batch. Failed hooks do
not suppress later hooks, but they make the aggregate update fail.

Keep reusable mechanics in Dot's public hook API and target-specific policy in
the owning overlay. Base inputs and hook instances currently cover:

- agent-rule manifests through `agent-rules-sync`;
- filtered cron entries and their PATH;
- global ignore patterns;
- terminal and keyboard application policy;
- SSH fragments, including selected-overlay transport fragments prepared by
  the pre-sync hook;
- the tmux reload and the WSL-only copy of the WezTerm config into the
  Windows home, declared by README-only instance directories.

Use native source formats where practical. Never place credentials, private
hostnames, or machine-local selectors in this public tree.
