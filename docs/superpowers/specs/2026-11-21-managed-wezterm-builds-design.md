# Managed WezTerm builds

Dotfiles selects a reviewed WezTerm build for each supported macOS or Linux
desktop target. Shdeps checks the executable version on update and installs
the selected artifacts by checksum. Headless Linux, CI, and WSL keep their
existing skip behavior.

Record the snapshot URL, version, and checksum in one `wezterm-build.lock`
beside the Shdeps hook. WezTerm overwrites its nightly assets and Arch mirrors
can drop old packages, so the dedicated `cgraf78/wezterm-builds` repository
keeps each reviewed set under its own release tag. Dotfiles carries only the
generated dependency declaration. The original bytes, signatures, and
publisher information stay with each snapshot.

The macOS installer uses a managed, versioned user app and links into the
Shdeps bin directory. The existing system or Homebrew app remains available
during migration. Linux uses an exact distro and architecture match and the
native package manager. Platforms without a reviewed package report the
coverage gap instead of silently substituting another build.
