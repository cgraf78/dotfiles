# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Base dotfiles are managed as a bare git repository with `$HOME` as the working
tree, plus optional Git or filesystem overlays for work, machine-specific, or
project-specific files.

- `~/.dotfiles` is the base bare repo.
- `~/.dotfiles-<name>` repos are Git overlays discovered from
  `~/.config/dot/overlays.d/*.conf`; `sync=none` descriptors can point at
  sources managed outside dot.
- Overlay files live under each overlay's `home/` directory and are symlinked
  into `$HOME` by `dot update`.

macOS requires Bash 4+ (`brew install bash`). The system Bash 3.2 is too old.

## Quick Start

Personal machine:

```bash
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Machine with a private overlay using normal GitHub SSH access:

```bash
# Bootstrap the base repo and any matching overlays that your SSH key can read.
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Machine with a private overlay that uses a dedicated deploy key:

```bash
# Copy the overlay deploy key from a machine that already has it.
scp <source>:~/.ssh/<deploy-key> ~/.ssh/
chmod 600 ~/.ssh/<deploy-key>

curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

`dotbootstrap` clones the base repo and matching Git overlays, validates and
applies matching filesystem overlays whose descriptors and sources are already
present, skips optional Git overlays that are not accessible on the current
machine, backs up conflicting files under `~/.dotfiles-backup/`, and installs
the auto-update cron.

## Usage

```bash
dot update                  # sync repos, apply overlays, merge configs, update deps
dot update -v               # verbose update
dot update --force          # bypass TTL caches and force reinstalls
dot update --cron           # quiet update, skipped when any repo is dirty
dot pull                    # alias for update
dot fetch                   # fetch base + Git overlays
dot push                    # push base + Git overlays
dot status                  # status for base + Git overlays
dot diff                    # diff for base + Git overlays
dot cron                    # show installed cron entries
dot doctor                  # run installation health checks
```

`update`, `pull`, `cron`, and `doctor` work before the bare repo exists.
`fetch`, `push`, `status`, and `diff` require it.

Use plain `git` for raw Git operations on the base repo. The tracked
`~/.local/bin/git` launcher routes `$HOME` and non-repo descendants to the bare
dotfiles repo, while normal Git and Sapling checkouts still use real Git:

```bash
git add <file>
git commit
dot push
```

Git overlay repos are regular checkouts and are managed with
`git -C ~/.dotfiles-<name>`.

## Dependency Docs

This file is the high-level map. Detailed behavior lives beside the files that
own it:

| Area | README |
| --- | --- |
| Dot config directories | [`.config/dot/README.md`](../../../../.config/dot/README.md) |
| Agent rule merge inputs | [`.config/dot/merge-hooks.d/agent-rules/README.md`](../../../../.config/dot/merge-hooks.d/agent-rules/README.md) |
| ds sessions | [`.config/ds/README.md`](../../../../.config/ds/README.md) |
| Overlay repos | [`.config/dot/overlays.d/README.md`](../../../../.config/dot/overlays.d/README.md) |
| Config merge hooks and cron | [`.config/dot/merge-hooks.d/README.md`](../../../../.config/dot/merge-hooks.d/README.md) |
| Git config | [`.config/git/README.md`](../../../../.config/git/README.md) |
| Git hooks | [`.local/share/git-hooks/README.md`](../../../../.local/share/git-hooks/README.md) |
| Sapling hooks | [`.local/share/sl-hooks/README.md`](../../../../.local/share/sl-hooks/README.md) |
| Hive Memory config | [`.config/hive-memory/README.md`](../../../../.config/hive-memory/README.md) |
| Hive Memory launcher | [`.local/lib/dot/hive-memory/README.md`](../../../../.local/lib/dot/hive-memory/README.md) |
| Shell loading | [`.config/shell/README.md`](../../../../.config/shell/README.md) |
| Dependency installs | [`.config/shdeps/README.md`](../../../../.config/shdeps/README.md) |
| Pinned tool versions | [`.config/mise/README.md`](../../../../.config/mise/README.md) |
| Ripgrep integration | [`.config/ripgrep/README.md`](../../../../.config/ripgrep/README.md) |
| Lazygit integration | [`.config/lazygit/README.md`](../../../../.config/lazygit/README.md) |
| Neovim config | [`.config/nvim/README.md`](../../../../.config/nvim/README.md) |
| tmux config | [`.config/tmux/README.md`](../../../../.config/tmux/README.md) |
| WezTerm integration | [`.config/wezterm/README.md`](../../../../.config/wezterm/README.md) |
| Checkrun policy | [`.config/checkrun/README.md`](../../../../.config/checkrun/README.md) |
| Sley verification policy | [`.config/sley/verify.d/README.md`](../../../../.config/sley/verify.d/README.md) |
| Command entry points | [`.local/bin/README.md`](../../../../.local/bin/README.md) |
| Runtime library layout | [`.local/lib/dot/README.md`](../../../../.local/lib/dot/README.md) |
| `dot` core runtime | [`.local/lib/dot/core/README.md`](../../../../.local/lib/dot/core/README.md) |
| Dot Lua helpers | [`.local/lib/dot/lua/README.md`](../../../../.local/lib/dot/lua/README.md) |
| Dot documentation index | [`.local/share/doc/dot/README.md`](README.md) |
| Schema payloads | [`.local/share/checkrun/schemas/README.md`](../../../../.local/share/checkrun/schemas/README.md) |
| Test suites | [`.local/lib/dot/tests/README.md`](../../../../.local/lib/dot/tests/README.md) |
| Core test modules | [`.local/lib/dot/tests/core/README.md`](../../../../.local/lib/dot/tests/core/README.md) |

## Operating Model

`dot update` is the normal convergence command. It pulls the base repo and all
active overlays, links overlay files, installs dependencies through shdeps,
runs config merge hooks, and refreshes generated state. Installing tools before
hooks lets an overlay add policy and the compatible tool release in one update.

`DOT_UPDATE_JOBS` controls top-level update concurrency for work that can run in
parallel. It defaults to the host CPU count. `DOT_MERGE_JOBS` and
`SHDEPS_JOBS` are narrower overrides; when unset, dot gives both the resolved
`DOT_UPDATE_JOBS` value.

The base dotfiles repo still syncs first. After that, pull-eligible overlay
repos sync in parallel up to `DOT_UPDATE_JOBS`; overlay linking stays ordered
because overlay order controls which file wins when overlays overlap.

shdeps owns its own self-update policy; dot only ensures shdeps is available and
then invokes the configured dependency update pass.

Dependency warnings remain non-fatal, but `dot update` shows their count and
the affected dependency details. For example, a user-owned local checkout that
cannot fast-forward stays untouched and usable while the update reports that it
may be serving stale code.

Required-stage failures are different: repository sync, overlay linking,
dependency installation, and config merge hook failures make `dot update`
return nonzero. The command remains best effort and runs every later safe stage
before returning, so one failed dependency does not prevent config convergence
or cleanup. An initial shdeps bootstrap failure stops before overlay discovery
because platform and host filters are not available safely.

Advisory dependency warnings, optional overlay skips, cron's dirty-worktree
skip, cron lock contention, and best-effort worktree normalization retain a
zero exit status.

If a pull updates dot infrastructure such as `.local/lib/dot/` or
`.local/bin/dot`, the command re-execs itself so the remainder of the update
uses the new code.

Base files use `[ -f ]` guards and ordered config directories so overlays can
contribute extra files without patching base files. Every machine is a peer:
there is no branch sync protocol and no generated ownership marker system.

## Common Workflows

Add a base dotfile:

```bash
git add <file>
git commit
dot push
```

Add an overlay dotfile:

```bash
git -C ~/.dotfiles-<name> add home/<path>
git -C ~/.dotfiles-<name> commit
git -C ~/.dotfiles-<name> push
dot update
```

Check readiness before pushing:

```bash
dot status
sley ready
dot-test
dot push
```

## Testing

Run all local tests with:

```bash
dot-test
```

The suite auto-discovers `*-test` scripts under `~/.local/lib/dot/tests/` and
runs them in parallel by default. See the
[`tests` README](../../../../.local/lib/dot/tests/README.md) for suite names,
options, and CI coverage.
