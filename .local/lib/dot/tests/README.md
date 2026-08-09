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

- `core-test` and `core-*-test` shard core `dot` coverage. `core-test` is the
  orchestrator: it selects shards, prepares the shared fixture home, sources
  topic modules from [`core/`](core/README.md), and calls their explicit
  `dot_core_test_*` functions. Doctor section modules under `core/doctor/` are
  loaded lazily by the doctor tests that need private `_dr_*` helpers.
  `DOT_CORE_SHARD=all ./core-test` still runs the original monolithic coverage
  shape for audits.
- `bootstrap-test` and `bootstrap-*-test` shard `dotbootstrap` coverage. The
  shards share one source script through `DOT_BOOTSTRAP_SHARD`.
  `bootstrap-shortcut-test` runs the README curl-pipe install command against
  the live `cgraf78.github.io/d` shortcut with local fixture repos so CI covers
  the public first-install entrypoint without requiring private SSH state. If
  the live shortcut URL is unreachable from the current network before the
  script can be fetched, the shard reports `SKIP:` instead of treating network
  reachability as a product failure.
  `DOT_BOOTSTRAP_SHARD=all ./bootstrap-test` still runs the original
  monolithic coverage shape for audits.
- `githook-test` tests dotfiles' Sley hook activation and the special bare-home
  policy through real Git operations. Sley's own commit-hook suite owns the
  reusable Git sequencer and Sapling skip-decision matrix.
- `gstack-register-test` tests only dotfiles' provider dependency ordering,
  XDG exclusion policy location, and shdeps/merge-hook activation. The
  gstack-register repository owns generated artifacts, agent adapters, cache,
  migration, collision, and cleanup behavior.
- `agent-rules-test` tests dotfiles-owned rule prose policy, IDs, routing, and
  trusted playbook discovery. `agent-rules-adapter-test` tests dependency and
  resolved-manifest dispatch. `agent-rules-contract-test` compares the complete
  synthetic runtime artifact contract when an installed provider is available;
  extraction work can set `DOT_TEST_AGENT_RULES_PROVIDER` to an isolated
  provider checkout. Generic parsing, rendering, publication, migration, and
  cleanup tests live in the `agent-rules` repository.
- `agent-hook-work-test` tests work-specific `agentguard` hook extensions.
  Installed base hook smoke checks live in `dot doctor`, and detailed hook
  behavior lives in the `agentguard` repo.
- `shdeps-hooks-test` tests dotfiles-specific shdeps hooks.
- `validate-commit-msg-test` tests commit message policy.
- `tmux-test` tests tmux config integration.
- `wezterm-test` tests WezTerm config integration.
- `agent-yolo-wrappers-test` pins where the agent shell wrappers place their
  skip-approval flags, because each CLI accepts that flag on a different set of
  subcommands.
- `nvim-test` tests Neovim config.
- `lua-test` verifies the Neovim and WezTerm adapters consume Shdeps' stable
  provider-owned Lua bootstrap without a dotfiles discovery layer.
- `workflow-consistency-test` compares the Checkrun/Sley policy projection
  across Checkrun plans, generated VS Code settings, the local VS Code
  extension, Neovim language policy, and Sley hook/human invocation paths. Its
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
