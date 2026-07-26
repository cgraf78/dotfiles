# Agent Rule Merge Inputs

The `agent-rules` merge hook renders generated global agent rule files from two
family-aggregator inputs. Its executable implementation lives at
`~/.local/lib/dot/core/merge-hooks/agent-rules.sh`.

- `rules.d/` contains concise, always-loaded Markdown source fragments.
- `targets.d/` contains declarative target profiles.

Task-specific guidance lives in `~/.config/dot/agent-playbooks.d/` and is
referenced by the generated on-demand playbook index in `rules.d/`. Each
playbook's opening metadata block must contain exactly one non-empty
`<!-- agent-rule-trigger: ... -->` line beside its `agent-rule-id`. Keep the
`<!-- dot-playbook-index -->` marker in the on-demand core fragment; `dot
update` replaces it with the human-readable trigger list. Playbook bodies are
not merged into runtime targets.

Generated runtime rule files are outputs, not source. Edit these family inputs,
then run `dot update` and the relevant dotfiles tests.

## Rule Sources

`rules.d/` contains the source fragments for generated global agent rule files.
`dot update` concatenates the active Markdown fragments in family order and
writes the result into the configured runtime target files.

Use three-digit numeric prefixes to make ordering explicit. Keep the aggregate
small: language, tool, troubleshooting, and detailed workflow guidance belongs
in an on-demand playbook. Overlay repositories can add concise routing or core
fragments directly or use `.replace` groups when a rule family must be mutually
exclusive.

Do not edit generated runtime files directly. Edit these source fragments, then
run `dot update` and the relevant dotfiles tests.

## Rule Targets

`targets.d/` selects where the generated agent rule aggregate is written. Each
active `*.txt` file is a newline-delimited list of target files. Supported path
forms are absolute paths, `$HOME/...`, and `~/...`. The hook still accepts the
legacy `*.conf` suffix for older overlays.

Use a `.replace` group when environments are mutually exclusive. For example, a
personal machine can select native agent global files, while an overlay on
another machine can replace that profile with a different single loader target.

Targets receive a dot-managed block. Unmanaged text outside that block is
preserved, and stale managed blocks are pruned when the active profile changes.
