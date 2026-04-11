# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Personal dotfiles managed as a bare git repository with `$HOME` as the working tree.

Two repos:
- **`~/.dotfiles`** — bare repo, personal dotfiles (public)
- **`~/.dotfiles-work`** — regular clone, work dotfiles (private, optional)

Work files are symlinked into `$HOME` by the work repo's bootstrap script. Personal dotfiles use `[ -f ]` guards to source work files only when present.

**macOS note:** Requires Bash 4+ (`brew install bash`). The system Bash (3.2) is too old.

## Quick Start

Personal machine:
```bash
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Work machine (also clones work repo):
```bash
curl -sL cgraf78.github.io/d | bash -s work
source ~/.bashrc  # or: source ~/.zshrc
```

On subsequent runs, `dotbootstrap` with no argument auto-detects `work` mode if `~/.dotfiles-work` exists. The bootstrap script automatically backs up any conflicting files to `~/.dotfiles-backup/<timestamp>/`.

After bootstrap, `dot update` self-installs a cron that keeps the machine updated automatically (see [Auto-update cron](#auto-update-cron)).

## Usage

```bash
dot update          # sync everything: pull repos, merge configs, update deps
dot update --cron   # same, but quiet + skip if worktree is dirty (for cron)
dot pull            # same as update (requires bare repo)
dot fetch           # fetch both repos (without updating working copy)
dot push            # push both repos
dot status          # check status of both repos
dot diff            # diff both repos
dot add <file>      # track a file in personal repo
dot commit -m ""    # commit to personal repo
dot refresh         # fix phantom dirty files from clean/smudge filters
dot cron            # show installed cron entries
```

`update` works on all machines with the bare repo. Installs cron entries from `~/.config/dot/cron` into the user crontab. All other commands also require the bare repo.

Work repo files are managed with plain `git` in `~/.dotfiles-work/`.

## How It Works

- `dot update` syncs everything: pulls repos (if present), merges configs, updates deps
- If a pull updates dot infrastructure (`.config/dot/` or `.local/bin/dot`), the script re-execs itself so the rest of the run uses the new code — no need to run `dot update` twice
- `dot fetch/pull/push/status/diff` operates on both repos (if `~/.dotfiles-work` exists)
- Work bootstrap symlinks files from `~/.dotfiles-work/home/` into `$HOME`
- Files that override personal versions get `--skip-worktree` to prevent phantom dirty status
- No branch sync, no markers — just two independent repos

### Auto-update cron

`dot update` installs cron entries from `~/.config/dot/cron` into the user crontab. By default this runs `dot update --cron` every 30 minutes, keeping all machines up to date automatically after the initial `dotbootstrap`.

The `--cron` flag enables two safety behaviors:
- **Skip if dirty** — if either repo has uncommitted changes, the update is skipped entirely. This prevents stomping on in-progress dotfile editing.
- **Quiet mode** — suppresses all output unless something goes wrong.

Every machine is a peer — no primary/replica roles. All machines pull from git independently.

To change the schedule or add more cron entries, edit `~/.config/dot/cron`. The file is a tracked dotfile — changes propagate to all machines on the next `dot update`. For machine-local entries that shouldn't propagate, use `~/.config/dot/cron.local` (same format, untracked). Lines starting with `#` are comments. `$HOME` is expanded and `PATH` is injected automatically at install time.

Run `dot cron` to see what's currently installed.

### Shell config

`.bashrc` and `.zshrc` are thin loaders that source files from
`~/.config/shell/` in two phases. Files use numeric prefixes for load order
and extensions to indicate shell compatibility: `.sh` (any shell), `.bash`
(bash-specific), `.zsh` (zsh-specific).

