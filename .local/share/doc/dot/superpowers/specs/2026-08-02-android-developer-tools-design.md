# Android Developer Tool Routing Design

## Problem

`dot update` currently sends Watchexec and Trippy through their GitHub
repository routes on Android. Neither repository route produces a runnable
Termux binary: Watchexec is already packaged by Termux, while Trippy is not
available from the supported Android package source. The Android CI job does
not run the normal dotfiles bootstrap, so it misses both routing errors.

Once CI exercises the complete update, the same unsupported-repository failure
also applies to Bottom and Hive Memory. Neither repository exposes the
configured command in an Android-compatible payload, and neither tool is
available from the supported Termux package source.

## Dependency policy

Watchexec will use the native package route on macOS and Android. Its GitHub
route will remain available on supported non-macOS, non-Android systems.

Trippy will continue to use the native package route on macOS and the GitHub
route on supported non-macOS, non-Android systems. It will be disabled on
Android until a supported native package becomes available.

Bottom and Hive Memory will retain their existing routes on supported systems
and be disabled on Android until they publish compatible payloads or enter the
supported Termux package source.

The dependency table will retain its aligned column layout. Android package
selection will use the existing Shdeps platform-filter and package-alias
syntax rather than a hook or installer special case.

## Android CI contract

The Termux job will exercise the user-visible bootstrap path:

1. Install the shared workflow's `base` and `neovim` prerequisite profiles.
2. Enable strict shell failure propagation and run `dot update --skip-pull`
   with the checkout as an isolated `HOME`.
3. Fail immediately if `dot update` returns nonzero.
4. Run the existing Android policy smoke checks.
5. Confirm `watchexec --version` succeeds after the bootstrap.

The isolated `HOME` is required because the shared Termux worker transports
the repository to `$HOME/project`, while the dotfiles launcher deliberately
loads its runtime from `$HOME/.local`. The `base` profile supplies Git and curl
for Shdeps bootstrap; the smoke script will verify the profile-installed
Neovim rather than installing it again.

An interactive fresh Shdeps bootstrap will retain the installer's diagnostics
so failures in those prerequisites, platform selection, or release artifacts
are visible. Quiet and cron updates will keep their existing silent behavior.

The smoke script will not install Watchexec directly. This ensures CI proves
that the checked-in Shdeps policy selected Termux's package manager and that
`dot update` installed a runnable command. Trippy will be asserted absent from
Android dependency resolution rather than installed. Bottom and Hive Memory
will have the same explicit unsupported-Android assertions.

## Testing

Host-side Shdeps tests will cover the macOS, Android, and fallback routing
policy. The real Termux smoke will cover package installation and command
execution through `dot update`. Existing Neovim Android checks will remain in
the same smoke path.

No change affects shell startup or Neovim startup. The only added runtime work
is in Android CI and in Android `dot update`, where Watchexec is intentionally
installed through the native package manager.
