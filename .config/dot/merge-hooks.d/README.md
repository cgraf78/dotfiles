# Merge Hooks

`dot update` runs merge hooks declared from this directory to turn tracked
source layers into generated config files. Declarative hook inputs live here;
executable hook implementations live under
`~/.local/lib/dot/core/merge-hooks/`.

## Conventions

- merge-hook instance names are unprefixed and must match their executable
  script name, e.g. `claude/` pairs with
  `~/.local/lib/dot/core/merge-hooks/claude.sh`
- executable hook scripts drive merge execution; config directories are
  optional inputs consumed by those scripts
- config directories that exist should have a `README.md`, even when they have
  no other declarative config
- private helper scripts may live beside their hook implementation when only
  that hook uses them
- merge source files use the app's native format when possible
- numeric prefixes belong inside ordered source families, not on top-level hook
  instances

Many source collections use a shared family layout owned by dot core:

- direct files in `<family>.d/` aggregate in lexical order
- an immediate `<name>.replace/` directory contributes only its last lexical
  file, making that directory a mutually-exclusive group
- the selected replace file is sorted back into the stream by its relative path

Use numeric prefixes on both direct files and `.replace` directories to express
ordering. Family names are just consumer-chosen directories; the shared policy
does not assign meaning to words like personal, work, or environment.

Use subdirectories inside the hook instance when a target owns multiple source
families or private helpers. For example, VS Code keeps `settings.d`,
`keybindings/`, extension manifests, and helper code under `vscode/`, and
Codex keeps config layers, profile overlays, and merge implementation code under
`codex/`. Single-family targets can stay directly under their hook instance
directory when extra nesting would not make the layout clearer.

The merge runner discovers readable scripts from
`~/.local/lib/dot/core/merge-hooks/` in lexical order, then runs independent
hooks in parallel while preserving explicit serial barriers for singleton
external state. A hook should become serial only when the implementation can
name the specific shared-state hazard; currently only the cron hook is serial
because it read-modify-writes the user crontab and installs it as one complete
replacement. Non-shell helper files and declarative config in this directory are
inert unless a hook explicitly calls them.

A failed hook is advisory to the overall update: the runner prints its log,
marks the Configs stage with a warning, and continues other hooks, while
`dot update` still exits successfully. Unattended monitoring that needs to
escalate config failures must inspect the warning output or captured log rather
than relying only on the process exit status.

Shared mechanics live in `~/.local/lib/dot/core/merge-hooks.sh`: source-file
lookup, portable home-placeholder expansion, parser-tool probes,
sibling-temp writes, and the generic JSON layer merge used by simple config
hooks. Product policy should live in declarative source files under this
directory whenever practical; hook implementations should interpret that config
and own only target-specific apply logic.

The Codex hook delegates its larger TOML/profile/trust workflow to private
helpers in [`codex/`](codex/README.md). That keeps the compatibility path
for older Codex versions covered without implying the code is a reusable dot
runtime API.

## Configs

| App or target | Source files | Output |
| --- | --- | --- |
| VS Code | `vscode/settings.d/`, `vscode/keybindings/`, `vscode/extensions.d/`, `vscode/variants.d/`, `vscode/local-extensions.d/` | VS Code config dirs |
| iTerm2 | `iterm2/profiles.d/*.json`, `iterm2/defaults.d/*.tsv` | iTerm2 DynamicProfiles and global defaults |
| Karabiner | `karabiner/profiles.d/*.json` | Karabiner config |
| Claude Code | AgentGuard `claude/hooks.json`, then `claude/settings.d/` | `~/.claude/settings.json` |
| Codex CLI | AgentGuard `codex/hooks.toml`, then `codex/config.d/` and `codex/profiles/<name>.d/` | `~/.codex/config.toml` |
| OpenCode | AgentGuard `opencode/agentguard.js` | `~/.config/opencode/plugins/dotfiles-agentguard.js` |
| Gemini CLI | AgentGuard `gemini/hooks.json`, then `gemini/settings.d/` | `~/.gemini/settings.json` |
| Muse Code | AgentGuard `muse/hooks.json`, then `muse/settings.d/` | `~/.config/muse/settings.json` |
| Agent rules | `agent-rules/rules.d/*.md`, trusted `agent-playbooks.d/**/*.md`, `agent-rules/targets.d/*.txt` | private resolved manifest consumed by the `agent-rules` provider |
| Git | tracked XDG config | one portable include in `~/.gitconfig` when needed |
| GitHub CLI | `gh/config.d/*.yml` | `~/.config/gh/config.yml` |
| Neovim | `nvim/` | Lazy-managed plugins updated headlessly when Neovim is idle |
| SSH | `ssh/config.d/*.ssh_config` plus overlay `.ssh` files | `~/.ssh/config` |
| tmux | tracked `~/.config/tmux/tmux.conf` | running default tmux server |
| Git ignore | `ignore/ignore.d/` | global gitignore |
| WezTerm | tracked WezTerm config | copied to Windows home on WSL |
| Cron | `cron/cron.d/`, `cron/path.d/`, and optional `cron.local` | user crontab |
| Sapling | `sapling/hgrc.d/*.ini` | `~/.hgrc` |

JSON and JSONC layers generally preserve local-only settings while allowing the
dotfiles layer to win on conflicts. The TOML Codex merge uses `yq` plus an
embedded serializer so root scalars stay above nested tables.

