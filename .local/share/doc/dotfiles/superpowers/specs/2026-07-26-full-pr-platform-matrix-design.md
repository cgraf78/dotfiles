# Full Pull-Request Platform Matrix

## Goal

Run the dotfiles test suite on every platform already provided by the shared
`full` shell CI matrix during pull-request and push validation. Keep the shared
actions repository unchanged and defer Android/Termux coverage to separate
work.

## Design

The dotfiles workflow will pass `matrix-set: full` to the existing SHA-pinned
`cgraf78/actions` reusable `shell-ci.yml` workflow. The shared workflow remains
the single source of truth for platform membership and continues to own runner,
container, prerequisite, and dotfiles-bootstrap behavior.

This changes normal pull-request and push CI from the five-platform `core`
matrix to the eight-platform `full` matrix:

- macOS
- CentOS Stream
- Arch
- Debian
- Ubuntu
- WSL
- Fedora
- Alpine

Scheduled and manually dispatched runs already resolve to `full`; explicitly
selecting it makes all workflow triggers consistent.

## Verification

Add a static workflow-contract assertion to the existing core test suite so a
future edit cannot silently fall back to the reusable workflow's `auto`
selection. Validate the workflow with the repository's normal format, lint,
and full `dot test` commands.

After the pull request emits and passes the three new platform checks, add
their exact GitHub Actions contexts to `main` branch protection:

- `shell / Platforms / WSL`
- `shell / Platforms / Fedora`
- `shell / Platforms / Alpine`

Verify that branch protection requires the selector and all eight platform
jobs before merging.

## Scope Boundary

Do not modify `cgraf78/actions`, dependency bootstrap behavior, or platform
definitions. Do not add Android/Termux coverage in this change; that platform
uses a separate emulator-backed reusable workflow and will be handled in a
later pull request.
