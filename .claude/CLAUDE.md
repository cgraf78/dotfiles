# Personal Rules

## Dotfiles

- On this macOS setup, live terminal shortcut behavior with Karabiner enabled does not always match what the tracked `karabiner.json` appears to remap explicitly. For mac terminal shortcut work, keep the `Ctrl`-prefixed bindings for cross-platform consistency, but also add `Cmd`-prefixed aliases and validate the result with Karabiner enabled because those are often the reliable forms in practice on this machine.

Dotfiles are managed via a bare git repo at `~/.dotfiles` with worktree `$HOME`.
Use the `dot` alias (defined in `~/.bashrc`) instead of `git` for all dotfiles operations:

```bash
dot status
dot add ~/.tmux.conf
dot commit -m "update tmux config"
```

When moving tracked dotfiles, use `dot mv` (not `mv` + `rm --cached` + `add`) to preserve history.

Key dotfiles:
- `~/.bashrc` - shell config, proxy settings, dotfiles alias
- `~/.bash_aliases` - project-specific build/test aliases
- `~/.tmux.conf` - tmux configuration
- `~/.local/bin/ds` - dev session launcher (local and remote tmux sessions)

## Dev Session

`~/.local/bin/ds` creates tmux sessions with configurable profiles:
- `ds` — bare session (default), or `ds -p dev` for chatbot + bash layout
- `ds -n <name>` — named session (e.g., `ds-bare-2`, `ds-dev-myproject`)
- `ds <hostname>` — remote session via SSH/ET, profile per host in `~/.config/ds/hosts.conf`
- `def [name]` — alias for `ds -p bare [-n name]`

## Notifications

- Do NOT use the `pingme` skill to send notifications.

## Workflow

- For new work, always fetch and base branches from the latest `origin/main`, not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them into an in-flight PR.
- Write PR descriptions so they also work well as squash-merge commit bodies: lead with a concise summary of what changed and why.
- Keep in-flight PR branches current with the latest `origin/main`; if `origin/main` has moved and I'm touching the branch again, rebase it and update the PR.
- Before saying a PR was updated, verify that the PR is still open; if it was already merged or closed, create a new branch/PR instead of assuming more branch pushes update the old PR.
- Don't chain separately-permitted commands with `&&` — use individual Bash calls instead, to avoid unnecessary permission prompts.
- Use single-line `dot commit -m '...'` for dotfiles commits — heredoc-style commits break permission matching.
- Always verify changes compile and pass tests before presenting as done.
- Always update .h and .cpp files consistently when changing interfaces.
- Read and understand existing code before proposing changes. Match existing patterns in the file.
- When uncertain about which architectural layer owns a responsibility, ask before proposing changes.
- Don't over-engineer. Solve what's asked, nothing more.

## Code Style

- **Brief function names** — concise verbs, no unnecessary prefixes/suffixes.
- **Comments explain WHY, not WHAT** — comments are valuable for non-obvious performance decisions, hardware behaviors, workarounds, regulatory/compliance requirements, and complex algorithms.
- **Docstrings** for classes, public methods, and non-trivial private methods. Skip simple getters/setters and obvious helpers. Use Doxygen style: `/** */` blocks with `@brief`, `@param`, `@tparam`, `@return`, `@note`. Use `/// @brief` for one-liners.
- **Keep code tidy** - delete dead comments, commented-out code, and debugging leftovers.

## C++

- `std::unique_ptr` for single ownership, `std::shared_ptr` only when truly shared.
- References (`const T&`, `T&`) for non-owning params. `std::span<T>` for contiguous data views. Never raw pointers.
- `std::optional<std::reference_wrapper<T>>` for optional non-owning refs.
- Always brace-initialize variables (`int count{};`). Initialize at declaration.
- `auto` when type is obvious from context, explicit otherwise.
- `constexpr` for compile-time constants, `std::string_view` for read-only strings, `std::optional` over sentinel values.
- `[[nodiscard]]` on getters and functions returning values.
- `std::expected` for expected failures, `std::optional` for "not found", exceptions for truly exceptional cases.

## Testing

- Always write tests for new code.
- Analyze edge cases before writing tests — boundary values, missing data, error paths, concurrency, invalid input.
- Dedicated test case per edge case, not bundled into happy-path tests.
