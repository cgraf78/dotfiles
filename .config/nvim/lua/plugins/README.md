# Neovim Plugin Specs

`lua/plugins/` contains LazyVim plugin specs. These files declare plugins,
override plugin options, and connect plugin lifecycle to local policy modules
under `lua/config/`.

## Conventions

- Group specs by user-facing area: coding, formatting, linting, Git, UI,
  workspace, and similar domains.
- Keep reusable policy out of plugin specs. Put it in `lua/config/` and call a
  named helper from the spec.
- Prefer dependency-owned adapters through `shdeps` for behavior shared with
  hooks or command-line tools.
- Keep editor-only fallback installers behind `mason-policy.lua`; shdeps,
  mise, and system packages remain authoritative.
- Use late `zz-*` specs only when ordering is the point. For example,
  `zz-mason-policy.lua` wraps final LSP setup after normal language specs have
  registered their servers.

Plugin specs may declare plugin-local Lazy `keys = { ... }` entries. Use
`lua/config/keymaps/` when a keymap domain needs shared helpers, mode-specific
logic, or lifecycle ordering beyond a single plugin.
