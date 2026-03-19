# Personal Rules

## Dotfiles

Two repos: `~/.dotfiles` (personal, bare) and `~/.dotfiles-work` (work, regular clone). See `~/.local/bin/dot.md` for full documentation.

- Use the `dot` alias for personal dotfiles. Use `git` in `~/.dotfiles-work/` for work dotfiles.
- When moving tracked personal dotfiles, use `dot mv` to preserve history.

Commit description style:
- Title: imperative sentence, backtick code names (e.g., "Fix `ds -l` showing empty window count")
- Body has `## Summary` and `## Testing` sections
- Summary uses `- ` bulleted list, lowercase start, hard-wrapped at ~72 columns with 2-space continuation indent
- Testing uses `- ` bulleted list describing what was verified
- Blank line between title, Summary, and Testing sections

## Dev Session

`~/.local/bin/ds` creates tmux dev sessions with pluggable profiles, connection methods, and share backends. Config lives in `~/.config/ds/`. See `~/.local/bin/ds.md` for full documentation.

## Notifications

- Do NOT use the `pingme` skill to send notifications.

## Repos

- `~/git` is the default location for locally cloned git repos.
- GitHub username: `cgraf78`.
- Use `gh` for all GitHub operations (PRs, issues, releases).

## Workflow

- Don't chain separately-permitted commands with `&&` — use individual Bash calls instead, to avoid unnecessary permission prompts.
- Use single-line `dot commit -m '...'` for dotfiles commits — heredoc-style commits break permission matching.
- Always verify changes compile and pass tests before presenting as done.
- Always update .h and .cpp files consistently when changing interfaces.
- Read and understand existing code before proposing changes. Match existing patterns in the file.
- When uncertain about which architectural layer owns a responsibility, ask before proposing changes.
- Don't over-engineer. Solve what's asked, nothing more.
- For new work, always fetch and base branches from the latest `origin/main`, not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them into an in-flight PR.
- Write PR descriptions so they also work well as squash-merge commit bodies: lead with a concise summary of what changed and why.
- Keep in-flight PR branches current with the latest `origin/main`; if `origin/main` has moved and I'm touching the branch again, rebase it and update the PR.
- Before saying a PR was updated, verify that the PR is still open; if it was already merged or closed, create a new branch/PR instead of assuming more branch pushes update the old PR.

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
- `std::expected` / `folly::Expected` for expected failures, `std::optional` for "not found", exceptions for truly exceptional cases.

## Testing

- Always write tests for new code.
- Analyze edge cases before writing tests — boundary values, missing data, error paths, concurrency, invalid input.
- Dedicated test case per edge case, not bundled into happy-path tests.

## gstack

Repo: `~/.gstack`. Skills symlinked into `~/.claude/skills/`.

Available skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/review`, `/ship`, `/qa`, `/qa-only`, `/design-review`, `/retro`, `/debug`, `/document-release`, `/gstack-upgrade`.
