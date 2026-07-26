# dotfiles

![Tests](https://github.com/cgraf78/dotfiles/actions/workflows/test.yml/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash Version](https://img.shields.io/badge/bash-%3E%3D4.0-blue.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20WSL-lightgrey.svg)](#)

Base dotfiles managed as a bare git repository with `$HOME` as the working
tree, plus optional overlay repos for work, machine-specific, or
project-specific files.

## Quick Start

```bash
curl -sL cgraf78.github.io/d | bash
source ~/.bashrc  # or: source ~/.zshrc
```

macOS requires Bash 4+ (`brew install bash`). The system Bash 3.2 is too old.

## Documentation

See the full guide:
[`~/.local/share/doc/dot/dot.md`](../.local/share/doc/dot/dot.md)
