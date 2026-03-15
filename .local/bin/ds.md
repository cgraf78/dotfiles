# ds — Dev Session Launcher

`ds` creates tmux dev sessions locally or on remote hosts. Profiles, connection methods, and share backends are all pluggable via `~/.config/ds/`.

## Files

- `~/.local/bin/ds` — main script
- `~/.config/ds/connect*.conf` — hostname-to-connect-method maps (additive, personal + work in separate files)
- `~/.config/ds/profile-<name>.sh` — profile layout plugins
- `~/.config/ds/connect-<method>.sh` — connection method plugins
- `~/.config/ds/share-<backend>.sh` — share backend plugins
- `~/.config/ds/share-<backend>.conf` — share backend config (e.g., `share-upterm.conf`)

All tracked via the `dot` bare repo (work-specific files symlinked from `~/.dotfiles-work`).

## Usage

```bash
ds                              # default session "ds" (plain tmux session)
ds dev                          # session "dev" with dev profile
ds dev-work                     # session "dev-work" with dev profile
ds dev-2                        # session "dev-2" with dev profile

ds dev @myhost                  # dev session on remote host
ds @myhost                      # default session on remote host

ds -l                           # list active ds sessions
ds -l @myhost                   # list sessions on remote host

ds -k dev                       # kill session "dev"
ds -k                           # kill current session (inside tmux)
ds -k dev @myhost               # kill session on remote host
ds --killall                    # kill all ds sessions
ds --killall @myhost            # kill all ds sessions on remote host

ds --share                      # share current session (inside tmux)
ds --share dev                  # share session "dev"
ds --unshare                    # stop sharing current session
ds --unshare dev                # stop sharing session "dev"
ds --share-via upterm           # create/attach and share in one step

ds init bash                    # print shell integration snippet
```

## Session Naming

Sessions are named after their profile, with an optional dash-separated instance tag:

```text
ds              → "ds"          (default, plain tmux session)
ds dev          → "dev"         (dev profile)
ds dev-work     → "dev-work"    (dev profile, "work" instance)
ds dev-2        → "dev-2"       (dev profile, second instance)
```

The profile is resolved from the session name: split on the first `-`, and if the left side matches a known profile, that profile is used. Unknown profiles produce an error. Profile names must not contain dashes.

The default session `ds` is special — it creates a plain tmux session with no layout.

## Shell Integration

`ds init bash` prints a snippet to source in `.bashrc` that provides:

- **Auto-attach on SSH login** — when SSHing into a host, automatically creates/attaches a `ds` session. Skip with `NO_TMUX=1`.
- **ET attach-next** — reads a state file written by the ET connect plugin to join the correct session on connect.

## Profiles

Profiles define the tmux window/pane layout. Additional profiles are pluggable scripts in `~/.config/ds/profile-<name>.sh`, each defining a `_profile_<name>()` function:

```bash
# ~/.config/ds/profile-myprofile.sh
_profile_myprofile() {
    local session="$1"
    # set up tmux windows/panes here
}
```

Profile names must be simple words without dashes (e.g., `dev`).

Profiles configure their own behavior via environment variables. For example, the `dev` profile reads `DS_DEV_CHATBOT` and `DS_DEV_DIR`.

### Dev profile

The `dev` profile creates a chatbot pane (top), a bash pane (bottom), and a separate bash window.

| Variable | Default | Description |
|---|---|---|
| `DS_DEV_CHATBOT` | *(empty — no chatbot)* | Command to run in the top pane (e.g., `argus`, `claude`) |
| `DS_DEV_DIR` | `~` | Working directory for all panes/windows |

Set these in `~/.bashrc` (personal) or `~/.bashrc_work` (work) to configure per-machine defaults.

## Host Resolution

All `~/.config/ds/connect*.conf` files are read (additive). This allows personal and work hosts to live in separate files. Format is two columns: hostname and connect method. Hostnames support glob patterns. First match wins across all files.

Remote hosts are specified with the `@` prefix:

```bash
ds dev @myhost       # dev session on myhost
ds @myhost           # default session on myhost
ds -l @myhost        # list sessions on myhost
ds -k dev @myhost    # kill session on myhost
ds --killall @myhost # kill all on myhost
```

Personal hosts (`~/.config/ds/connect.conf`):

```text
# hostname    connect
nas           autossh
taylor        autossh
```

Work hosts (`~/.config/ds/connect-work.conf`, symlinked from work repo):

```text
# hostname    connect
cgrafdev      autossh
dev*          autossh
```

### Resolution priority

1. First glob/exact match across all `connect*.conf` files
2. Fallback: `ssh` connect method

CLI flag `-c` overrides the resolved connect method.

