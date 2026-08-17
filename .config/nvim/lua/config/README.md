# Neovim Config Modules

`lua/config/` holds local Neovim policy and helper modules. These files should
answer dotfiles-specific questions and expose small APIs that plugin specs can
consume.

## Ownership

- Keep plugin declarations and Lazy `opts` tables in `lua/plugins/`.
- Keep reusable editor behavior in a spun-out dependency repo when it has a
  stable public surface, then load it through `shdeps`.
- Keep local glue here when it adapts dependency-owned APIs to this Neovim
  setup, such as `sley-nvim.lua`, `checkrun-nvim.lua`, and
  `nvim-workspace.lua`.
- Keep shared language capability policy in `language-policy.lua`; plugin
  specs should consume that policy instead of retyping filetype lists.
- Keep LSP provider and fallback policy in `mason-policy.lua`; external
  shdeps, mise, and system commands are authoritative, while Mason fills only
  missing editor-local tools on supported hosts. Mason stays disabled on
  Android. `dot doctor` checks the server inventory against enabled language
  servers so drift is visible.

## Loading

LazyVim loads `options.lua`, `autocmds.lua`, and `keymaps.lua` by convention.
Plugin specs under `lua/plugins/` may require focused modules from this
directory when they need shared policy or setup timing.

`dot-runtime.lua` resolves the dotfiles checkout from its own path rather than
from the process `HOME`, so tests and fixture homes can run without confusing
dependency lookup. It loads Shdeps through the provider-owned
`$SHDEPS_LUA_DIR/shdeps/bootstrap.lua` entrypoint (default
`~/.local/lib/shdeps/shdeps/bootstrap.lua`); source, developer, and release
selection belongs to Shdeps rather than this config.

`checkrun-nvim.lua` follows the same boundary: Checkrun owns validation and
materialization of its editor-metadata contract, while the local shim only
selects dotfiles' checked JSON projection and resolves `shdeps:` assets through
`dot-runtime.lua`. Do not copy the contract parser back into this directory.
