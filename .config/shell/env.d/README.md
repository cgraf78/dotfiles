# Shell Environment Layer

`env.d/` files load for interactive shells and for non-interactive shells that
source `~/.config/shell/env-noninteractive.sh` through `BASH_ENV` or `.zshenv`.

## Rules

- Keep this layer non-interactive-safe: exports, PATH construction, and cheap
  platform detection are fine; prompts, completions, aliases, and keybindings
  belong in `../interactive.d/`.
- Files are shell-neutral `.sh` snippets. If a setting is Bash- or Zsh-only,
  guard it explicitly.
- Numeric prefixes define order. Base files generally use `50-90`; overlays
  should use `80-` or higher unless they intentionally need to run earlier.
- Avoid expensive commands at shell startup. Put cached or interactive-only
  initialization in `interactive.d/54-tool-init.sh` and the integration files.

`50-core.sh` owns environment values that downstream files may rely on,
including `SHDEPS_CONF_DIR`, editor defaults, and non-interactive shell
bootstrapping.