## Connect Methods

`ssh` is built-in. Other methods are plugins in `~/.config/ds/connect-<method>.sh`, each defining a `_connect_<method>` function:

```bash
# ~/.config/ds/connect-mymethod.sh
_connect_mymethod() {
    local host="$1" remote_cmd="$2" session="$3" action="$4" ds_args="$5"
    # action is "session", "list", "kill", or "killall"
    # remote_cmd is a pre-built "bash -lc 'ds ...'" string for non-session actions
}
```

For `session` actions the plugin owns the full connect lifecycle (and may ignore `remote_cmd`). For `list`/`kill`/`killall` it typically falls back to `ssh $host -t "$remote_cmd"`.

| Method | Plugin | Use case |
|---|---|---|
| `-` | (none) | Local-only host, no remote connections |
| `ssh` | built-in | Standard SSH |
| `autossh` | `connect-autossh.sh` | Auto-reconnecting SSH |
| `et` | `connect-et.sh` | Eternal Terminal via x2ssh |

## Sharing

Share backends are plugins in `~/.config/ds/share-<backend>.sh`. If only one backend is installed, `ds --share` auto-selects it; otherwise use `--share-via <backend>`.

Only one session can be shared at a time. `ds -l` marks the shared session with `[shared]`.

Sharing is local only — `@host` is not supported with `--share` or `--unshare`.

When no session name is given, `--share` and `--unshare` default to the current tmux session (must be inside tmux).

### Share plugin interface

A share backend must define all of:

- `_share_start <session>` — start sharing, call `_write_share_info` with connection info
- `_share_stop <session>` — stop sharing, clean up state files
- `_share_running` — return 0 if sharing is active
- `_share_current_session` — print name of the shared session
- `_share_info` — print current share connection info
- `_share_load_config` — load backend-specific config from `share-<backend>.conf`

### Upterm config

All upterm backend config lives in `~/.config/ds/share-upterm.conf`. Env vars (`DS_UPTERM_*`) override config values.

| Config key | Env var | Description |
|---|---|---|
| `server` | `DS_UPTERM_HOST` | Upterm server `host:port` (default: `uptermd.upterm.dev:22`) |
| `known-hosts` | `DS_UPTERM_KNOWN_HOSTS` | Known hosts file for server identity verification |
| `private-key` | `DS_UPTERM_PRIVATE_KEY` | SSH private key (auto-detected if unset) |
| `github-user` | `DS_UPTERM_GITHUB_USER` | Restrict access to a GitHub user |
| `authorized-keys` | `DS_UPTERM_AUTHORIZED_KEYS` | Restrict access via an authorized_keys file |
| `push` | `DS_UPTERM_PUSH` | `user@host` target — pushes share info via SCP |

Example `share-upterm.conf`:

```text
github-user=argusbot78
push=openclaw@taylor
```

### Self-hosted server

To share through a private Upterm server instead of the public one:

```text
# ~/.config/ds/share-upterm.conf
server=myupterm.internal:2222
known-hosts=~/.ssh/upterm_known_hosts
authorized-keys=~/.ssh/upterm_authorized_keys
```

`known-hosts` is strongly recommended for private servers. Without it, `ds` warns about the missing host key verification and prompts for confirmation before proceeding.

For one-off server overrides, use the env var:

```bash
DS_UPTERM_HOST=myupterm.internal:2222 ds --share
```

### Share workflows

1. **Share an already-running session:**
   ```bash
   ds --share [session]
   ```
2. **Create/attach and share in one shot:**
   ```bash
   ds dev --share-via upterm
   ```

### Cleanup behavior

- `ds --unshare` stops sharing and cleans local state.
- `ds -k <session>` auto-unshares first if that session is currently shared.
- `ds --killall` auto-unshares first, then kills all ds-managed sessions.

## Current Session Defaults

When inside a tmux session, `-k`, `--share`, and `--unshare` default to operating on the current session if no session name is given. If not inside tmux and no session name is given, these commands error.

This default is local only — remote operations (`@host`) always require an explicit session name.

## State

Runtime state lives under `~/.local/state/ds/` (mode `0700`). Includes share metadata, upterm PID, admin socket path, shared session name, and ET attach-next targets.

## tmux Behavior

- **Outside tmux**: `tmux attach -t <session>`
- **Inside tmux**: `tmux switch-client -t <session>`
- If the session already exists, attaches/switches without recreating
- `detach-on-destroy off` in `.tmux.conf` switches to the next session on close instead of detaching

Sessions are tagged with a `DS_MANAGED` tmux environment variable on creation. `ds -l` and `ds --killall` use this tag to identify ds-managed sessions.
