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
curl -sL https://raw.githubusercontent.com/cgraf78/dotfiles/main/.local/bin/dotbootstrap | bash -s init
source ~/.bashrc
```

Work machine (also clones work repo):
```bash
curl -sL https://raw.githubusercontent.com/cgraf78/dotfiles/main/.local/bin/dotbootstrap | bash -s init work
source ~/.bashrc
```

On subsequent runs, `dotbootstrap` with no argument auto-detects `work` mode if `~/.dotfiles-work` exists. The bootstrap script automatically backs up any conflicting files to `~/.dotfiles-backup/<timestamp>/`.

On dotsync-managed machines (no bare repo), `dotbootstrap` is not needed — use `dot update` directly.

## Usage

```bash
dot update        # sync everything: pull repos, merge configs, update deps
dot pull          # same as update (requires bare repo)
dot fetch         # fetch both repos (without updating working copy)
dot push          # push both repos
dot status        # check status of both repos
dot diff          # diff both repos
dot add <file>    # track a file in personal repo
dot commit -m ""  # commit to personal repo
dot refresh       # fix phantom dirty files from clean/smudge filters
```

`update` works on all machines including dotsync-managed ones without git repos. All other commands require the personal bare repo.

Work repo files are managed with plain `git` in `~/.dotfiles-work/`.

## How It Works

- `dot update` syncs everything: pulls repos (if present), merges configs, updates deps
- `dot fetch/pull/push/status/diff` operates on both repos (if `~/.dotfiles-work` exists)
- Work bootstrap symlinks files from `~/.dotfiles-work/home/` into `$HOME`
- Files that override personal versions get `--skip-worktree` to prevent phantom dirty status
- No branch sync, no markers — just two independent repos

### Shell config

`.bashrc` is the entry point for all shell config. Platform-specific sections (macOS, Linux/WSL/MINGW) are inline, guarded by `uname` checks. Sourced files:

```
.bashrc
├── .bashrc_work        (work-only — sourced first, symlinked from work repo if present)
├── .bashrc_local       (machine-local, not tracked)
└── .bashrc_local_work  (machine-local work-only, not tracked)
```

`.bash_aliases` contains all aliases, including platform-specific (macOS, Linux/WSL/MINGW), inline with `uname` guards. Sourced files:

```
.bash_aliases
└── .bash_aliases_work    (work-only — symlinked from work repo if present)
```

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

## Additional Tools

### [`ds`](https://github.com/cgraf78/ds) — Dev Session Launcher

Creates tmux sessions locally or on remote hosts with configurable profiles and per-host defaults. Installed to `~/.local/share/ds` by `dotbootstrap`; updated by `dot update`.

### [`dotsync`](https://github.com/cgraf78/dotsync) — Cross-Machine Dotfile Sync

Keeps your shell environment (dotfiles + config) consistent across multiple machines via rsync + SSH. Automates pushing settings updates to all your hosts so they stay in sync. Installed to `~/.local/share/dotsync` by `dotbootstrap`; updated by `dot update`.

### [`vimrc`](https://github.com/cgraf78/vimrc) — Vim Config

Vim runtime and plugin configuration. Installed to `~/.vim_runtime` by `dotbootstrap`; updated by `dot update`.

### [`gstack`](https://github.com/garrytan/gstack) — Claude Code Skills

A collection of Claude Code skills (slash commands) for engineering workflows: code review, shipping, QA, retros, design consultation, and more. Installed to `~/.gstack` by `dotbootstrap`; updated by `dot update`. Skills are symlinked into `~/.claude/skills/`.
