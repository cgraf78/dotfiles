# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Base dotfiles use `~/.dotfiles` as a separate Git directory with `$HOME` as the
worktree, plus optional Git or filesystem overlays for environment-specific
files.

- Fresh `dot init` clients set `core.bare=false` and an explicit absolute
  `core.worktree=$HOME` in `~/.dotfiles`. Existing legacy bare clients remain
  supported.
- `~/.dotfiles-<name>` repos are Git overlays discovered from
  `~/.config/dot/overlays.d/*.conf`; `sync=none` descriptors can point at
  sources managed outside dot.
- Overlay files live under each overlay's `home/` directory and are symlinked
  into `$HOME` by `dot update`.
- `~/.local/lib/dotfiles` is the dotfiles client's executable policy runtime.
  The standalone Dot checkout and its public API remain separate.

macOS requires Bash 4+ (`brew install bash`). The system Bash 3.2 is too old.

## Quick Start

Personal machine:

```bash
curl -fsSL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Machine with a private overlay using normal GitHub SSH access:

```bash
# Bootstrap the base repo and any matching overlays that your SSH key can read.
curl -fsSL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Machine with a private overlay that uses a dedicated deploy key:

```bash
# Copy the overlay deploy key from a machine that already has it.
scp <source>:~/.ssh/<deploy-key> ~/.ssh/
chmod 600 ~/.ssh/<deploy-key>

curl -fsSL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

The public shortcut delegates to standalone Dot and selects this client
repository. `dot init` owns repository initialization, conflict backup, overlay
convergence, and extension execution. It backs up conflicting files under
`~/.dot-backup/` and installs the auto-update cron.

## Recovery

When the base client Git directory can be discarded, recovery stays a clean
reinitialization rather than a compatibility migration:

```bash
rm -rf ~/.dotfiles
curl -fsSL cgraf78.github.io/d | bash
```

Dot recreates the canonical separate Git directory and preserves conflicting
worktree files through its normal initialization backup.

## Usage

```bash
dot update                  # sync repos, apply overlays, merge configs, update deps
dot update -v               # verbose update
dot update --force          # bypass TTL caches and force reinstalls
dot update --cron           # quiet update, skipped when any repo is dirty
dot pull                    # alias for update
dot init REPOSITORY_URL     # initialize or resume the base client repository
dot fetch                   # fetch base + Git overlays
dot push                    # push base + Git overlays
dot status                  # status for base + Git overlays
dot diff                    # diff for base + Git overlays
dot cron                    # show installed cron entries
dot doctor                  # run installation health checks
```

`init`, `update`, `pull`, `cron`, and `doctor` work before the client repo exists.
`fetch`, `push`, `status`, and `diff` require it.

Use plain `git` for raw Git operations on the base repo. The tracked
`~/.local/bin/git` launcher routes `$HOME` and non-repo descendants to the base
client Git directory, while normal Git and Sapling checkouts still use real Git:

```bash
git add <file>
git commit
dot push
```

Git overlay repos are regular checkouts and are managed with
`git -C ~/.dotfiles-<name>`.

## Tool Installation and Ownership

`dot update` converges tools through several providers. Each command has one
authoritative owner on a given platform, although the owner may differ between
platforms when package availability, signing, or compatibility requires it.
Fallback providers must not shadow the authoritative installation.

Choose an owner according to the guarantees the tool needs, not merely which
installer is capable of installing it:

| Requirement | Preferred owner |
| --- | --- |
| Current package in an existing trusted system repository | `shdeps:pkg` |
| Portable executable needing a reviewed version and asset digest | mise |
| Repository checkout or automatically updated latest-compatible dependency | `shdeps:github` |
| Special wrapper, asset layout, or lifecycle handling | `shdeps:custom` |
| Neovim plugin code | Lazy |
| Missing editor-local executable on a supported workstation | Mason fallback |
| Project-specific runtime or tool version | Project-local mise config |

Prefer `shdeps:pkg` when the platform package is sufficiently current and
preserves required behavior. Package-manager ownership combines normal
automatic updates with the trusted repository's integrity or authentication
mechanisms and lifecycle.
Do not switch merely because a package name exists: compare it with the current
upstream version, retain documented compatibility floors and bug fixes, and
avoid adding an unrelated third-party repository solely to call an install a
system package. Similar tools with ambiguous package names, such as unrelated
`yq` implementations, also require an explicit package mapping.
For formatters and other output-producing tools, a package can still be
unsuitable when independently advancing platform versions would make results
diverge; keep those tools under one lock or update platform providers together
with compatibility tests.

When no suitable package exists, prefer mise for standalone release binaries
whose version or output affects builds, generated files, CI, or editor behavior.
The tracked `mise.lock` binds installs to reviewed release assets. Prefer Aqua
registry entries, then direct GitHub releases with complete locked platform
coverage; use UBI only for a documented backend-specific exception. A fuzzy
selector such as `latest` remains at its locked version until an intentional
`mise lock --bump` refresh, so lock updates should be reviewed and tested rather
than silently performed during normal convergence. If frequent updates are
desired, use a scheduled reviewed lock-bump workflow rather than weakening the
locked-install contract.

Use `shdeps:github` when repository ownership or automatic latest-compatible
updates are more important than a locked release asset. The generic `github`
method should choose between a release and checkout; force `github:repo` when a
source tree is required and `github:release` when falling back to a checkout
would be incorrect. Prefer upstream-published checksums for release binaries,
but do not treat a checksum downloaded beside an asset as independent publisher
authentication.

Lazy owns Neovim plugin code, not general-purpose language servers, formatters,
or linters. Externally installed commands from shdeps, mise, or the host remain
authoritative. Mason fills only missing editor-local tools where downloads are
supported and stays disabled on Android. A package may remain Mason-owned when
Neovim consumes assets beyond its command, such as `codelldb`'s LLDB libraries.

Avoid ad hoc global Cargo, Go, uv, npm, gem, and similar installs. Declare a
global dependency through shdeps or mise, and use a project-local mise config
when a repository needs its own runtime or tool version. Provider migrations
are complete only after the previous installation and any obsolete tracked
state have a safe retirement path.

## Dependency Docs

This file is the high-level map. Detailed behavior lives beside the files that
own it:

| Area | README |
| --- | --- |
| Dot config directories | [`.config/dot/README.md`](../../../../.config/dot/README.md) |
| Agent rule and playbook prose | [`.config/agent-rules/README.md`](../../../../.config/agent-rules/README.md) |
| Agent rule merge inputs | [`.config/dot/merge-hooks.d/agent-rules/README.md`](../../../../.config/dot/merge-hooks.d/agent-rules/README.md) |
| ds sessions | [`.config/ds/README.md`](../../../../.config/ds/README.md) |
| Overlay repos | [`.config/dot/overlays.d/README.md`](../../../../.config/dot/overlays.d/README.md) |
| Config merge hooks and cron | [`.config/dot/merge-hooks.d/README.md`](../../../../.config/dot/merge-hooks.d/README.md) |
| Git config | [`.config/git/README.md`](../../../../.config/git/README.md) |
| Git hooks | [`.local/lib/dotfiles/git-hooks/README.md`](../../../../.local/lib/dotfiles/git-hooks/README.md) |
| Hive Memory config | [`.config/hive-memory/README.md`](../../../../.config/hive-memory/README.md) |
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
| Client runtime layout | [`.local/lib/dotfiles/README.md`](../../../../.local/lib/dotfiles/README.md) |
| Dotfiles documentation index | [`.local/share/doc/dotfiles/README.md`](README.md) |
| Schema payloads | [`.local/share/checkrun/schemas/README.md`](../../../../.local/share/checkrun/schemas/README.md) |
| Test runner and client suites | [`.local/lib/dotfiles/tests/README.md`](../../../../.local/lib/dotfiles/tests/README.md) |

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

Dot's `shdeps_update_policy` controls how the provider is selected. The default
`pinned` policy keeps Dot's lock as the immutable revision and installer trust
boundary. This fleet uses `latest`: each update follows a valid user-owned
`cgraf78/shdeps` development checkout when present, or forces the managed
release path to check for the newest available release through the pinned
bootstrap. Network or metadata failures may retain a compatible last-known-good
managed release; `dot doctor` reports the active policy, selected source, and
revision or fallback diagnostics.

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

When a pull updates tracked client policy, the standalone runtime re-execs the
update so the remainder of the command uses the new policy.

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

The dotfiles-owned runner lives under `~/.local/lib/dotfiles/tests/` and uses
the standalone Dot test UI. See the
[`tests` README](../../../../.local/lib/dotfiles/tests/README.md) for suite
names, options, and CI coverage.
