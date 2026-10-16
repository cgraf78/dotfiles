# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)

My personal shell, tmux, and terminal environment for Linux, macOS, and WSL:
Bash and Zsh startup, tmux configuration and session tooling, WezTerm,
ripgrep, atuin, and the agent rules I use with coding assistants. It is
managed by [`dot`](https://github.com/cgraf78/dot), which tracks `$HOME`
directly in Git and layers optional overlay repos on top.

This is my configuration, not a framework. Browse and borrow freely. If you
want the same workflow for your own files, start from `dot` and its
[`examples/minimal-dotfiles`](https://github.com/cgraf78/dot/tree/main/examples/minimal-dotfiles).

## Quick Start

```bash
curl -fsSL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

Read this before running it on a machine you care about:

- It installs `dot`, then my config into `$HOME`. Conflicting files are
  backed up under `~/.dot-backup/`.
- It installs a cron job that runs `dot update` every 30 minutes, so the
  machine keeps pulling and applying this repo's `main`.
- It installs my tool set (listed in
  [`.config/shdeps/10-deps.conf`](../.config/shdeps/10-deps.conf)) through
  your system package manager, which may need sudo, and GitHub releases.
- The default `editor` profile adds the
  [dotfiles-nvim](https://github.com/cgraf78/dotfiles-nvim) overlay. Private
  overlays are optional and are skipped when your key cannot read them.
- It clones this repo over SSH. Without a GitHub SSH key, use HTTPS instead:

  ```bash
  curl -fsSL cgraf78.github.io/d |
    DOTFILES_REPOSITORY=https://github.com/cgraf78/dotfiles.git bash
  ```

It needs `curl` and `git`. macOS requires Bash 4+ (`brew install bash`). The
system Bash 3.2 is too old.

## Related repos

- [dot](https://github.com/cgraf78/dot): the dotfiles manager this repo runs
  on.
- [shdeps](https://github.com/cgraf78/shdeps): installs the tools listed in
  `.config/shdeps/`.
- [dotfiles-nvim](https://github.com/cgraf78/dotfiles-nvim): my Neovim layer
  (the default `editor` profile).
- [dotfiles-dev](https://github.com/cgraf78/dotfiles-dev): my development
  layer (Git, toolchains, editors, agent tooling).
- [nvim-workspace](https://github.com/cgraf78/nvim-workspace),
  [termnav](https://github.com/cgraf78/termnav),
  [tmux-tools](https://github.com/cgraf78/tmux-tools),
  [git-tools](https://github.com/cgraf78/git-tools), and
  [agentguard](https://github.com/cgraf78/agentguard): standalone tools
  extracted from these dotfiles.

## Documentation

See the [full guide](../.local/share/doc/dotfiles/dotfiles.md). Licensed
under MIT; see [`.github/LICENSE`](LICENSE).

## For contributors and agents

There is deliberately no root `AGENTS.md` or `CLAUDE.md`: the repo root is
`$HOME`, so either file would apply to every project under it. Read the
dotfiles [operations](../.config/agent-rules/playbooks.d/dotfiles/operations.md),
[testing](../.config/agent-rules/playbooks.d/dotfiles/testing.md), and
[ownership](../.config/agent-rules/playbooks.d/dotfiles/ownership-and-extraction.md)
playbooks and the [test suite guide](../.local/lib/dotfiles/tests/README.md)
instead.