VS Code variants are declared by files under `vscode/variants.d/`.
Each non-comment row is
`platform<TAB>marker<TAB>extensions_dir<TAB>config_dir<TAB>options`. Use `-`
for `config_dir` when a variant only needs extensions registered, such as a
remote VS Code server profile. Options are comma-separated; `no-sley` skips the
local Sley formatter extension and removes generated Sley formatter settings for
that variant. Checkrun-generated file associations and schema settings still
apply because they are editor policy, not Sley extension registration. Only
`$HOME`, `${HOME}`, `~`, `${APPDATA}`, `${WSL_APPDATA}`, and
`${VSCODE_APPLICATIONS_DIR}` are expanded in paths.

Every active row receives its own extension registration. When multiple rows
share a `config_dir`, settings and keybindings are reconciled once using the
last declaration for that directory; place the intended config options on that
last row. This avoids repeating a complete config merge for editor builds that
share one user profile while keeping their extension inventories independent.

VS Code local extensions are declared by files under
`vscode/local-extensions.d/`. Each non-comment row is
`extension_id<TAB>source_dir<TAB>disabled_by_variant_options`. The third column
is optional and may contain comma-separated variant options. When any option is
present on a variant, the hook removes that local extension from the variant
instead of installing it.

Schema associations for source layers live in
[`../../checkrun`](../../checkrun/README.md). Keep associations there instead of
embedding schema policy in individual hooks.

When adding or modifying JSON, JSONC, YAML, or TOML source layers here, also
check `~/.config/checkrun/associations.json`. Use an official, first-party,
SchemaStore, or dependency-owned schema when one exists; if no proper schema
exists, do not add an invented placeholder schema.

## Merge Details

- VS Code settings and keybindings preserve local-only entries, let dotfiles
  win on conflicts, and strip JSONC comments before writing config. Append-only
  retirement records in the JSONC sources identify exact historical managed
  entries. That lets later source changes and deletions remove generations
  synchronized from another machine without altering generated keybinding
  semantics or mistaking genuine local bindings for dotfiles.
- Karabiner dotfiles profiles from `karabiner/profiles.d` replace local profiles with the same name;
  local-only profiles are preserved.
- Claude, Codex, Gemini, and Muse prepend dependency-owned native AgentGuard
  generations before their local source families. AgentGuard also supplies the
  shared ownership-aware reconciliation filter that replaces its previous
  commands and retires removed events without touching user hooks or mutable
  runtime state. Dotfiles owns only asset resolution, native serialization,
  atomic replacement, and local policy. If either required provider asset is
  missing, the hook reports a failed refresh and preserves the whole live
  target instead of applying a policy-only partial update.
- The agent-rules hook retains dot-specific policy only: it resolves ordered
  `agent-rules/rules.d` fragments, validates trusted playbooks, expands the
  active `agent-rules/targets.d` profile, and atomically writes a private
  manifest under dot's XDG state directory. The standalone `agent-rules`
  dependency validates that manifest and owns generic rendering, publication,
  migration, stale cleanup, and uninstall behavior. Per-agent hooks remain
  responsible for settings and AgentGuard integration, not shared rule prose.
- OpenCode has no declarative command-hook schema, so its merge hook safely
  installs AgentGuard's provider-owned protocol adapter through OpenCode's
  global plugin directory. Dotfiles owns only resolution, managed-target
  protection, atomic replacement, and last-known-good preservation. A missing
  provider is reported as a failed refresh even when an installed copy can be
  preserved.
- SSH config merges tracked family fragments plus overlay `.ssh` host aliases.
- Global ignore patterns are assembled from `ignore/ignore.d` source files.
- The mise hook runs `mise install` for versions declared under
  `~/.config/mise`.

## Cron

The cron hook installs entries from ordered tracked fragments under `cron/cron.d/`
and optional untracked `cron.local`. The default entry runs
`dot update --cron --force` every 30 minutes so dependency refresh caches do not
defer scheduled updates.

Use `cron/cron.d/` for overlay-owned jobs. Direct files are parsed in lexical order,
`.replace` groups contribute their selected winner, and `cron.local` is parsed
last. Each source file starts with a fresh filter state, so a `# filter:`
directive in one fragment cannot leak into the next fragment.

`--cron` is quiet and skips the update entirely when any managed repo has
uncommitted changes.

`$HOME` is expanded in cron entries. `PATH` is built from ordered
`cron/path.d/*.txt` fragments, with missing directories and duplicates skipped,
so cron jobs can use the same dotfiles command paths as an interactive shell
without inheriting a polluted interactive PATH.

Filter directives restrict following entries until the next directive:

```text
# Runs everywhere.
*/30 * * * * dot update --cron --force && shdeps prune -y > /dev/null

# filter: hosts=nas
0 3 * * * $HOME/.local/bin/backup-nas

# filter: hosts=!nas platforms=linux
0 6 * * * $HOME/.local/bin/linux-non-nas-task

# filter: hosts=bevo2 users=root
0 6 * * * $HOME/.local/bin/root-only-task

# filter: *
0 7 * * * $HOME/.local/bin/common-task
```

Each `# filter:` line replaces the previous filter. Entries before any
directive default to all machines. `# filter: *` resets to all machines.

Supported keys are `hosts`, `platforms`, and `users`. When multiple keys are
present, every key must match. Platform values are `linux`, `macos`, and `wsl`;
prefix any value with `!` to exclude it. Values may be comma-separated. Host
matching uses the short hostname, and user matching uses `id -un`.

Filter state resets between each `cron/cron.d` fragment and `cron.local`, so a
directive in one file does not leak into the other.
