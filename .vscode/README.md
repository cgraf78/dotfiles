# HOME VS Code Workspace

This directory contains VS Code settings for the `$HOME` workspace. It is
intentionally narrower than normal repo workspaces because `$HOME` includes
large caches, editor extension installs, and shdeps-managed dependency trees.

## Shell Navigation

`bashIde.globPattern` in `settings.json` mirrors the HOME shell policy in
`~/.config/nvim/lua/config/nvim-workspace.lua`. When shell files move between
dotfiles, shdeps hooks, dot runtime helpers, or shdeps-installed `cgraf78`
repos, update both files together.

Index shdeps-installed bin targets under `~/.local/share/cgraf78/*/bin/*`.
Do not recursively index `~/.local/bin`; that directory is a facade of symlinks
plus unrelated local commands and should only be handled when a file there is
opened directly.

## Lua Navigation

LuaLS refuses `$HOME` as a workspace unless VS Code passes
`--force-accept-workspace`. Keep that flag scoped to this HOME workspace, and
keep `Lua.workspace.ignoreDir` focused on large HOME subtrees that should not be
scanned as part of editor navigation.

After changing these paths, run:

```sh
dot test nvim
dot test vscode-sley
dot test workflow-consistency
```
