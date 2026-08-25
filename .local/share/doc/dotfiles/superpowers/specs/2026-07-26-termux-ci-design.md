# Android/Termux CI

## Goal

Run a dotfiles policy smoke check inside the official Termux
application on an Android emulator for every push and pull request. Keep
Android separate from the shared eight-platform shell matrix and leave
`cgraf78/actions` unchanged.

## Design

Add a `termux` job to `.github/workflows/test.yml` beside the existing `shell`
job. The new job will call the existing SHA-pinned public reusable workflow:

```yaml
cgraf78/actions/.github/workflows/termux-ci.yml@feeba8dcb271bd206ae55cd735e53577ffa08877
```

The reusable workflow owns the emulator, official Termux APK, sandbox
transport, and Android runtime boundary. The dotfiles caller owns only the
command executed after its checkout is copied into the Termux home directory.

The caller command will:

1. install the minimum test package, `git`, from Termux;
2. verify the process is actually running under Android and Termux; and
3. validate Android package mappings and unsupported-platform exclusions in
   the dotfiles dependency policy.

No repository secrets will be forwarded into the Termux workflow.

The complete `dot test` suite remains on the eight host platforms. Its
fixtures intentionally model Linux/macOS filesystem layouts, interpreters,
and host tools, so running it wholesale in an Android application sandbox
would report fixture incompatibility rather than dotfiles runtime health.

## Verification

Extend the core static workflow checks to require an active, immutably pinned
`termux-ci.yml` call and the Android policy smoke command in the `termux` job.
The assertions must ignore comments and reject the same calls when they are
placed under another job.

Use a red/green test cycle by first adding the assertion against the unchanged
workflow, confirming it fails, then adding the job and confirming it passes.
Run `checkrun format`, `checkrun lint`, `actionlint`, and the complete
`dot test` suite before opening the pull request.

After GitHub emits the nested Android job's exact check context and the run is
green, add that context to strict `main` branch protection. Re-read protection
to verify the selector, eight shell platforms, and Android check are all
required before merging.

## Scope Boundary

Do not add Android to the `full` platform matrix, modify `cgraf78/actions`,
cross-build release artifacts, forward credentials, or change dotfiles
dependency policy unless the real Termux run exposes a concrete compatibility
defect. Any such defect will be fixed narrowly and covered by its own failing
test in this pull request.
