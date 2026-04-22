# Personal Rules

> **Note:** Work-specific rules live in `~/.claude/rules/work.md` when that file is present. When asked to remember work-specific preferences, add them there — not here. This file is for personal, cross-context, and non-work-specific rules only.

## Dotfiles

Base bare repo at `~/.dotfiles`, plus overlay repos discovered from
`~/.config/dot/overlays.d/*.conf`. See `~/.local/share/doc/dot/dot.md`
for full documentation.

- Use the `dot` alias for base dotfiles. Use `git -C ~/.dotfiles-<name>`
  for overlay repos.
- `dot push/pull/status/diff/fetch` operate on base + all active overlays.
- Use `dot push` to push all repos, not raw `git push`.
- When moving tracked base dotfiles, use `dot git mv` to preserve history.
- Always run `dot` commands from `$HOME`. The bare repo uses `$HOME` as its work tree, so commands like `dot git ls-files`, `dot git add`, and `dot git mv` resolve paths relative to CWD — running from a subdirectory gives wrong or empty results.

## Tools

- `~/git` is the default location for locally cloned git repos. GitHub username: `cgraf78`.
- Use `gh` for all GitHub operations (PRs, issues, releases).
- `ds` creates tmux dev sessions. See the `ds` README.
- For home network host details, read `~/.local/share/doc/dot/home-lab.md` before
  investigating `nas`, `taylor`, `metro`, or `bevo2`.
- When inspecting tmux sessions, prefer non-attached tmux commands like
  `capture-pane`, `list-panes`, and `list-windows`. Avoid attaching a small
  client that would shrink the user's pane size; only attach interactively if
  truly necessary.
- gstack skills live in `~/.gstack`, symlinked into `~/.claude/skills/`.
- Do NOT use the `pingme` skill to send notifications.

## Commit Style

- Title: imperative sentence, backtick code names (e.g., "Fix `ds -l` showing empty window count")
- Body has `Summary` and `Testing` sections (plain text headers, no `##` prefix — `#` inside commit heredocs triggers Claude Code permission warnings)
- Summary uses `- ` bulleted list, lowercase start, hard-wrapped at ~72 columns with 2-space continuation indent
- Testing uses `- ` bulleted list describing what was verified
- Blank line between title, Summary, and Testing sections
- When commit messages contain backticks or other shell-sensitive characters, do not pass them via shell-quoted `git commit -m ...`; write the message to a temporary file or use a single-quoted heredoc and commit with `git commit -F`.
- When fixing an unpushed commit, amend it instead of creating a new commit. Never amend already-pushed commits. ALWAYS check `git log --oneline origin/main..HEAD` (or equivalent) before any amend, fixup, or rebase to confirm the target commit is unpushed. Don't assume the target commit is HEAD — for non-HEAD commits, leave changes unstaged and run `git absorb --and-rebase` to auto-route hunks to the correct commits.

## Workflow

- Don't chain separately-permitted commands with `&&` — use individual Bash calls instead, to avoid unnecessary permission prompts.
- Use `git -C <path>` instead of `cd <path> && git` — avoids compound command permission checks triggered by `cd` + `git` combinations.
- Always verify changes compile and pass tests before presenting as done.
- Before committing in a GitHub repo, check `.github/workflows/` for CI steps and run what can be reproduced locally (linters, tests, type checks). Skip steps that require CI-specific infrastructure (deployment, secrets, matrix OS variants).
- Always update .h and .cpp files consistently when changing interfaces.
- Read and understand existing code before proposing changes. Match existing patterns in the file.
- When uncertain about which architectural layer owns a responsibility, ask before proposing changes.
- Don't over-engineer. Solve what's asked, nothing more.
- When navigating into a directory or repo (whether via cd or any other means), check for `AGENTS.md` in that directory and read it if present.
- For new work, always fetch and base branches from the latest `origin/main`, not a stale local `main` or another feature branch.
- Create new PRs for unrelated or independent changes instead of bundling them into an in-flight PR.
- Write PR descriptions so they also work well as squash-merge commit bodies: lead with a concise summary of what changed and why.
- Keep in-flight PR branches current with the latest `origin/main`; if `origin/main` has moved and I'm touching the branch again, rebase it and update the PR.
- Before saying a PR was updated, verify that the PR is still open; if it was already merged or closed, create a new branch/PR instead of assuming more branch pushes update the old PR.

## Design Principles

- **Single-source shared knowledge** — when two or more places need the same value, decision, or logic, extract it to one authoritative location and have consumers call into it. Don't duplicate constants, resolution logic, or convention knowledge across files.
- **Expose clean interfaces** — provide a function or module API to access shared state rather than forcing callers to reimplement the same steps. Callers should say *what* they want, not *how* to get it.
- **Compose from single-purpose parts** — build higher-level behavior by aggregating small, focused components with clean interfaces. Each piece does one thing well; composition gives flexibility to recombine them differently without rewriting internals.
- **Consolidate after the second use** — the first duplication is fine; when a second consumer appears, refactor to a shared source. Don't preemptively abstract, but don't tolerate three copies.
- **Guard at async boundaries** — any callback that fires after a delay (timers, deferred functions, completion handlers) must re-validate every handle it touches. Resources can disappear between scheduling and execution.
- **Prevent re-entrancy in polled loops** — if a timer or event can fire while a previous invocation is still in flight, use a flag to skip overlapping runs rather than queuing unbounded work.
- **Isolate by separation, not by crippling** — when sandboxing components, prefer running normal code in a separate process or scope over stripping everything and manually re-adding pieces. Only remove what actually causes interference.

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
