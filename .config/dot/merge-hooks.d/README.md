# Base Merge-Hook Inputs

This directory contains declarative input for the merge hooks owned by the
always-active `dotfiles` repository. Executable hooks live under
`~/.local/lib/dotfiles/merge-hooks.d/`.

Base owns agent-rule aggregation, cron, global ignore policy, SSH, tmux,
WezTerm, iTerm2, and Karabiner integration. Editor and development applications
contribute their own same-named input directories from `dotfiles-nvim` and
`dotfiles-dev`; their documentation lives in those repositories.

Ordered source families use direct files and `<name>.replace/` groups. Direct
files aggregate in lexical order. A replace group contributes only its last
lexical file, and that winner is sorted back into the family by relative path.
Numeric prefixes belong inside a family, not on the top-level hook name.

The standalone Dot runtime discovers executable hooks in lexical order and
runs independent hooks in isolated workers. `cron.serial.sh` is deliberately
serialized because it replaces the user crontab as one unit. Failed hooks do
not suppress later hooks, but they make the aggregate update fail.

Keep reusable mechanics in Dot's public hook API and target-specific policy in
the owning overlay. Base inputs currently publish:

- agent-rule manifests through `agent-rules-sync`;
- filtered cron entries and their PATH;
- global ignore patterns;
- terminal and keyboard application policy;
- SSH fragments, including selected-overlay transport fragments prepared by
  the pre-sync hook;
- tmux and WezTerm refresh behavior.

Use native source formats where practical. Never place credentials, private
hostnames, or machine-local selectors in this public tree.
