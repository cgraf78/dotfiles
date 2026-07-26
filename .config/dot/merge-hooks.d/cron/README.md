# Cron Merge Hook

This directory declares the `cron` merge-hook instance. Its declarative sources
are:

- `cron.d/`: ordered cron entry fragments
- `path.d/`: ordered PATH allowlist fragments, preferably named `*.txt`
- `../cron.local`: optional untracked machine-local cron entries

The executable hook implementation lives at
`~/.local/lib/dot/core/merge-hooks/cron.sh`.
