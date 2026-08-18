# Dot Test Suites

`dot-test` discovers `*-test` scripts in this directory and runs them with a
bounded parallel worker pool by default.

## Usage

```text
dot-test                  # all tests, parallel
dot-test core bootstrap   # named subset
dot-test agent-hook       # work-specific agent-hook shards
dot-test -j 4             # run up to 4 suites concurrently
dot-test -s               # sequential output
dot-test -v               # verbose output in parallel mode
dot-test -l               # list available tests
```

Parallel full runs preserve discovery order within scheduling groups, with
unmarked `agent-hook-*` suites running after the broad baseline suites. A suite
that has been measured on the full-run critical path may put this exact marker
within its first 20 lines to enter the first worker wave:

```bash
# dot-test-priority: early
```

Use the marker only when end-to-end measurements show a wall-clock benefit;
it is not a general importance label and does not affect sequential or
explicitly filtered runs.

Run `dot-test` from the checkout under test and let the runner detect the source
tree. This works for both the live dotfiles home and linked git worktrees:
`dot-test` exports `HOME`/`DOT_TEST_SOURCE_HOME` for the source checkout and
preserves the caller's home as `DOT_TEST_HOST_HOME` for host-installed tools.
Individual suites should not require a special `HOME=... dot-test` invocation or
invent their own source-home detection. If a suite intentionally launches
host-installed tools, use the helpers in `helpers.sh`; when a path assertion
cares about filesystem identity on macOS, canonicalize the assertion rather than
depending on a particular `/var` versus `/private/var` spelling.

## Suites

- `core-test` owns the dotfiles test runner. Its focused shards retain
  application merge-hook, cron, launcher, doctor-extension, and static-policy
  coverage; generic engine behavior lives in the standalone dot repository.
- `core-update-test` is the one retained end-to-end client integration: a real
  standalone update advances a local client origin and runs a dotfiles-owned
  merge hook.
- `bootstrap-shortcut-test` pipes the local standalone installer through
  `--init` against a local client origin. It never reaches the developer's real
  GitHub account.
- `cutover-preparation-test` and `fleet-transition-test` are temporary rollout
  gates for the tracked phase, private readiness proof, and exact old-client
  transition. Remove them with the frozen rescue after fleet activation is
  observed; they are not permanent client architecture.
- `githook-test` tests dotfiles' Sley checkout selection, activation shims,
  commit-message provider choice, and the special bare-home policy. Sley's own
  commit-hook suite owns readiness, Git sequencer behavior, secret scanning,
  and the Sapling skip-decision matrix.
- `git-shell-workflows-test` tests the dotfiles adapter that supplies local fzf
  and editor policy plus the established short command names. The `git-tools`
  repository owns branch, log, status, stash, worktree, and absorb/rebase
  behavior, including separate bare Git-directory and work-tree layouts.
- `gstack-register-test` tests only dotfiles' provider dependency ordering,
  XDG exclusion policy location, and shdeps/merge-hook activation. The
  gstack-register repository owns generated artifacts, agent adapters, cache,
  migration, collision, and cleanup behavior.
- `agent-rules-test` tests dotfiles-owned rule prose policy, IDs, routing, and
  trusted playbook discovery, including rendering the selected policy through
  the installed provider. `agent-rules-adapter-test` tests dependency and
  resolved-manifest dispatch. Generic parsing, rendering, publication,
  migration, and cleanup tests live in the `agent-rules-sync` repository.
- `agent-hook-work-test` tests work-specific `agentguard` hook extensions.
  Installed base hook smoke checks live in `dot doctor`, and detailed hook
  behavior lives in the `agentguard` repo.
- `shdeps-hooks-test` tests dotfiles-specific shdeps hooks.
- `validate-commit-msg-test` tests dotfiles commit-message policy and its Sley
  Git-hook routing.
- `tmux-test` tests tmux config integration. Termnav owns the protocol encoding
  of the tab-routing helpers that the config activates.
- `wezterm-test` tests WezTerm config integration.
- `agent-yolo-wrappers-test` pins where the agent shell wrappers place their
  skip-approval flags, because each CLI accepts that flag on a different set of
  subcommands.
- `nvim-test` tests Neovim config and thin dependency wiring. Sley owns its
  formatter/linter adapter shapes, while Termnav owns its Neovim event and
  publication lifecycle.
- `lua-test` verifies the Neovim and WezTerm adapters consume Shdeps' stable
  provider-owned Lua bootstrap without a dotfiles discovery layer.
- `workflow-consistency-test` compares the Checkrun/Sley policy projection
  across Checkrun plans, generated VS Code settings, the local VS Code
  extension, and Neovim language policy. Its
  representative language matrix lives in
  `fixtures/common-language-policy.json` so cross-surface expectations stay in
  one place. It also guards production workflow surfaces against direct
  low-level formatter/linter dispatch so those tools stay behind Checkrun or
  explicit Sley verify policy.
- `schema-refresh-workflow-test` keeps the scheduled schema updater on its
  dedicated branch-and-PR path, requires a real protected-check synchronization
  event, and prevents auto-merge from bypassing the normal dotfiles gate.

Prefer suites named for the tool or focused behavior they test. Behavior owned
by a dependency repo should live in that repo's own test suite; this directory
keeps dotfiles config and cross-dependency integration checks.

Installed-environment smoke checks belong in `dot doctor`. In particular,
`shdeps` owns generic dependency bin-link behavior in its own test suite, while
`dot doctor` verifies that important public commands in this dotfiles install
still point at the expected spun-out repos.

CI runs all suites through the shared shell CI workflow configured in
`.github/workflows/test.yml`. `dot-test` uses `gum` for styled output when
available and falls back to plain text in CI or minimal environments.
