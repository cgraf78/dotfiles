# dotsync — Bidirectional File Sync Across Hosts

`dotsync` syncs files across machines via rsync + SSH. Designed for dotfiles and config that live outside version control — the untracked companion to the `dot` bare git repo.

Files are listed in manifests, hosts are listed in config files. `dotsync sync` does bidirectional sync with conflict detection and 3-way merge. `push` and `pull` do simple one-way transfers.

## Quick Start

Prerequisites:
- SSH key access between machines (configure ports/keys in `~/.ssh/config`)
- `rsync` and `md5sum` on each host (standard on Linux; macOS has `md5`)
- No special server or daemon — just SSH

Add a host:
```bash
echo "dev2 dev2.example.com" >> ~/.config/dot/dotsync-hosts
```

Add files to sync:
```bash
echo ".bashrc_extra" >> ~/.config/dot/dotsync-paths
```

Push your files to the new host:
```bash
dotsync push dev2
```

From then on, keep everything in sync:
```bash
dotsync sync
```

## Files

- `~/.local/bin/dotsync` — the sync tool
- `~/.config/dot/dotsync-paths` — personal file manifest (tracked in dotfiles)
- `~/.config/dot/dotsync-paths-work` — work file manifest (tracked in dotfiles-work)
- `~/.config/dot/dotsync-paths-extra` — machine-local file manifest (untracked)
- `~/.config/dot/dotsync-hosts` — personal hosts (tracked in dotfiles)
- `~/.config/dot/dotsync-hosts-work` — work hosts (tracked in dotfiles-work)
- `~/.local/share/dot/dotsync/` — sync state (per-host file copies and checksums)

## Usage

```
dotsync push <host>     rsync listed files TO host
dotsync pull <host>     rsync listed files FROM host
dotsync sync            bidirectional sync with all reachable hosts
dotsync diff <host>     dry-run showing what sync would do
dotsync list            show all paths from all manifests
dotsync hosts           show configured hosts

Flags:
  --dry-run, -n         show what would be done without changes
```

### Examples

```bash
dotsync list                    # see what files are being synced
dotsync hosts                   # see configured hosts
dotsync diff dev2               # preview what sync would do
dotsync push dev2               # one-way push to dev2
dotsync pull dev1               # one-way pull from dev1
dotsync sync                    # sync everything with all reachable hosts
dotsync push myserver.com       # ad-hoc push (host not in config)
dotsync --dry-run sync          # show what sync would do across all hosts
dotsync push -n dev2            # show what push would transfer
```

## Manifests

Three tiers, merged based on host tier:

| Tier | File | Tracked in | Synced to |
|------|------|-----------|-----------|
| Personal | `dotsync-paths` | `~/.dotfiles` | All hosts |
| Work | `dotsync-paths-work` | `~/.dotfiles-work` | Work hosts only |
| Extra | `dotsync-paths-extra` | Nothing (per-machine) | All hosts |

Work paths are **never** synced to personal-tier hosts. This prevents work content from leaking to personal machines.

Format: one path per line, relative to `$HOME`. Blank lines and `#` comments allowed. Entries can be files or directories (directories are synced recursively).

Lines starting with `!` are excludes. Excludes take priority and support glob wildcards (`*` matches any string including `/`, `?` matches one character).

```
# Example manifest
.bashrc_extra
.config/dot
!.config/dot/dotsync-paths   # exclude a specific file
!*/__pycache__               # exclude __pycache__ dirs anywhere
!*.pyc                       # exclude all .pyc files
```

## Hosts

Two tiers, merged additively. The host's tier determines which manifest paths it receives:

| Tier | File | Tracked in | Receives |
|------|------|-----------|----------|
| Personal | `dotsync-hosts` | `~/.dotfiles` | Personal + extra paths |
| Work | `dotsync-hosts-work` | `~/.dotfiles-work` | Personal + work + extra paths |

Format: `alias ssh-destination`, one per line. SSH ports, keys, and proxy settings are handled via `~/.ssh/config`.

```
# alias    ssh-destination
dev1       dev1.example.com
nas        nas.grafhome.net
```

For ad-hoc usage, `push` and `pull` accept literal SSH destinations not in the config (e.g., `dotsync push myserver.example.com`).

## Sync Behavior

### push / pull

Simple one-way rsync. Transfers all existing files listed in the manifest. Does **not** propagate deletions. Updates sync state so subsequent `sync` calls have correct baselines.

### sync

Bidirectional sync with all configured hosts:

1. Skips the current machine (self-detection via hostname)
2. Probes each host with a 3-second SSH timeout; unreachable hosts are silently skipped
3. Compares local and remote file checksums against stored last-synced state
4. Takes action based on what changed:

| Local | Remote | Stored state | Action |
|-------|--------|-------------|--------|
| unchanged | unchanged | exists | skip |
| changed | unchanged | exists | push to remote |
| unchanged | changed | exists | pull from remote |
| changed | changed (same) | exists | update state only |
| changed | changed (different, text) | exists | 3-way merge via `diff3` |
| changed | changed (different, binary) | exists | save `.conflict` copy |
| missing | exists | exists | delete on remote |
| exists | missing | exists | delete locally |
| exists | missing | none | push to remote |
| missing | exists | none | pull from remote |
| exists (different) | exists | none | push (local wins on first sync) |

### First Sync

When no stored state exists, the local copy is treated as the source of truth. Files are pushed to the remote and baseline state is established. No merge is attempted.

### Conflicts

When both sides modify the same file:

- **Text files**: 3-way merge using `diff3 -m` with the stored last-synced copy as the merge base. If the merge succeeds, the result is pushed to both sides. If it fails, the local copy is kept and the remote version is saved as `<file>.conflict.<host>`.
- **Binary files**: No merge attempted. The remote version is saved as `<file>.conflict.<host>`.

### Deletions

When a file is deleted on one side and unchanged on the other, the deletion propagates. If a file is deleted on one side but modified on the other, it's treated as a conflict.

## Unreachable Hosts

`dotsync sync` probes each host before syncing (3-second SSH timeout). Unreachable hosts are skipped silently with a summary at the end:

```
synced: dev1, dev2
skipped: nas (unreachable)
```

## Cron Usage

`dotsync sync` is designed for unattended operation:

- No interactive prompts
- Lock file prevents concurrent runs (PID-based stale detection)
- Exit codes: 0 = success, 1 = merge conflicts, 2 = transfer errors

```crontab
*/30 * * * * $HOME/.local/bin/dotsync sync >> /tmp/dotsync.log 2>&1
```

## Testing

```bash
dotsync-test                  # unit tests (no SSH required)
dotsync-test --integration    # full suite including sync/push/pull via localhost SSH
```

## Dependencies

**Required**: `rsync`, `ssh`, `md5sum` (or `md5` on macOS), `file`
**Optional**: `diff3` (for 3-way merge; falls back to conflict-copy if missing)

Remote hosts need `rsync` and `md5sum`/`md5`. Missing dependencies are reported at startup.
