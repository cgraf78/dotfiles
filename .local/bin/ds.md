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
ds                              # bare session (default profile)
ds -p dev                       # chatbot + bash layout
ds -p orc                       # orc in top pane, bash below
ds -n work                      # named session: ds-work
ds myserver                     # remote session (per hosts config)
ds -p bare nas                  # remote bare session on nas
ds -l                           # list active ds sessions
ds -l myserver                  # list active ds sessions on remote
ds -k dsdev                     # kill session by name
ds -k -p dev -n 2               # kill dsdev-2
ds -k dsdev myserver            # kill session on remote
ds --killall                    # kill all ds sessions

ds --share                      # share current session via upterm
ds --share dsdev                # share specific existing session
ds --unshare                    # stop sharing
ds --share-via upterm           # create/attach and share in one command
ds --share --push user@host     # also copy share info to remote host

ds --no-attach                  # create/share without attaching locally
ds --github-user <github_user>  # restrict upterm auth to GitHub user

dsdev                           # shortcut for ds -p dev
dsorc                           # shortcut for ds -p orc
```

## Profiles

Profiles define the tmux window/pane layout. `bare` is built into `ds`.
Additional profiles are pluggable scripts in `~/.config/ds/profile-<name>.sh`, each defining a `_profile_<name>()` function.
Shell shortcuts (`dsdev`, `dsfoo`, etc.) are auto-defined from discovered profiles.

To add a new profile, create `~/.config/ds/profile-myprofile.sh`:

```bash
_profile_myprofile() {
    local session="$1" chatbot="$2" dir="$3"
    # set up tmux windows/panes here
}
```

## Hosts Format

All `~/.config/ds/hosts*` files are read (additive). This allows personal and work hosts to live in separate files.
Four columns: hostname, connect method, chatbot, working directory.
Hostnames support glob patterns. First match wins across all files.

Personal hosts (`~/.config/ds/hosts`):

```text
# hostname    connect   chatbot   dir
nas           autossh   argus     ~
clark2        -         argus     ~
```

Work hosts (`~/.config/ds/hosts-work`, symlinked from work repo):

```text
# hostname    connect   chatbot   dir
myserver      ssh       claude    ~/code
```

## Resolution Priority

1. First glob/exact match across all `hosts*` files
2. Hardcoded fallback: `ssh` + `claude` + `~` + `bare`

CLI flags (`-p`, `-b`, `-c`, `-d`, `-n`) override resolved values per-field.

## Connect Methods

| Method | Command | Use case |
|---|---|---|
| `-` | (none) | Local-only host, no remote connections |
| `ssh` | `ssh HOST -t "ds ..."` | Standard SSH |
| `autossh` | `autossh -M0 HOST -t "ds ..."` | Auto-reconnecting SSH |
| `et` | `x2ssh -et HOST -c "ds ..." --noexit` | Eternal Terminal via x2ssh |

## Upterm Sharing

### One-session sharing model

Only one `ds` session can be shared at a time per socket.

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

- `~/.local/share/ds/`

This includes share metadata, upterm pid, admin socket path, and shared session name.
The directory is created with mode `0700`, and files are written with restrictive permissions (including `0600` for share info).

### Cleanup behavior

- `ds --unshare` stops upterm and cleans local share state.
- `ds -k <session>` auto-unshares first if that session is currently shared.
- `ds --killall` auto-unshares first, then kills all `ds*` sessions.

## Session Naming

Sessions are named `ds<profile>[-<name>]`:

```text
ds              → ds
ds -p dev       → dsdev
ds -n work      → ds-work
ds -p dev -n 2  → dsdev-2
```

## tmux Behavior

- **Outside tmux**: `tmux attach -t <session>`
- **Inside tmux**: `tmux switch-client -t <session>`
- If the session already exists, attaches/switches without recreating
- `detach-on-destroy off` in `.tmux.conf` switches to the next session on close instead of detaching
