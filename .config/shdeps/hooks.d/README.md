# Base Shdeps Hooks

Hooks in this directory implement base-specific dependency behavior that cannot
be expressed by a normal Shdeps declaration. A hook may define `exists`,
`version`, `install`, `post`, or `uninstall` according to the Shdeps API.

Keep hooks idempotent and portable across Linux, macOS, WSL, and Android. A
managed install must verify downloaded content before publication, replace its
payload atomically, and never overwrite a user-owned public command.

The base repository owns hooks for Dot, terminal/navigation tools, fonts,
clipboard support, shell support, and the pinned tmux build. Neovim hooks belong
to `dotfiles-nvim`; development-language and formatter hooks belong to
`dotfiles-dev`.
