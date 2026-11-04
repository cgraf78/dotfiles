# Cron Merge Hook

This directory declares the `cron` merge-hook instance. Its declarative sources
are:

- `cron.d/`: ordered cron entry fragments
- `path.d/`: ordered PATH allowlist fragments, preferably named `*.txt`
- `../cron.local`: optional untracked machine-local cron entries

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/cron.sh`.

The managed block is placed at the top of the account crontab. Its `SHELL`,
`BASH_ENV`, `PATH`, and any other variable assignments apply to all later jobs,
including unmanaged jobs. A later unmanaged assignment overrides that value
for jobs below it. Other accounts, system crontabs, and `/etc/cron.d` files
have independent environments.

On the first update from the earlier layout, an unchanged block at the bottom
is moved to the top. An unmanaged assignment that previously preceded the
managed block (for example `MAILTO` or `CRON_TZ`) no longer applies to managed
jobs; it still applies to subsequent unmanaged jobs. Put a value intended for
managed jobs in a managed fragment. Ambiguous, duplicate or incomplete managed
markers cause the update to leave the crontab untouched for manual repair.
Before replacing a crontab the hook re-reads it and stops on a concurrent
change; crontab does not provide an atomic compare-and-swap, so a writer can
still race after that check.
