# ds — Dev Session Launcher

`ds` creates tmux sessions locally or on remote hosts with configurable profiles, per-host defaults, and multiple connection methods.

## Files

- `~/.local/bin/ds` — entry point (host resolution, remote connection, tmux session creation)
- `~/.config/ds/hosts*.conf` — per-host config (additive, personal + work in separate files)

All tracked via the `dot` bare repo.

## Usage

```
ds                        # bare session (default profile)
ds -p dev                 # chatbot + bash layout
ds -p orc                 # orc in top pane, bash below
ds -n work                # named session: ds-bare-work
ds myserver               # remote session (per hosts.conf)
ds -p bare nas            # remote bare session on nas
ds -l                     # list active ds sessions
ds -l myserver            # list active ds sessions on remote
ds -k ds-dev              # kill session by name
ds -k -p dev -n 2         # kill ds-dev-2
ds -k ds-dev myserver     # kill session on remote
def                       # alias for ds -p bare
def 2                     # alias for ds -p bare -n 2
```

## Profiles

Profiles define the tmux window/pane layout. Add new profiles by defining `_layout_<name>` functions in `ds`.

| Profile | Layout |
|---|---|
| `bare` | Single empty window (default) |
| `dev` | Chatbot in top pane, bash below, separate bash window |
| `orc` | Orc in top pane, bash below |

## hosts.conf Format

All `~/.config/ds/hosts*.conf` files are read (additive). This allows personal and work hosts to live in separate files. Five columns: hostname, connect method, chatbot, working directory, profile. Hostnames support glob patterns. First match wins across all files.

Personal hosts (`~/.config/ds/hosts.conf`):
```
# hostname    connect   chatbot   dir    profile
nas           autossh   argus     ~      bare
clark2        -         argus     ~      bare
```

Work hosts (`~/.config/ds/hosts-work.conf`, symlinked from work repo):
```
# hostname    connect   chatbot   dir        profile
myserver      ssh       claude    ~/code     dev
```

## Resolution Priority

1. First glob/exact match across all hosts*.conf files
2. Hardcoded fallback: `ssh` + `claude` + `~` + `bare`

CLI flags (`-p`, `-b`, `-c`, `-d`, `-n`) override resolved values at any level.

## Connect Methods

| Method | Command | Use case |
|---|---|---|
| `-` | (none) | Local-only host, no remote connections |
| `ssh` | `ssh HOST -t "ds ..."` | Standard SSH |
| `autossh` | `autossh -M0 HOST -t "ds ..."` | Auto-reconnecting SSH |
| `et` | `x2ssh -et HOST -c "ds ..." --noexit` | Eternal Terminal via x2ssh |

## Session Naming

Sessions are named `ds-<profile>[-<name>]`:

```
ds              → ds-bare
ds -p dev       → ds-dev
ds -n work      → ds-bare-work
ds -p dev -n 2  → ds-dev-2
```

## tmux Behavior

- **Outside tmux**: `tmux attach -t <session>`
- **Inside tmux**: `tmux switch-client -t <session>`
- If the session already exists, attaches/switches without recreating
- `detach-on-destroy off` in `.tmux.conf` switches to the next session on close instead of detaching
