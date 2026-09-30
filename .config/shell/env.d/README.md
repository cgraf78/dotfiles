# Base Environment Layer

These ordered shell-neutral fragments load in interactive and non-interactive
shells. Keep this layer limited to inexpensive exports, PATH construction, and
platform detection. Prompts, completions, aliases, and keybindings belong in
`../interactive.d/`.

Export dotfiles-owned values with `_shell_env_set` so non-interactive children
keep caller overrides; see
[Environment Ownership](../README.md#environment-ownership).

`50-core.sh` owns values needed by downstream fragments, including Shdeps and
non-interactive shell bootstrapping. Selected overlays may contribute fragments
before, between, or after the base fragments, choosing prefixes relative to the
base layers they depend on.
