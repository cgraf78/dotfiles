# Base Shdeps Configuration

`dot update` uses [Shdeps](https://github.com/cgraf78/shdeps) to install the
always-active command-line substrate. Numbered `.conf` files aggregate in
lexical order with declarations contributed by selected overlays.

Base declarations cover shell support, Dot itself, terminal/session tools,
search/navigation utilities, archives, system update helpers, diagnostics, and
`agent-rules-sync`. Git is a prerequisite that must already be installed (as
is Homebrew on macOS), so base does not declare it. Editor dependencies are
owned by `dotfiles-nvim`; development toolchains and workflows are owned by
`dotfiles-dev`.

Declaration rows use:

```text
name  method  [command]  [aliases]  [filter]
```

Methods are `pkg`, `github`, `github:repo`, `github:release`, `cargo`, `go`,
`uv`, `npm`, and `custom`. Package aliases may be manager-qualified, and
optional filters may constrain a row by operating system, package manager, or
hostname. Use `NONE` to suppress a package on a specific manager.

Custom or augmented dependencies place their lifecycle code in
[`hooks.d/`](hooks.d/README.md). Machine-only dependency declarations may use
an ignored local `.conf` file.
