# Dot Overlays

Overlays extend the base dotfiles with work, machine-specific, or
project-specific files. Each overlay is declared by a config file in this
directory.

## Adding An Overlay

1. Create a conf file such as `10-work.conf`.
2. Track it in the base repo with `git add` from `$HOME`.
3. Run `dot update` or `dotbootstrap`.

When the overlay matches the current machine and its remote is reachable,
`dot update` clones it to `~/.dotfiles-<name>` and symlinks files from its
`home/` directory into `$HOME`.

For an existing checkout, `dot update` requires its recorded `origin` URL to
match the configured `url` exactly before pulling. The exact comparison keeps
local paths and SSH host aliases authoritative instead of guessing that two URL
spellings name the same repository. A mismatch is left untouched and reports an
explicit adoption command appropriate to the checkout's origin state; run that
command only after verifying that the checkout is the intended overlay. Missing
and ambiguous origins use `remote add` and `config --replace-all`, respectively.
Relative local URLs are resolved from `$HOME` before cloning and comparison, so
their identity does not depend on the directory where `dot update` is invoked.

Adding a file to an existing overlay is just normal Git work in that overlay:
add the file under `home/`, commit it, push it, and run `dot update`.

## Conf Format

```text
url=git@github.com:user/dotfiles-work.git
optional=true
platforms=linux
hosts=workbox1
```

- `sync` defaults to `git`; set it to `none` only for a filesystem-managed
  source as described below.
- `url` is required for Git overlays.
- `optional` is optional. Set it to `true` for private overlays that should be
  used when available but skipped when the current machine cannot clone or pull
  them. Leave it unset for required overlays; missing keys or clone failures are
  reported as update failures.
- `platforms` is optional. Values are `linux`, `macos`, and `wsl`.
- `hosts` is optional and matches `hostname -s`, case-insensitively.

Prefix a platform or host with `!` to exclude it. When both `platforms` and
`hosts` are present, both must match. A conf with no filters applies
everywhere.

## Names And Priority

The filename determines both the overlay name and the link order:

```text
05-personal.conf -> personal -> ~/.dotfiles-personal
10-work.conf     -> work     -> ~/.dotfiles-work
20-nas.conf      -> nas      -> ~/.dotfiles-nas
```

Numeric prefixes sort alphabetically. When multiple overlays provide the same
file, the later overlay wins.

## Overlay Repo Layout

Only files under `home/` are linked into `$HOME`.

```text
my-overlay-repo/
├── home/
│   ├── .config/shell/env.d/80-myoverlay.sh
│   ├── .config/shell/interactive.d/80-aliases.sh
│   ├── .config/dot/merge-hooks.d/myapp/README.md
│   ├── .config/shdeps/hooks.d/mytool.sh
│   ├── .local/bin/my-script
│   └── .local/lib/dot/core/merge-hooks/myapp.sh
└── README.md
```

Files outside `home/` stay inside the overlay repo.

Create a new overlay repo with any repo name; the local clone destination is
derived from the conf filename.

```bash
mkdir -p ~/my-overlay-repo/home
git -C ~/my-overlay-repo init
# add files under home/
git -C ~/my-overlay-repo add -A
git -C ~/my-overlay-repo commit -m "initial"
# push to a remote, then create the conf in the base repo
```

No extra overlay-specific plugin point is needed. Symlinking into `$HOME` makes
overlay-provided files appear in the same directories that `dot update` already
scans, such as `merge-hooks.d`, `hooks.d`, shell config directories, and
`.local/bin`.

## Filesystem-Managed Sources

Use a machine-local `*.local.conf` descriptor when another tool or a manual
setup step already places the overlay source on disk. These descriptors live in
the normal `~/.config/dot/overlays.d/` directory and are ignored by the public
base repository:

```text
sync=none
path=~/projects/example-overlay
```

The source uses the same `home/` layout as a Git overlay. `dot update` links its
files and runs the normal merge, dependency, and cleanup lifecycle, but it does
not run Git, synchronize, configure, or otherwise manage the source repository.
The filesystem overlay is also omitted from `dot fetch`, `dot push`,
`dot status`, and `dot diff`.

`path` must be an absolute path or start with `~/`. It may contain spaces. A
`sync=none` descriptor cannot also set `url`, `optional`, or use a companion
`.ssh` file. Its `.local.conf` suffix is not part of the overlay name, so
`10-project.local.conf` names the overlay `project`.

An active filesystem source must have a readable, searchable `home/` directory
and readable file entries. Source symlinks must resolve to usable files or
directories. If validation fails, `dot update` stops before repository
synchronization or finalization; `dotbootstrap` validates after the base
checkout and before overlay pulls or finalization. Removing a source file
removes its managed link on the next successful update. Removing the descriptor
removes all of its managed links without needing the source tree to remain
available; user-replaced paths are preserved.

For a manual cutover from a Git overlay, avoid running both descriptors with
the same name at once:

1. Pause scheduled updates and back up the source plus any user files at paths
   the overlay owns.
2. Remove the tracked Git descriptor upstream, run `dot update` to receive that
   change, then run it once more with no same-name replacement descriptor. The
   second pass guarantees rediscovery and cleanup even when the first pull did
   not need to re-exec the CLI.
3. Verify a placeholder `*.local.conf` path is ignored with `git check-ignore`
   before putting a private path in it.
4. Place the filesystem source and local descriptor, then run `dot update` and
   `dot doctor`.

To roll back, remove the local descriptor and run `dot update` before restoring
the previous Git descriptor. This keeps each cleanup pass under one source of
authority and requires no compatibility mode.

## Private Overlays

Use `optional=true` for private overlays that should not exist on every
machine. `dot update` and `dotbootstrap` try to clone or pull optional overlays
when the configured Git URL is accessible, but a failed clone or pull is treated
as "not available here" instead of failing the whole update. This is the right
shape for personal private overlays that should automatically appear on
machines where normal GitHub SSH authentication has access:

```text
url=git@github.com:user/dotfiles-personal.git
optional=true
```

Some private overlays also need a dedicated SSH deploy key for access control.
Those overlays can have a companion `.ssh` file next to the `.conf` file:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/<name>-deploy -C "<name> deploy key" -N ""
scp ~/.ssh/<name>-deploy <other-host>:~/.ssh/
```

Add the public key as a deploy key on the remote. Enable write access only on
machines that should push to that overlay.

```text
Host github-dotfiles-work
  HostName github.com
  User git
  IdentityFile ~/.ssh/dotfiles-work-deploy
  IdentitiesOnly yes
```

Point the conf URL at that host alias:

```text
url=github-dotfiles-work:user/dotfiles-work.git
optional=true
```

`dot update` and `dotbootstrap` merge these SSH snippets into `~/.ssh/config`.
Machines without the key skip the optional overlay until the key is installed.
For a required deploy-key overlay, a missing key is an error. For a new machine
that should use a required deploy-key overlay, copy the private key before
bootstrapping or add it later and rerun `dot update`.

## Removal

When an overlay conf is deleted or its filters stop matching the current
machine, `dot update` removes that overlay's symlinks and restores any shadowed
base-repo files.
