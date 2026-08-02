# Shell Config

`.bashrc`, `.zshrc`, `.zprofile`, and non-interactive shell entry points are
thin loaders. The ordered files in this directory hold the actual shell policy.

## Layout

```text
.config/shell/
├── env-noninteractive.sh
├── env.d/                  # see env.d/README.md
│   ├── 50-core.sh
│   ├── 55-homebrew.sh
│   ├── 60-tools.sh
│   ├── 70-platform.sh
│   └── 90-path.sh
└── interactive.d/          # see interactive.d/README.md
    ├── 50-aliases.sh
    ├── 51-aliases-{linux,macos,wsl}.sh
    ├── 52-cursor.sh
    ├── 53-wezterm.sh
    ├── 54-tool-init.sh
    ├── 55-ssh.sh
    ├── 56-dot.sh
    ├── 57-fzf-git.sh
    ├── 57-git-worktree.sh
    ├── 57-marks.sh
    ├── 59-prompt.sh
    ├── 60-prompt.bash
    ├── 60-prompt.zsh
    ├── 70-integrations.bash
    ├── 70-integrations.zsh
    └── 71-zsh-completion-cache.zsh
```

## Loading Policy

- `env.d/` loads for interactive and non-interactive shells.
- `interactive.d/` loads only for interactive shells.
- `env-noninteractive.sh` is the shared non-interactive entry point used by
  `BASH_ENV` and non-login, non-interactive zsh.
- Sourceable shell APIs from dependency repos load from the relevant
  `70-integrations.*` file through `54-tool-init.sh` helpers and shdeps;
  `env.d/` stays limited to non-interactive-safe exports.
- Generated tool initialization is cached below an absolute `XDG_CACHE_HOME`,
  falling back to `$HOME/.cache`; cache generation is skipped when neither
  root is available.
- `.sh` files are shell-neutral.
- `.bash` files load only in Bash.
- `.zsh` files load only in Zsh.
- Numeric prefixes define order.

Base files generally use prefixes in the `50-71` range. Overlay files should
use `80-` or higher unless they must run before base setup.

See [`env.d/README.md`](env.d/README.md) and
[`interactive.d/README.md`](interactive.d/README.md) for the editing rules that
are specific to those loader layers.

## Local Files

Prefer overlay files for repeatable machine classes. Use untracked local files
only for one-off machine state, and keep them outside the numbered base policy
unless they intentionally need to participate in the ordered loader.
