# Android/Termux CI

## Goal

Run the dotfiles test suite inside the official Termux application on an
Android emulator for every push and pull request. Keep Android separate from
the shared eight-platform shell matrix and leave `cgraf78/actions` unchanged.

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

1. install the minimum bootstrap packages, `git` and `curl`, from Termux;
2. set the copied checkout as `HOME` and put its `.local/bin` first on `PATH`;
3. run `dot update --skip-pull` so the normal Android-aware shdeps policy
   installs the test dependencies;
4. run `dot doctor` as the same bootstrap smoke check used by shell CI; and
5. run `dot-test`.

No repository secrets will be forwarded into the Termux workflow.

## Verification

Extend the core static workflow checks to require an active, immutably pinned
`termux-ci.yml` call in the `termux` job. The assertion must ignore comments
and reject the same call when it is placed under another job.

Use a red/green test cycle by first adding the assertion against the unchanged
workflow, confirming it fails, then adding the job and confirming it passes.
Run `checkrun format`, `checkrun lint`, `actionlint`, and the complete
`dot-test` suite before opening the pull request.

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
