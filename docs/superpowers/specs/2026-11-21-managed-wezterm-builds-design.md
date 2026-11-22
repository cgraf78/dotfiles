# Managed WezTerm builds

Dotfiles selects a reviewed WezTerm build for each supported macOS or Linux
desktop target. Shdeps checks the executable version on update and installs
the selected artifacts by checksum. Headless Linux, CI, and WSL keep their
existing skip behavior.

Record the publisher's URL, version, and checksum in one `wezterm-build.lock`
beside the Shdeps hook. WezTerm overwrites its nightly assets and Arch mirrors
can drop old packages. If the publisher rotates a file, a fresh install or
repair needs a reviewed repin. Dotfiles carries only dependency declarations.

The macOS installer uses a managed, versioned user app and links into the
Shdeps bin directory. The existing system or Homebrew app remains available
during migration. Linux uses an exact distro and architecture match and the
native package manager. Platforms without a reviewed package report the
coverage gap instead of silently substituting another build.
