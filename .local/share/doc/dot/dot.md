# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Base dotfiles managed as a bare git repository with `$HOME` as the working tree, plus overlay repos for work, machine-specific, or project-specific dotfiles.

- **`~/.dotfiles`** — bare repo, base dotfiles (public)
- **`~/.dotfiles-<name>`** — overlay repos, discovered from `~/.config/dot/overlays.d/*.conf`

Overlay files are symlinked into `$HOME` by `dot update`. Base dotfiles use `[ -f ]` guards to source overlay files only when present.

**macOS note:** Requires Bash 4+ (`brew install bash`). The system Bash (3.2) is too old.

## Quick Start

Personal machine:

```bash
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Machine with a private overlay (e.g., work):

```bash
# 1. Copy the overlay's deploy key (from any machine that has it)
scp <source>:~/.ssh/<deploy-key> ~/.ssh/
chmod 600 ~/.ssh/<deploy-key>

# 2. Bootstrap (clones base repo + matching overlays)
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Overlay repos hosted on private remotes use SSH deploy keys for access control. Each overlay can include a companion `.ssh` file in `overlays.d/` that defines the SSH host alias for its remote (see [Overlays](#overlays)). Machines without the deploy key skip the overlay and continue.

On subsequent runs, `dotbootstrap` pulls the base repo and clones any overlay repos defined in `~/.config/dot/overlays.d/`. The bootstrap script automatically backs up any conflicting files to `~/.dotfiles-backup/<timestamp>/`.

Bootstrap automatically installs a cron that keeps the machine updated (see [Auto-update cron](#auto-update-cron)).

## Usage

```bash
dot update            # sync everything: pull repos, merge configs, update deps
dot update --cron     # same, but quiet + skip if worktree is dirty (for cron)
dot pull              # same as update (requires bare repo)
dot fetch             # fetch all repos (without updating working copy)
dot push              # push all repos
dot status            # check status of all repos
dot diff              # diff all repos
dot cron              # show installed cron entries
dot git <command>     # run any git command on the base repo
```

All commands require the bare repo. Use `dot git` for raw git operations on the base repo (e.g., `dot git add`, `dot git commit`, `dot git log`).

Overlay repos are managed with plain `git -C ~/.dotfiles-<name>` for commits.

To add a new file to the base repo:

```bash
dot git add <file> && dot git commit -m "add <file>" && dot push
```

## How It Works

- `dot update` syncs everything: pulls repos (base + overlays), merges configs, updates deps
- If a pull updates dot infrastructure (`.local/lib/dot/` or `.local/bin/dot`), the script re-execs itself so the rest of the run uses the new code
- `dot fetch/pull/push/status/diff` operates on base + all active overlays
- Overlay files are symlinked from `~/.dotfiles-<name>/home/` into `$HOME`
- Files that override base versions get `--skip-worktree` to prevent phantom dirty status
- Missing overlay repos are cloned automatically when their conf and deploy key are present
- No branch sync, no markers — just independent repos. Every machine is a peer

## Overlays

Overlay repos extend the base dotfiles with additional files. Each overlay is defined by a config file in `~/.config/dot/overlays.d/`:

```text
~/.config/dot/overlays.d/
├── 10-work.conf
└── 20-nas.conf
```

### Adding an overlay

1. Create a conf file: `~/.config/dot/overlays.d/10-work.conf`
2. Track it in the base repo: `dot git add .config/dot/overlays.d/10-work.conf`
3. Run `dot update` or `dotbootstrap` — the overlay is cloned and linked automatically.

### Adding an overlay file

Add the file to the overlay repo under `home/`, commit, and push. The next `dot update` symlinks it into `$HOME`.

### Overlay removal

When an overlay conf is deleted or its filter stops matching, `dot update` automatically removes its symlinks from `$HOME` and restores any shadowed base-repo files.

### Conf file format

```text
url=git@github.com:user/dotfiles-work.git
platforms=linux
hosts=workbox1
```

- **`url`** (required) — git remote URL.
- **`platforms`** (optional) — comma-separated platform filter. Values: `linux`, `macos`, `wsl`. Prefix with `!` to exclude.
- **`hosts`** (optional) — comma-separated hostname filter (matches `hostname -s`, case-insensitive). Prefix with `!` to exclude.

When both `platforms` and `hosts` are specified, both must match (AND logic). No filter keys = all machines. Overlays that don't match the current machine are skipped entirely (not cloned, not pulled, not linked).

### Naming and priority

The filename determines the overlay name and priority:

- `10-work.conf` → overlay name `work` → cloned to `~/.dotfiles-work`
- `20-nas.conf` → overlay name `nas` → cloned to `~/.dotfiles-nas`

Numeric prefixes control ordering (same convention as shell config and merge hooks). When multiple overlays provide the same file, **last wins** (alphabetically by filename).

### How overlays contribute configs

Overlays contribute merge hooks, shdeps configs, shell config, and scripts by placing files under `home/` at the right paths. Because these files are symlinked into `$HOME`, they appear in the same directories that `dot update` already scans:

- **Merge hooks** — `home/.config/dot/merge-hooks.d/80-*.sh` (use 80+ prefix to run after base 50-\* hooks)
- **Shdeps hooks** — `home/.config/shdeps/hooks.d/<name>.sh`
- **Shell config** — `home/.config/shell/env.d/80-*.sh`, `home/.config/shell/interactive.d/80-*.sh`
- **Cron entries** — `home/.config/dot/merge-hooks.d/cron.local` (untracked locally, or a numbered cron file)
- **Scripts** — `home/.local/bin/<name>`

No special overlay mechanism needed — symlinking into `$HOME` is sufficient.

### Creating a new overlay repo

The repo can be named anything — the clone destination is always `~/.dotfiles-<name>`, derived from the conf filename (e.g., `10-work.conf` → `~/.dotfiles-work`).

```bash
mkdir -p ~/my-overlay-repo/home
cd ~/my-overlay-repo
git init
# add files under home/ (see structure below)
git add -A && git commit -m "initial"
# push to a remote, then create the conf in the base repo
```

The overlay repo has one required convention: files to be symlinked into `$HOME` go under `home/`, mirroring the `$HOME` directory structure:

```text
my-overlay-repo/
├── home/
│   ├── .config/shell/env.d/80-myoverlay.sh      (shell config)
│   ├── .config/shell/interactive.d/80-aliases.sh (interactive aliases)
│   ├── .config/dot/merge-hooks.d/80-myapp.sh     (merge hook)
│   ├── .config/shdeps/hooks.d/mytool.sh          (shdeps hook)
│   └── .local/bin/my-script                      (scripts)
└── ...                                           (non-home files, not symlinked)
```

Everything under `home/` is symlinked into `$HOME` by `dot update`. Files outside `home/` (READMEs, configs for the overlay repo itself) are not symlinked.

### Private overlays (deploy keys)

Overlays hosted on private remotes use SSH deploy keys for access control. The deploy key determines which machines can access the overlay — no platform or host filtering needed.

**One-time setup (per overlay):**

1. Generate a deploy key and copy it to every machine that needs access:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/<name>-deploy -C "<name> deploy key" -N ""
   scp ~/.ssh/<name>-deploy <other-host>:~/.ssh/
   ```
2. Add the public key (`~/.ssh/<name>-deploy.pub`) as a deploy key on the git remote (GitHub repo → Settings → Deploy keys). Enable write access if you push from these machines.
3. Create a companion `.ssh` file next to the conf:
   ```text
   ~/.config/dot/overlays.d/10-work.ssh
   ```
   ```text
   Host github-dotfiles-work
     HostName github.com
     User git
     IdentityFile ~/.ssh/dotfiles-work-deploy
     IdentitiesOnly yes
   ```
4. Set the conf's `url` to use the SSH alias:
   ```text
   url=github-dotfiles-work:user/dotfiles-work.git
   ```
5. Track both files: `dot git add .config/dot/overlays.d/10-work.conf .config/dot/overlays.d/10-work.ssh`

The `.ssh` file is merged into `~/.ssh/config` automatically during `dot update` and `dotbootstrap`. Machines without the deploy key silently skip the overlay — once the key is added, the next `dot update` clones it automatically.

**Provisioning a new machine:** copy the private key (`~/.ssh/<name>-deploy`) to the machine before running `dotbootstrap`, or add it later and run `dot update`.

## Auto-update cron

`dot update` installs cron entries from `~/.config/dot/merge-hooks.d/cron` into the user crontab. By default this runs `dot update --cron` every 30 minutes, keeping all machines up to date automatically.

The `--cron` flag enables two safety behaviors:

- **Skip if dirty** — if any repo has uncommitted changes, the update is skipped entirely. This prevents stomping on in-progress dotfile editing.
- **Quiet mode** — suppresses all output unless something goes wrong.

To change the schedule or add more cron entries, edit `~/.config/dot/merge-hooks.d/cron`. The file is a tracked dotfile — changes propagate to all machines on the next `dot update`. For machine-local entries that shouldn't propagate, use `~/.config/dot/merge-hooks.d/cron.local` (same format, untracked). Lines starting with `#` are comments. `$HOME` is expanded and `PATH` is injected automatically at install time.

Run `dot cron` to see what's currently installed.

### Cron filter directives

Use `# filter:` directives to restrict entries to specific hosts or platforms:

```text
# Runs everywhere (default — no filter needed)
*/30 * * * * $HOME/.local/bin/dot update --cron

# filter: hosts=nas
0 3 * * * $HOME/.local/bin/backup-nas
0 4 * * 0 $HOME/.local/bin/scrub-zpool

# filter: hosts=!nas platforms=linux
0 6 * * * $HOME/.local/bin/linux-non-nas-task

# filter: *
0 7 * * * $HOME/.local/bin/common-task
```

Each `# filter:` line fully replaces the previous filter. Entries before any directive default to all. `# filter: *` resets to all. When both `hosts` and `platforms` are specified, both must match (AND logic). Filter state resets between `cron` and `cron.local`.

Platform values: `linux`, `macos`, `wsl`. Prefix with `!` to exclude. Comma-separated for multiple values (e.g., `platforms=linux,macos`, `platforms=!wsl`). Hosts match against the short hostname (`hostname -s`), case-insensitive.

## Shell Config

`.bashrc` and `.zshrc` are thin loaders that source files from
`~/.config/shell/` in two phases. Files use numeric prefixes for load order
and extensions to indicate shell compatibility: `.sh` (any shell), `.bash`
(bash-specific), `.zsh` (zsh-specific).

```text
.bashrc / .zshrc
├── env.d/                          (all shells, interactive and non-interactive)
│   ├── 10-work-bootstrap.sh        (work — devserver system config, must load first)
│   ├── 50-core.sh                  (exports, history settings)
│   ├── 60-path.sh                  (PATH assembly)
│   ├── 70-platform.sh              (Homebrew, stty)
│   └── 80-work.sh                  (work — build modes, proxy, PARA, gdrive)
├── .bashrc_local / .zshrc_local               (machine-local, not tracked)
├── .bashrc_local_work / .zshrc_local_work     (machine-local work-only, not tracked)
└── interactive.d/                  (interactive shells only)
    ├── 50-aliases.sh               (tool aliases, SSH, platform-specific)
    ├── 60-prompt.bash / .zsh       (prompt, git branch indicators)
    ├── 70-integrations.bash / .zsh (fzf, zoxide, atuin, ds)
    ├── 80-work-aliases.sh          (work — project build/run/test shortcuts)
    └── 90-work-integrations.bash   (work — arc completions)
```

Base files (50-70) are in the base repo. Work files (10, 80-90) are symlinked from the work overlay by `dot update`.

## App Config Merges

`dot update` merges tracked config files into their app-specific locations. Merge hooks in `~/.config/dot/merge-hooks.d/` handle each app.

### VS Code

Settings and keybindings in `~/.config/dot/vscode/` are merged into VS Code's config dirs:

```text
~/.config/dot/vscode/
├── settings.json             (cross-platform)
├── keybindings.json          (common keybindings, all platforms)
├── keybindings-mac.json      (macOS-specific)
├── keybindings-windows.json  (Windows/WSL-specific)
└── keybindings-linux.json    (Linux-specific)
```

Merge policy: dotfiles win on conflicts, local-only settings/keybindings are preserved, JSONC comments are stripped.

### iTerm2 (macOS)

Dynamic Profile in `~/.config/dot/iterm2/dotfiles-dyn-profile.json` is copied into iTerm2's DynamicProfiles dir. Set it as default in Preferences.

### Karabiner (macOS)

Profiles in `~/.config/dot/karabiner/karabiner.json` are merged into Karabiner's config. Dotfiles profiles replace local profiles with the same name; local-only profiles are preserved.

### WezTerm

`~/.config/wezterm/wezterm.lua` is the WezTerm config file. Tracked directly. On WSL, `dot update` copies it to the Windows home so the Windows-native WezTerm picks it up.

## Dependency System

`dot update` installs and upgrades tools via [shdeps](https://github.com/cgraf78/shdeps), configured in `~/.config/shdeps/deps.conf`. Each line declares a dependency with a name and install method:

```text
# name               method           cmd          aliases                  filter
jq                   pkg
bat                  pkg              apt:batcat
fd                   pkg              apt:fdfind   apt:fd-find,dnf:fd-find
cgraf78/ds           github:repo
neovim/neovim        github:release   nvim
direnv/direnv        github:release
nerd-fonts           custom
dust                 pkg              -            -                        os:macos
```

**Methods:**

- **`pkg`** — system package (`brew`, `apt`, `dnf`, `pacman`). Batches all packages into one install command.
- **`github:repo`** — clones from GitHub into `$SHDEPS_INSTALL_DIR/<owner>/<repo>`. Prefers `~/git/<repo>` local clones, falls back to a shallow clone for fresh installs. The `name` field is `owner/repo`.
- **`github:release`** — downloads from GitHub releases, matching by OS and arch. Asset matching is case-insensitive and supports all common naming conventions (Go, Rust triples, etc.). Prefers standalone binaries, then tarballs, then zip archives. Compressed single binaries (`.gz`, `.bz2`, `.zst`) are decompressed automatically. On Linux, prefers `gnu` over `musl` assets when both are available. The `name` field is `owner/repo`.
- **`custom`** — entirely managed by a post-install hook. The hook handles platform detection, idempotency, and installation.

**Machine-local deps:** `~/.config/shdeps/deps.local.conf` (untracked, same format) adds machine-local dependencies that aren't in the tracked config. Entries are merged with `deps.conf` at load time.

**Package aliases:** The `aliases` column maps package managers to platform-specific names (e.g., `apt:fd-find`). Use `NONE` to skip a dep on a specific package manager (e.g., `apt:NONE`).

**Filtering:** The optional `filter` column controls which platforms and hosts a dep installs on. Uses `os:` and `host:` prefixes. Prefix with `!` to exclude. Examples: `os:linux,os:macos` (only those), `os:!wsl` (all except WSL), `host:nas` (only host named nas). Omit or use `-` for all.

**Post-install hooks:** Defined as individual files in `~/.config/shdeps/hooks.d/<name>.sh` (for `github:*` deps, hooks go in `hooks.d/owner/repo.sh`). Each file can define `post()` (runs after install/update) and `status()` (reports dep status) functions. Hooks run only when their corresponding dep is newly installed or updated.

**Existence checks:** `pkg` deps check `command -v` first, then fall back to querying the package manager directly (`brew list`, `dpkg -s`, etc.) — useful for deps like fonts that install no binary.

## Scripts Reference

Base scripts in `~/.local/bin/`, deployed via `~/.dotfiles`. All are on PATH.
Work-specific scripts are documented in `~/.local/share/doc/dot/work-scripts.md`.

### Claude Code Hooks

Hook scripts follow the naming convention `claude-hook-{event}[-{matcher}]`.
Each base script auto-delegates to a `-work` variant if one exists on PATH,
enabling layered composition without changing settings.json.

#### `claude-hook-pre-bash` (PreToolUse, Bash)

Parses stdin JSON from the hook runner, exports `CMD_TRIMMED` (whitespace-
trimmed command), then runs base guards:

- **Blocks**: `rm -rf` on `/`, `~`, `$HOME`, or `..`
- **Warns**: any other `rm -rf` usage

Delegates to `claude-hook-pre-bash-work` if present.

#### `claude-hook-post-bash` (PostToolUse, Bash)

Parses stdin JSON, exports `CMD_TRIMMED`. No base post-actions currently.
Exists as the composition base for `-work` variant delegation.

#### `claude-hook-post-edit` (PostToolUse, Edit|Write)

Parses stdin JSON, exports `FP` (file path). No base post-actions currently.
Exists as the composition base for `-work` variant delegation.

#### `claude-hook-session-start` (SessionStart)

Reports context at session start: uncommitted changes (`git status`) and disk
usage warnings (>90%). Delegates to `-work` variant _before_ running base logic
(since the work variant replaces rather than extends).

#### `claude-hook-session-end` (SessionEnd)

Auto-names Claude Code sessions by extracting user messages from the transcript
and calling `claude -p --model sonnet` in the background via `nohup`. Skips
sessions that already have a custom title. Runs base logic first, then delegates to `-work` variant if present.

### Delegation Pattern

```text
settings.json → claude-hook-{event}
                  ↓
                  run base logic
                  ↓
                  command -v claude-hook-{event}-work
                  ├─ found → exec into it (CMD_TRIMMED/FP already exported)
                  └─ not found → exit 0
```

Work scripts receive `CMD_TRIMMED` or `FP` via exported env vars. They never
parse stdin — the base script already consumed it.

`claude-hook-session-start` is the exception: it checks for the `-work` variant
first and lets that replace the base logic entirely.

## Format / Lint Tooling

Two companion CLIs that Claude Code hooks, git hooks, editors, and shell
invocations all funnel through:

- **`autoformat FILE`** — dispatches to the right formatter for the file
  extension (or shebang, for extensionless files). Always-mutates. Exits 0
  even when the formatter fails (stderr is surfaced; the hook never blocks).
- **`autolint [--fix] FILE`** — dispatches to the right linter. Read-only by
  default; pass `--fix` to apply auto-fixes. Exits non-zero when lint
  findings exist.

Both hard-require `yq` (installed by dotfiles bootstrap). Both treat a
missing tool (eslint, luacheck, rustfmt, …) as a graceful no-op — they
never fail the caller because a language toolchain happens to be absent on
this host.

### Default configs

All global fallback configs live in **`~/.config/autoformat/`**, a single
source of truth shared by both scripts. Overridable per-script via the
`AUTOFORMAT_DIR` / `AUTOLINT_DIR` env vars (both default to this path).

```text
~/.config/autoformat/
├── ruff.toml                 # Python — shared by format + lint
├── shfmt.toml                # Shell format (sh/bash/zsh)
├── stylua.toml               # Lua format
├── clang-format              # C/C++ format
├── rustfmt.toml              # Rust format
├── taplo.toml                # TOML format
├── prettierrc.json           # css/html/js/ts/json/md/yaml format
├── shellcheckrc              # Shell lint
├── luacheckrc                # Lua lint
└── markdownlint-cli2.jsonc   # Markdown lint
```

### Config resolution order

For each file, the scripts:

1. **Detect per-repo config** — walk up from the file's directory looking
   for tool-specific config files (`ruff.toml`, `.prettierrc.*`, etc.) and
   nested configs inside multi-purpose files (`pyproject.toml[tool.ruff]`,
   `package.json[prettier]`, `package.json[markdownlint-cli2]`).
2. **If per-repo config found** — invoke the tool without a `--config`
   flag; let the tool resolve its own config the way it natively does.
3. **If no per-repo config** — pass the global fallback explicitly via the
   tool's `--config` / `--config-path` / `--rcfile` / `-style=file:` flag.

One exception: **taplo** walks from the process `cwd`, not the file path,
so autoformat always passes `--config <path>` explicitly (to the detected
per-repo path if present, else the fallback).

### Supported tools

| File type                   | Formatter        | Linter                                                                          |
| --------------------------- | ---------------- | ------------------------------------------------------------------------------- |
| Python                      | ruff format      | ruff check                                                                      |
| Shell (sh/bash)             | shfmt            | shellcheck                                                                      |
| Zsh                         | shfmt (zsh mode) | `zsh -n`                                                                        |
| Lua                         | stylua           | luacheck                                                                        |
| C/C++                       | clang-format     | —                                                                               |
| Rust                        | rustfmt          | —                                                                               |
| TOML                        | taplo            | —                                                                               |
| JSON/YAML/MD/CSS/HTML/JS/TS | prettier         | markdownlint-cli2 (md), actionlint (GH workflows), eslint (js/ts, project-only) |

Shared code in `~/.local/lib/dot/autofmt.sh`: `_has_config`, `_find_config`
(walk helpers), `_classify_shell` (extensionless dispatch), `_toml_read_keys`
(batched yq reads), `_walk_config_with_key` (nested-key config walks).

### Testing

- `~/.local/bin/autoformat-test` — unit tests for autoformat.
- `~/.local/bin/autolint-test` — unit tests for autolint.
- Both run in CI on every matrix entry (macOS, Ubuntu, Debian, Arch,
  CentOS Stream, Fedora, WSL) via `.github/workflows/test.yml`.