```
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

Personal files (50-70) are in the personal repo. Work files (10, 80-90) are symlinked from `~/.dotfiles-work/` by `dot update`.

### VS Code config

Settings and keybindings in `~/.config/dot/vscode/` are merged into VS Code's config dirs by `dot update` and `dot pull`:

```
~/.config/dot/vscode/
├── settings.json             (cross-platform)
├── keybindings.json          (common keybindings, all platforms)
├── keybindings-mac.json      (macOS-specific)
├── keybindings-windows.json  (Windows/WSL-specific)
└── keybindings-linux.json    (Linux-specific)
```

Merge policy: dotfiles win on conflicts, local-only settings/keybindings are preserved, JSONC comments are stripped.

### iTerm2 config (macOS)

Dynamic Profile in `~/.config/dot/iterm2/dotfiles-dyn-profile.json` is copied into iTerm2's DynamicProfiles dir by `dot update` and `dot pull`. Set it as default in Preferences.

### Karabiner config (macOS)

Profiles in `~/.config/dot/karabiner/karabiner.json` are merged into Karabiner's config by `dot update` and `dot pull`. Merge policy: dotfiles profiles replace local profiles with the same name, local-only profiles are preserved.

### WezTerm config

`~/.config/wezterm/wezterm.lua` is the WezTerm config file. Tracked directly. On WSL, `dot update` and `dot pull` copy it to the Windows home so the Windows-native WezTerm picks it up.

## Adding a Work-Only File

Add the file to `~/.dotfiles-work/home/<path>`, commit, and push. The work bootstrap will symlink it on the next `dot pull`.

## Adding a Personal File

```bash
dot add <file> && dot commit -m "add <file>" && dot push
```

## Dependency System

`dot update` installs and upgrades tools defined in `~/.config/dot/deps.conf`. Each line declares a dependency with a name and install method:

```
# name          method    cmd    alt    overrides                repo                dir                 platforms
jq              pkg
bat             pkg       bat    batcat
fd              pkg       fd     fdfind apt:fd-find,dnf:fd-find
ds              git       -      -      -                        cgraf78/ds.git      .local/share/ds
neovim          binary    nvim   -      -                        neovim/neovim
direnv          binary    -      -      -                        direnv/direnv
fonts           custom    -      -      -                        -                   -                   !wsl
```

**Methods:**
- **`pkg`** — system package (`brew`, `apt`, `dnf`, `pacman`). Batches all packages into one install command.
- **`git`** — clones from GitHub (prefers `~/git/<name>` local clones, falls back to release tarballs, then `git clone`).
- **`binary`** — downloads from GitHub releases, matching by OS and arch. Asset matching is case-insensitive and supports all common naming conventions (Go, Rust triples, etc.). Prefers standalone binaries, then tarballs, then zip archives. Compressed single binaries (`.gz`, `.bz2`, `.zst`) are decompressed automatically. On Linux, prefers `gnu` over `musl` assets when both are available. Archives are extracted to `~/.local/share/<name>` with the binary symlinked into PATH.
- **`custom`** — entirely managed by a post-install hook. The hook handles platform detection, idempotency, and installation.

**Machine-local deps:** `~/.config/dot/deps.local.conf` (untracked, same format) adds machine-local dependencies that aren't in the tracked config. Entries are merged with `deps.conf` at load time.

**Package overrides:** The `overrides` column maps package managers to platform-specific names (e.g., `apt:fd-find`). Use `NONE` to skip a dep on a specific package manager (e.g., `apt:NONE`).

**Platform filtering:** The optional `platforms` column controls which platforms a dep installs on. Values: `linux`, `darwin`, `wsl`. Prefix with `!` to exclude. Examples: `linux,darwin` (only those), `!wsl` (all except WSL). Omit or use `-` for all platforms.

**Post-install hooks:** Defined in `~/.config/dot/deps-hooks.sh` as `_post_<name>()` functions (dashes in dep name become underscores). Run after installation when a dep is new or updated.

**Existence checks:** `pkg` deps check `command -v` first, then fall back to querying the package manager directly (`brew list`, `dpkg -s`, etc.) — useful for deps like fonts that install no binary.
