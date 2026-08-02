# Interactive Shell Layer

`interactive.d/` files load only for interactive Bash and Zsh sessions after
the shared environment layer has run.

## Ordering

- `50-*` and `51-*` define aliases and platform-specific command behavior.
- `52-*` through `57-*` add terminal, SSH, dotfiles, navigation, and mark
  helpers.
- `59-*` and `60-*` own prompt setup.
- `70-integrations.*` loads shell-specific completions, plugins, and
  dependency-owned shell APIs.
- `71-*` accelerates completion definitions after integrations have finalized
  their search path.

Use `.sh` for shell-neutral snippets, `.bash` for Bash-only code, and `.zsh`
for Zsh-only code.

## Startup Cost

Interactive shells are on the hot path. Prefer `_tool_init` from
`54-tool-init.sh` for tool-generated init scripts so slow completions and hooks
are cached under `~/.cache/shell/`. `reloadsh` and `dotu` clear those generated
init files when tool state changes.

The Zsh Git completion cache is keyed to both the Zsh version and the exact
source file identity. If compilation or validation fails, Zsh keeps using the
original completion source. Its validated bytecode survives shell reloads and
prunes obsolete generations and old Zsh versions during successful refreshes.

Dependency-owned shell APIs should load through shdeps helpers rather than by
hard-coded install paths. That keeps local clones, release installs, and future
install layouts behind one lookup path.
