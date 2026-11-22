# Managed WezTerm builds implementation plan

**Goal:** Make `dot update` converge managed macOS and Linux WezTerm installs
to the builds selected in dotfiles.

**Architecture:** The custom Shdeps hook reads the target, version, archive
URL, and SHA-256 from one adjacent lockfile. macOS validates and publishes a
versioned user bundle. Linux stages all applicable native packages before
invoking the package manager once. The dedicated snapshot repository retains
the original publisher files under versioned releases and generates the
consumer lock with those permanent URLs.

**Spec:** [Managed WezTerm builds](../specs/2026-11-21-managed-wezterm-builds-design.md)

1. Extend `shdeps-hooks-test` for version drift, fetch verification, package
   selection, and macOS bundle ownership. Confirm the tests fail against the
   old presence-only hook.
2. Replace moving upstream release selection in `wezterm.sh` with the local
   lock. Verify all downloads before changing executable or package state.
3. Fetch and check the real upstream artifacts for the initial target rows.
   Publish and verify the initial release in `cgraf78/wezterm-builds` before
   repinning dotfiles. Document update, launch, and unsupported-platform
   behavior in the WezTerm guide.
4. Run `dot test`, format and lint checks, and an isolated install probe with
   the real macOS archive. Review the changes before opening the pull request.
