# Lua Style

<!-- agent-rule-id: language-lua-style -->
<!-- agent-rule-trigger: Editing Lua -->

- Use module tables (`local M = {}`) for reusable Neovim/config helpers, and
  keep plugin specs mostly declarative by calling into those helpers.
- Keep state local by default. Avoid globals; return tables/functions explicitly
  so module boundaries stay clear.
- Use `snake_case` for local variables and helpers. Keep names short but specific
  enough to show whether a value is a policy, adapter, command, or UI callback.
- Prefer data tables plus small helper functions over long inline imperative
  plugin setup blocks.
- Keep Neovim API calls at setup/adapter boundaries when possible. Shared policy
  should be represented as ordinary Lua tables/functions that tests and adjacent
  editor integrations can reuse.
- Use comments to explain cross-plugin ownership, Checkrun/Sley/LSP boundaries,
  lazy-loading constraints, and other non-obvious editor behavior.
- Respect project-local formatter config. In dotfiles or when no local config
  says otherwise, use 2-space indentation, spaces over tabs, and 100-column
  wrapping.
- Use `_` or `_name` for intentionally unused callback parameters instead of
  leaving ambiguous unused locals.
