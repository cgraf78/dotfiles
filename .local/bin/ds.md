# ds — Dev Session Launcher

`ds` creates tmux sessions locally or on remote hosts with configurable profiles, per-host defaults, and multiple connection methods.

It also supports **Upterm-based sharing** so another machine/user can join an existing `ds` tmux session securely over SSH.

## Files

- `~/.local/bin/ds` — entry point (host resolution, remote connection, tmux session creation, sharing)
- `~/.config/ds/hosts*` — per-host config (additive, personal + work in separate files)
- `~/.config/ds/profile-<name>.sh` — pluggable profile layouts
- `~/.config/ds/share` — optional sharing defaults (`push=...`, `github-user=...`)

All tracked via the `dot` bare repo.

## Usage

```bash
ds                              # session named "ds" (default)
ds -p dev                       # session named "ds" with dev layout
ds -p orc                       # session named "ds" with orc layout
ds -n work                      # session named "work"
ds -p dev -n work               # session named "work" with dev layout
ds myserver                     # remote session (per hosts config)
ds -p bare nas                  # remote bare session on nas
ds -l                           # list active ds sessions
ds -l myserver                  # list active ds sessions on remote
ds -k work                      # kill session by name
ds -k work myserver             # kill session on remote
ds --killall                    # kill all ds sessions

ds --share                      # share current session via upterm
ds --share work                 # share specific existing session
ds --unshare                    # stop sharing
ds --share-via upterm           # create/attach and share in one command
ds --share --push user@host     # also copy share info to remote host

ds --no-attach                  # create/share without attaching locally
ds --github-user <github_user>  # restrict upterm auth to GitHub user

dsdev                           # session "dsdev" with dev layout
dsdev -n foo                    # session "foo" with dev layout
dsorc                           # session "dsorc" with orc layout
```

## Profiles

Profiles define the tmux window/pane layout. `bare` is built into `ds`.
Additional profiles are pluggable scripts in `~/.config/ds/profile-<name>.sh`, each defining a `_profile_<name>()` function that receives the session name as its only argument.
Shell shortcuts (`dsdev`, `dsfoo`, etc.) are auto-defined from discovered profiles. Each defaults its session name to the command name (e.g., `dsdev` → session `dsdev`), overridable with `-n`.

Profiles configure their own behavior via environment variables. For example, the `dev` profile reads `DS_DEV_CHATBOT` and `DS_DEV_DIR`.

To add a new profile, create `~/.config/ds/profile-myprofile.sh`:

```bash
_profile_myprofile() {
    local session="$1"
    # set up tmux windows/panes here
}
```

### Dev profile

The `dev` profile creates a chatbot pane (top), a bash pane (bottom), and a separate bash window. Configured via environment variables:

| Variable | Default | Description |
|---|---|---|
| `DS_DEV_CHATBOT` | *(empty — no chatbot)* | Command to run in the top pane (e.g., `argus`, `claude`) |
| `DS_DEV_DIR` | `~` | Working directory for all panes/windows |

Set these in `~/.bashrc` (personal) or `~/.bashrc_work` (work) to configure per-machine defaults.

## Hosts Format

All `~/.config/ds/hosts*` files are read (additive). This allows personal and work hosts to live in separate files.
Two columns: hostname and connect method.
Hostnames support glob patterns. First match wins across all files.

Personal hosts (`~/.config/ds/hosts`):

```text
# hostname    connect
nas           autossh
clark2        -
```

Work hosts (`~/.config/ds/hosts-work`, symlinked from work repo):

```text
# hostname    connect
myserver      ssh
```

## Resolution Priority

1. First glob/exact match across all `hosts*` files
2. Hardcoded fallback: `ssh` connect method, `bare` profile

CLI flags (`-p`, `-c`, `-n`) override resolved values per-field.

## Connect Methods

| Method | Command | Use case |
|---|---|---|
| `-` | (none) | Local-only host, no remote connections |
| `ssh` | `ssh HOST -t "ds ..."` | Standard SSH |
| `autossh` | `autossh -M0 HOST -t "ds ..."` | Auto-reconnecting SSH |
| `et` | `x2ssh -et HOST -c "ds ..." --noexit` | Eternal Terminal via x2ssh |

## Upterm Sharing

### One-session sharing model

Only one `ds` session can be shared at a time.

- If you share a second session while one is already shared, `ds` errors and tells you to run `ds --unshare` first.
- `ds -l` marks the shared session with `[shared]`.

### Share workflows

1. **Share an already-running session**
   ```bash
   ds --share [session]
   ```
2. **Create/attach and share in one shot**
   ```bash
   ds --share-via upterm
   ```

### Auth + push options

- `--github-user <user>` limits upterm access to that GitHub user.
- `--push user@host` copies the generated share info file to `~/.ds/shares/` on another host.
- Optional defaults can be set in `~/.config/ds/share`:

```text
push=openclaw@taylor
github-user=argusbot78
```

### State files and permissions

`ds` writes runtime share state under:

- `~/.local/state/ds/`

This includes share metadata, upterm pid, admin socket path, and shared session name.
The directory is created with mode `0700`, and files are written with restrictive permissions (including `0600` for share info).

### Cleanup behavior

- `ds --unshare` stops upterm and cleans local share state.
- `ds -k <session>` auto-unshares first if that session is currently shared.
- `ds --killall` auto-unshares first, then kills all ds-managed sessions.

## Session Naming

`--name` sets the exact session name. Default is `ds`. Profile controls layout only, not the name.

```text
ds              → ds
ds -p dev       → ds
ds -n work      → work
ds -p dev -n 2  → 2
dsdev           → dsdev
dsdev -n foo    → foo
```

Sessions are tagged with a `DS_MANAGED` tmux environment variable on creation. `ds -l` and `ds --killall` use this tag to identify ds-managed sessions (rather than matching session name prefixes).

## tmux Behavior

- **Outside tmux**: `tmux attach -t <session>`
- **Inside tmux**: `tmux switch-client -t <session>`
- If the session already exists, attaches/switches without recreating
- `detach-on-destroy off` in `.tmux.conf` switches to the next session on close instead of detaching
