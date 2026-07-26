# Codex Profiles

Each `<name>.d/` directory here renders to `~/.codex/<name>.config.toml`.

Profiles are discovered from directory names, so adding a new profile is just a
matter of adding another family directory with TOML fragments. The `default`
profile name is ignored intentionally because bare `codex` reads
`~/.codex/config.toml` directly.

Each profile directory is a merge-hook family. Direct `*.toml` files aggregate
in lexical order, and an immediate `.replace/` group contributes only its last
matching `*.toml` file.
