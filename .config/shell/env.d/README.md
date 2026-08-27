# Base Environment Layer

These ordered shell-neutral fragments load in interactive and non-interactive
shells. Keep this layer limited to inexpensive exports, PATH construction, and
platform detection. Prompts, completions, aliases, and keybindings belong in
`../interactive.d/`.

`50-core.sh` owns values needed by downstream fragments, including Shdeps and
non-interactive shell bootstrapping. Selected overlays may contribute later
fragments for editor defaults or development environments.
