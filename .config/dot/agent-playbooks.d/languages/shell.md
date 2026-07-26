# Shell Style

<!-- agent-rule-id: language-shell-style -->
<!-- agent-rule-trigger: Editing shell -->

- Use Bash for new non-trivial standalone scripts and Bash-only sourceable
  libraries. Preserve zsh, POSIX, and shared-shell runtime contracts; do not add
  Bash-only features such as `${BASH_SOURCE[0]}` or arrays unless the file is
  already Bash-only.
- Add `# shellcheck shell=bash` when a Bash file's extension or shebang is not
  enough for tools to infer the shell.
- Prefer `set -u` or scoped strictness for public entry points. Do not blindly
  add `set -e` to sourced libraries, hooks, or dispatchers where callers need
  deliberate return-code handling.
- Sourced libraries must return errors instead of calling `exit`, and must not
  leak shell options, `shopt` changes, traps, `IFS`, or exported globals into the
  caller. Scope or restore state when a helper needs temporary shell settings.
- In Bash-only code, resolve sibling files from `${BASH_SOURCE[0]}` or a
  documented hook/runtime root. Do not depend on the caller's current working
  directory unless the CLI contract says cwd is the input.
- In Bash-only code, use `local` variables inside functions, arrays for argument
  lists, and explicit return-code capture when multiple commands contribute to
  one result.
- Quote expansions by default. When optional Bash arrays are passed through under
  `set -u`, use `${array[@]+"${array[@]}"}` so unset arrays do not collapse empty
  arguments or change word splitting.
- Keep public functions thin when shell is used as an adapter over reusable
  helpers. Shared policy should live in the narrowest sourceable library rather
  than being copied across hooks, CLIs, and tests.
- Comments should explain shell-specific constraints: sourced-library behavior,
  hook latency, platform quirks, temp-file/durability choices, and why a failure
  is advisory or fatal.
- Respect project-local formatter and linter config. In dotfiles or when no
  local config says otherwise, use 2-space indentation, indented switch cases,
  tidy conditionals, and no dead debug leftovers.
