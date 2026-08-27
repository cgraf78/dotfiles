# Dotfiles Overlay Profiles and Capability Split Implementation Plan

**Goal:** Make a fresh dotfiles installation select the small `base` profile by
default, while `editor` and `dev` add progressively larger, strictly
overlay-backed environments.

**Architecture:** The public `dotfiles` repository remains the always-active
base substrate and becomes the profile control plane. It defines three additive
profiles that expand only to additional overlay names. The new
`dotfiles-nvim` and `dotfiles-dev` repositories own the corresponding optional
public configuration, dependency declarations, hooks, tests, doctor checks, and
component documentation.
`dotfiles-personal` remains an optional member of `base`. `dotfiles-work` is an
opaque optional member of `dev`; this public plan intentionally contains no
details about its contents. Standalone Dot performs two-phase resolution: it
synchronizes root/base-selected optional personal first, loads eligible selector
records, then resolves and activates the final additional overlays. It exposes
only the resulting overlay manifest to downstream commands. There is no
independent capability flag system.

**Tech Stack:** Bash 4+, Git, standalone Dot, Shdeps, mise, tmux, Neovim/Lazy,
GitHub Actions, and the existing dotfiles shell test harness.

## Changes from Review

- Moved existing-machine selector preparation before profile definitions are
  deployed, so staging cannot silently retire a previously active optional
  overlay.
- Made profile selection precede descriptor parsing and made pre-sync SSH
  companion discovery consume only eligible overlay records.
- Specified overlay-only reservation for profile paths and the exact tracked
  ignore rule for the user-owned selector.
- Added exhaustive, machine-checkable baseline-disposition and final-ownership
  inventories that cover configuration, dependencies, runtime code, tests, doctor checks,
  documentation, CI, and repository metadata.
- Corrected standalone Dot's focused test commands, added controlled-PATH
  fixtures, documented new-repository bootstrapping and empty-profile
  semantics, and added a repeatable footprint measurement script.
- Distinguished doctor states for unselected, ineligible, unavailable, and
  active overlays.
- Strengthened the ownership invariant: a component's install declaration,
  configuration/runtime, focused tests, doctor checks, and component
  documentation stay together under one repository owner.
- Tightened staging so extracted focused tests, component doctor checks, and
  component-only documentation leave the top-level tree as soon as public
  overlay CI owns them; only temporary legacy Nvim/dev config/runtime remains
  for final cutover.
- Restricted each public capability repository's CI to its own focused behavior
  and doctor checks. Inherited-profile preservation and collision checks now
  live only in bounded top-level composition tests.
- Simplified the repository split: the existing public `dotfiles` repository
  remains the always-active base and control plane. There is no
  `dotfiles-core`; only Nvim and dev are extracted to new public overlays.
- Replaced the single local profile scalar with exact user/host selector
  records and safe two-phase resolution, allowing private personal mappings to
  participate without reading non-base overlay configuration early.
- Kept existing public/base agent rule files and required `agent-rules-sync`
  aggregation machinery in `dotfiles`, with their focused tests, doctor checks,
  and docs. Existing personal/work rule ownership remains unchanged.
- Split selector-path reservation so machine-local selectors are forbidden in
  every repository candidate, while tracked definitions/selectors remain
  base-owned and overlay-forbidden.
- Made the new repositories public at GitHub creation only after local bootstrap
  scans/review, with repeated review before every extracted-content push.
- Separated D4 staging checks/baseline from D5 final base absence and footprint
  gates.
- Added the shared-actions lock/consumer-sync contract and an auditable settings
  endpoint manifest to both public overlay skeletons.
- Defined converge, inspect, fetch, and push resolution semantics so inspection
  remains offline and repository commands touch only the existing selected set.
- Replaced the single path TSV with separate exhaustive baseline-disposition and
  final-ownership inventories that represent splits, new files, and duplicate
  relative metadata paths across repositories.
- Added the same-stem descriptor/SSH-companion rename and managed-block
  transition test.
- Scoped capability suite inventory completeness to the installed Dot suite
  root while running repository infrastructure tests exactly once outside it.
- Pinned capability CI to the immutable reviewed D1 standalone Dot revision,
  made selector rollout exhaustive, and added a tracked-root selector example.
- Split execution into an authorized PR-preparation phase and a separately
  authorized landing/rollout phase. PR preparation opens and proves D1-D5
  without merging or changing live selectors.
- Added an immutable coordinated-commit-set harness for unmerged D1-D3 heads,
  test-only `sync=none` integration descriptors, and an explicit D5-on-D4 PR
  stack/retarget contract.
- Froze the exact source `dotfiles` commit behind both ownership inventories and
  every extraction, with mandatory reconciliation if that source revision
  changes.
- Clarified that an empty capability suite inventory is valid only for the
  bootstrap skeleton and recorded the brief public-repository default-settings
  interval before mirrored settings are applied and verified.
- Routed the coordinator's resolved overlay records explicitly across Dot's
  isolated extension-worker boundary; workers no longer rediscover descriptors
  or selectors and authorize extensions only from the passed selected set.
- Defined a collision-free D4/D5 ephemeral descriptor fixture that excludes the
  two tracked public descriptors only in the temporary copy, generates
  canonical `sync=none` replacements for pinned checkouts, and separately
  validates the immutable production descriptors.
- Added a dedicated versioned six-field overlay-context codec shared by the
  coordinator and isolated workers; the installed link-manifest parser remains
  a separate schema.
- Named the overlay lifecycle sets `selected`, `eligible`, and `active`, so
  pre-sync receives eligible pre-availability records while merge/component
  doctor receive only active validated records.
- Bound D5 CI to the exact pull-request base ref and event base SHA in addition
  to the merge-base check.
- Moved the immutable source-dotfiles lock ahead of both capability bootstrap
  commits and bound their canonical license copies, source evidence, CI checks,
  and later reconciliation to that exact commit.
- Split pre-sync into an explicit non-pruning phase-one `prepare` stage and a
  full-family final `reconcile` stage that runs only after final selection and
  descriptor validation succeed.
- Made the stack-locked D1 checkout the sole Dot runtime for every D4/D5 Phase A
  verification group, with per-group HEAD/PATH assertions and no incidental
  host or shared-setup Dot.
- Scoped capability SPDX checks to the owning repository and added bounded
  condition polling for initial GitHub license/settings visibility, with a
  coordinator check after both repositories exist.
- Added an existing-machine `runtime_ready` gate: the landed D1 provider must
  be installed and verified while the root remains pre-D4, independently of
  selector readiness, before D4 can reach that installation.
- Kept tmux in `base` without retaining the development Mise toolset: a
  base-owned custom Shdeps hook installs the reviewed tmux-builds 3.6b assets
  using the exact URLs and checksums from the frozen Mise lock, while Android
  retains its native package path.

## Fixed Decisions

- The only profiles are `base`, `editor`, and `dev`.
- Profiles are additive and may include other profiles.
- `base` is the default when no selector record matches.
- `editor` includes `base`; `dev` includes `editor`.
- Profiles select overlays only. No consumer branches on the profile name.
- Profile selection is persistent configuration, not an environment override.
- Selector records may match user, host, or both; supplied fields all match,
  conflicts fail, and no match defaults to `base`.
- Public root selectors must contain no private inventory; real private
  host/user mappings belong in machine-local untracked config or the existing
  personal overlay.
- Do not add profile-management commands in the initial implementation.
- Only `init` and `update` may clone/pull phase-one personal before final
  selection. Inspection commands resolve from root/local plus an already-present
  validated personal checkout without network access; `fetch` and `push` use
  that existing-state selected set and never clone or pull during resolution.
- Isolated extension workers receive the coordinator's exact eligible or active
  overlay records, as appropriate to the mode, through a validated one-use
  private context. They never rediscover
  descriptors or selectors; an overlay-owned extension must pass both existing
  checkout/origin trust checks and owner membership in that context, while a
  root-owned extension remains bound to the validated root identity.
- Overlay lifecycle terms are precise: `selected` is flattened profile
  membership, `eligible` is a selected descriptor-valid host/platform match
  before checkout availability, and `active` is an eligible record whose source
  has synchronized or otherwise passed source validation. Pre-sync consumes
  eligible records; linking, merge, component doctor, and installed test
  discovery consume active records.
- Pre-sync has a trusted stage supplied by the coordinator. Phase-one
  `prepare` may upsert only supplied eligible companion blocks and cannot prune
  unmentioned managed-family entries. Final `reconcile` may replace the family
  only after selector/profile/selected-descriptor validation succeeds.
- During Phase A, every top-level D4/D5 command that executes Dot uses the exact
  D1 commit in `.github/overlay-profile-stack.lock` from an isolated XDG root.
  Host-installed Dot, latest/release resolution, and incidental
  `setup: dotfiles` runtimes are forbidden.
- Phase B may expose D4 to an existing installation only when its private
  rollout row has both `runtime_ready` proof for the exact landed D1
  commit/release and `selector_ready` proof, or an explicit deployment hold
  prevents that installation from receiving D4.
- The root `dotfiles` repository is always active and is not a selectable
  overlay. `base` selects only the optional personal overlay.
- `dotfiles-personal` is selected by `base` and remains `optional=true`.
- `dotfiles-work` is selected only by `dev` and remains opaque in public code,
  documentation, tests, commits, and pull requests.
- Profile membership does not strengthen an overlay's availability contract.
  A selected `optional=true` private overlay retains today's behavior: a
  missing deploy key, unreachable remote, failed clone, or failed pull is an
  advisory skip with zero overall status, and a later update may activate it
  when access becomes available.
- Git is available in `base` only as bootstrap infrastructure for Dot. Global
  Git configuration and all user-facing Git tooling belong to `dev`.
- The root `dotfiles` repository owns the existing public/base agent rule files
  and the `agent-rules-sync` tooling required to aggregate/synchronize/apply
  those rule fragments, plus their focused tests, doctor checks, and docs.
  Unrelated agent binaries, skills, plugins, hooks, wrappers, and all other
  agent tooling belong to `dotfiles-dev`. Existing personal rule fragments
  remain in `dotfiles-personal`; existing work rule fragments remain in
  `dotfiles-work`. Profiles merely compose those existing owners through the
  aggregation mechanism; this work does not consolidate private rules into the
  public base repository.
- The repository that installs a tool owns its default configuration and merge
  behavior. A selected overlay may add a fragment that references tools supplied
  by that overlay or an inherited lower layer.
- The same owner also owns that component's runtime helpers, dependency and
  installation declarations, focused tests, doctor checks, and component
  documentation. The top-level `dotfiles` repository retains base-focused tests
  and doctor/docs, plus profile/control-plane and cross-overlay composition and
  lifecycle tests.
- Profile changes unlink deselected overlay files but do not automatically
  uninstall native packages or delete cached checkouts. Cleanup remains an
  explicit later concern.
- Do not duplicate private hostnames, topology, policies, or deployment details
  in public repositories or this plan.
- New public overlay repositories use clean independent histories populated only
  from manifest-allowlisted files, mirror the audited `cgraf78/dotfiles`
  repository settings, and pass content/history privacy scans plus fresh-eyes
  review before first push, before every later push containing extracted
  content, and at final acceptance.
- The currently authorized work stops with open, green, dependency-blocked PRs.
  It does not merge or land any PR, publish a Dot release, change a live
  selector, or roll the profile system out to an existing installation. Those
  actions require separate Phase B authorization.

## Target Configuration

Tracked profile definitions in the top-level `dotfiles` repository:

```text
.config/dot/profiles.d/base.conf
.config/dot/profiles.d/editor.conf
.config/dot/profiles.d/dev.conf
```

```text
# base.conf
version=1
overlays=personal
```

```text
# editor.conf
version=1
profiles=base
overlays=nvim
```

```text
# dev.conf
version=1
profiles=editor
overlays=dev,work
```

Profile selection uses exact-match records. Public/root records, if any, live
under:

```text
.config/dot/profile-selectors.d/*.conf
```

Machine-local records are untracked:

```text
~/.config/dot/profile-selectors.local.d/*.conf
```

The optional personal overlay may keep existing private host/user mappings in
repository-only files outside `home/`:

```text
dot/profile-selectors.d/*.conf
```

Every selector record has this schema:

```text
version=1
user=example-user       # optional
host=example-host       # optional
profile=editor
```

At least one of `user` or `host` is required. All supplied fields must match.
User names match `id -un` exactly and case-sensitively. Host names compare the
validated selector value with `hostname -s` after ASCII lowercase
normalization and removal of a trailing dot. Combined user-and-host selectors
override matching user-only or host-only defaults. Multiple matching records at
the winning specificity are allowed only when they select the same profile;
conflicting profiles at that specificity are a hard configuration error before
final overlay mutation. No match selects `base`. This supports different users
selecting different profiles on the same host, plus user-wide defaults with
per-host exceptions, without environment overrides or management commands.

Target overlay descriptors:

```text
.config/dot/overlays.d/20-nvim.conf
.config/dot/overlays.d/30-dev.conf
.config/dot/overlays.d/80-personal.conf
.config/dot/overlays.d/90-work.conf
```

The root base is always the lowest precedence layer. Descriptor order is the
sole precedence order among additional overlays. Profile declaration and
profile-inclusion order affect membership only.

Resolution is deliberately two-phase:

1. activate the root/base substrate and attempt only the overlays named by
   `base`, preserving optional skips;
2. load selector records from root, local state, and successfully active
   personal checkout(s);
3. resolve `base`/`editor`/`dev`, then parse and synchronize only the additional
   overlays selected by that flattened profile.

If personal has no usable checkout, its selector records are unavailable too;
local or root matches still apply, otherwise the result is `base`. A validated
existing checkout retained after an optional pull failure may still provide its
current records. No non-base or unselected descriptor contents or SSH
companions are read before final selection.

Command lifecycle modes are explicit:

- `init`/`update` use **converge mode**: synchronize phase-one personal, resolve
  selectors, then synchronize final selected additions;
- `status`/`diff`/`doctor`/`test` use **inspect mode**: read root/local selectors
  and an already-present validated personal checkout only, with no clone, pull,
  fetch, push, or other network access;
- `fetch` uses **fetch mode**: perform the same existing-state resolution, then
  fetch the root plus selected repositories that already exist; never clone an
  absent optional checkout and never update a worktree;
- `push` uses existing-state resolution with no preparatory clone/pull/fetch,
  then pushes only the root plus selected existing Git repositories.

Maintain three explicitly named overlay sets:

- **selected:** logical names produced by the flattened profile before
  descriptor contents, host/platform predicates, or availability;
- **eligible:** selected records whose descriptors are valid and whose
  host/platform predicates match, before checkout/transport availability;
- **active:** eligible records whose Git checkout synchronized and validated,
  or whose `sync=none` source passed local-source validation.

A selected-invalid descriptor is a configuration failure. A
selected-ineligible descriptor is represented in lifecycle state but is not
eligible and exposes no SSH companion. A selected optional unavailable overlay
remains eligible for pre-sync but is not active for linking or component
extensions.

Phase-one pre-sync is explicitly `stage=prepare`: it can upsert supplied
eligible companion state but preserves every unmentioned managed-family entry
because final selection is not known. After selectors, profiles, and all
selected descriptors validate, final pre-sync is `stage=reconcile`: it replaces
the family from final eligible records and may remove deselected/ineligible
entries. A failed final resolution never performs reconcile.

For every pre-sync, merge, or doctor dispatch, the coordinator serializes the
appropriate eligible or active records into a one-use private context. The
isolated worker validates and consumes that context; it never enumerates
descriptors or resolves profiles independently.

## Target Ownership

| Repository | Owns |
| --- | --- |
| `dotfiles` | always-active base shell/runtime/tooling/configuration, raw Git bootstrap, existing public/base agent rule files and required `agent-rules-sync` machinery, base focused tests/doctor/docs, overlay descriptors, profile definitions, ownership inventories, profile/control-plane tests, and bounded cross-overlay integration tests |
| `dotfiles-nvim` | Neovim installation declarations and configuration, editor-oriented plugins, editor shell/tmux/ripgrep fragments, runtime hooks, focused tests, doctor checks, and component documentation |
| `dotfiles-dev` | global Git configuration, advanced Git tooling, language toolchains, formatters/linters, agent binaries/skills/plugins/hooks/wrappers and other tooling, development Nvim plugins, installation declarations, runtime hooks, focused tests, doctor checks, and component documentation |
| `dotfiles-personal` | existing lightweight personal overlay, Grafhome CA client policy, private connection policy, and personal fragments; no split unless tests identify a concrete active dependency defect |
| `dotfiles-work` | opaque optional overlay selected only by `dev`; implementation details remain private and out of this plan |

## Test, Doctor, and CI Ownership

Public component ownership is source-owned and non-duplicative:

- `dotfiles` owns and runs base-focused tests and doctor checks in addition to
  profile/control-plane and bounded composition coverage;
- each of `dotfiles-nvim` and `dotfiles-dev` owns the focused test scripts and
  doctor checks for the optional components it installs;
- each public capability repository has a literal, repo-owned
  `.github/dot-test-suites.txt` inventory and a `test/run` wrapper that validates
  the inventory, selects only those suites, and invokes the existing shared
  public dotfiles/shell CI machinery;
- the top-level `dotfiles` repository's corresponding inventory contains
  base-owned focused suites plus profile parsing/configuration, overlay
  selection/composition, ownership, migration, and bounded cross-overlay
  fixture suites;
- the ownership test rejects a public suite or doctor check listed by more than
  one public repository, and rejects a component-focused suite/check whose owner
  differs from the component's install/config/runtime owner;
- during staging, only legacy Nvim/dev config/runtime may remain in the
  top-level tree for safe cutover. Extracted focused tests, component doctor
  checks, and component-only docs move completely to their public overlay owner
  in staging, before profile-sensitive installed discovery is enabled;
- each capability repository tests only behavior it owns. It uses minimal
  prerequisite fixtures for inherited interfaces and does not assemble or run
  lower-profile behavioral suites;
- an installed operator `dot test` with no filter may still aggregate tests
  contributed by the current active-overlay manifest. Discovery tracks
  source provenance and rejects duplicate suite names rather than silently
  running two copies;
- private overlays remain special: their existing repository policy is
  unchanged, public dotfiles CI does not execute or compensate for their private
  suites, and this plan does not describe their contents.

Doctor follows the same rule. Standalone/top-level Dot reports profile and
overlay lifecycle states. Active overlays contribute their own component health
checks. An inactive or unavailable overlay contributes no component check.

## Authorization Boundary and Repository/PR Sequence

### Phase A: PR preparation — authorized now

Phase A may create the reviewed public bootstrap repositories, implement and
open D1-D5, open D6/D7 only if a concrete compatibility defect requires one,
and monitor all available checks to green. It must not merge or land a PR,
publish a standalone Dot release, edit a live machine selector, update a live
installation, or perform fleet rollout. Green in Phase A means the complete
prospective stack is reproducible from immutable reviewed commit IDs even
though every feature PR remains unmerged.

| Order | PR/work | Repository | Immutable dependency contract |
| --- | --- | --- | --- |
| A1 | D1 | `cgraf78/dot` | publish the PR head SHA; no release or merge |
| A2 | Source freeze | `cgraf78/dotfiles` on the published D4 branch | record the exact source SHA and canonical `.github/LICENSE` evidence before either capability bootstrap commit exists |
| A3 | Bootstrap | create public `dotfiles-nvim` and `dotfiles-dev` skeleton `main` branches | copy license/source evidence from the exact A2 SHA only |
| A4 | D4 inventory prefix | `cgraf78/dotfiles` on the published D4 branch | adopt the A2 source lock unchanged and publish reviewed inventory rows before a dependent extracted-content push |
| A5 | D2 and D3 | capability repositories | pin exact D1 PR head in `.github/dot.lock`; extract only from the frozen source SHA; may proceed in parallel |
| A6 | D4 | `cgraf78/dotfiles`, base `main` | pin exact D1/D2/D3 heads; every Dot check uses locked D1; CI builds the canonical ephemeral candidate |
| A7 | D6/D7, only if needed | existing private repositories | concrete compatibility fix only; never expose private details |
| A8 | D5 | `cgraf78/dotfiles`, base the published D4 branch | same pinned commit set and sole locked-D1 runtime; mark dependency on D4 and block merge |

D4 is based on `main`. D5 is a true stacked PR whose GitHub base is the
published D4 feature branch, so its diff contains only final cutover work. Add
an explicit dependency label/check and PR text stating that D4 must land first.
After D4 eventually merges in Phase B, retarget/rebase D5 onto `main`, refresh
all pinned revisions, and rerun the full stack before it can be merged. A green
Phase A D4 or D5 is still dependency-blocked and not authorized to merge.

The D4/D5 integration jobs must check out exact D1, D2, and D3 PR head commits,
never a branch name and never the capability skeleton `main`. In an isolated
ephemeral copy of the D4/D5 candidate, they exclude the tracked Nvim/dev
production descriptors and generate test-only `sync=none` descriptors at those
same canonical filenames, pointing to the exact checkouts. The immutable source
checkout is never mutated. Production descriptors remain ordinary descriptors
for the eventual public `main` branches and are separately parsed and hashed.
The fixture fails closed on duplicate logical names, a visible production
descriptor, network access, or a pinned commit/repository mismatch.

### Phase B: landing and rollout — deferred

Phase B requires a new explicit authorization. It lands and releases D1,
repins D2/D3 to the final immutable D1 commit, lands D2/D3, performs final-main
content/history/license/settings acceptance, completes the exhaustive private
rollout ledger, installs/verifies landed D1 on pre-D4 roots, prepares live
selectors, lands D4, retargets and lands D5, and performs fleet convergence and
verification. Tasks marked Phase B are
planning for that later authorization, not work to perform in Phase A.

Every repository change starts from the recorded base revision in its own
isolated worktree. Keep independent repositories and the two top-level
dotfiles phases in separate PRs. Use each repository's `Summary`/`Testing`
message format. Never silently rebase a split PR onto a newer `origin/main`;
follow the source-revision reconciliation procedure in Task 5.

---

## Task 1: Add strict profile parsing to standalone Dot

**Repository:** `cgraf78/dot`

**Files:**

- Create: `lib/dot/profiles.sh`
- Create: `tests/profiles-test`
- Create: `examples/profile-dotfiles/README.md`
- Create example profile, descriptor, and selector fixtures below
  `examples/profile-dotfiles/`
- Modify: `tests/examples-test`
- Modify: `lib/dot/runtime.sh`
- Modify: `tests/run`

### 1.1 Write failing parser fixtures

Add fixtures to `tests/profiles-test` for:

- no `profiles.d` directory: retain legacy all-descriptor behavior for generic
  Dot clients;
- profiles present and no matching selector: select `base`;
- user-only, host-only, and combined user+host exact matches;
- two users on one host selecting different profiles;
- a combined user-and-host match overriding disagreeing user-only and host-only
  defaults regardless of selector source or file order;
- duplicate winning matches that agree on one profile;
- conflicting matching records at the winning specificity as a hard error;
- host lowercase/trailing-dot normalization and case-sensitive user matching;
- unavailable personal selector source with local match and with no match;
- explicit `base`, `editor`, and `dev` results;
- root `dotfiles` is never part of the selected-overlay set;
- recursive additive expansion;
- duplicate overlay names across included profiles;
- unknown parent profile;
- unknown selected profile;
- direct and indirect inclusion cycles;
- malformed lines, duplicate keys, control bytes, symlinks, oversized files,
  and unsafe machine-local ownership/permissions;
- a profile containing only parent profiles, which is valid when expansion
  resolves to at least one overlay;
- a profile with neither parents nor overlays, an explicitly empty list value,
  and a profile whose complete expansion is empty, all of which are invalid;
- invalid profile and overlay identifiers.

Use temporary `XDG_CONFIG_HOME` roots plus controlled `id` and `hostname`
command fixtures; do not add production environment overrides merely to make
tests injectable. Assert structured arrays rather than parsing human-readable
diagnostics.

### 1.2 Run the focused test and verify RED

```bash
./tests/profiles-test
```

Expected: the suite fails because `lib/dot/profiles.sh` does not exist.

### 1.3 Implement the profile schema

Implement a data-only parser with these rules:

```text
profiles.d/<name>.conf:
  version=1
  profiles=<comma-separated profile names>   # optional
  overlays=<comma-separated overlay names>   # optional

profile-selectors.d/<name>.conf:
  version=1
  user=<one user name>       # optional
  host=<one short host name> # optional
  profile=<one profile name>
```

Requirements:

- never evaluate configuration as shell;
- accept comments and blank lines consistently with existing Dot config;
- validate identifiers before using them as paths or array keys;
- require at least one of `user` or `host`, require all supplied match fields,
  and resolve identity only from `id -un` and `hostname -s`;
- compare users exactly/case-sensitively; normalize selector and runtime host
  values to ASCII lowercase after removing a trailing dot;
- accept repeated matching records only when they name the same profile and
  fail conflicting matches before final overlay mutation;
- accept selector source directories supplied by the lifecycle layer in this
  order: tracked root, machine-local untracked, then active phase-one personal;
  source order does not establish precedence because conflicting results fail;
- require machine-local selector directories/files to be owned by the current
  user, reject symlinks and group/world-writable entries, and document the
  recommended `0700` directory/`0600` file modes;
- detect cycles with an explicit visiting/resolved state, not recursion depth;
- allow a profile to contain only `profiles=<parents>` when its flattened
  result is non-empty; reject a profile with no members, an explicitly empty
  list value, or a completely empty flattened result;
- deduplicate overlays without changing descriptor order;
- publish the selected profile, inclusion chain, and selected overlay-name set
  through internal arrays used by Dot modules;
- expose no environment-variable profile override;
- add no public profile-management command.

### 1.4 Add executable sanitized examples

Follow the existing `examples/` README-oriented conventions and add a
`examples/profile-dotfiles/` tree containing real parseable files for:

- `base`, `editor`, and `dev` definitions with additive inheritance;
- Nvim/dev descriptors plus optional private descriptors using only
  `example.invalid` URLs;
- one sanitized tracked-root selector;
- machine-local user-only, host-only, and combined selectors;
- two placeholder users on one placeholder host selecting different profiles;
- agreeing matches, conflicting matches, no-match/base fallback;
- optional overlay unavailable and later available.

Use this concrete fixture layout so documentation and tests share the same
artifacts:

```text
examples/profile-dotfiles/README.md
examples/profile-dotfiles/root/.config/dot/profiles.d/base.conf
examples/profile-dotfiles/root/.config/dot/profiles.d/editor.conf
examples/profile-dotfiles/root/.config/dot/profiles.d/dev.conf
examples/profile-dotfiles/root/.config/dot/overlays.d/20-nvim.conf
examples/profile-dotfiles/root/.config/dot/overlays.d/30-dev.conf
examples/profile-dotfiles/root/.config/dot/overlays.d/80-personal.conf
examples/profile-dotfiles/root/.config/dot/overlays.d/90-work.conf
examples/profile-dotfiles/root/.config/dot/profile-selectors.d/example-user.conf
examples/profile-dotfiles/local/user-only.conf
examples/profile-dotfiles/local/host-only.conf
examples/profile-dotfiles/local/combined.conf
examples/profile-dotfiles/local/two-users-user-1.conf
examples/profile-dotfiles/local/two-users-user-2.conf
examples/profile-dotfiles/local/conflict-a.conf
examples/profile-dotfiles/local/conflict-b.conf
examples/profile-dotfiles/local/no-match.conf
examples/profile-dotfiles/personal/dot/profile-selectors.d/dev.conf
```

Use only reserved placeholders such as `example-user`, `example-user-2`, and
`example-host`. Modify `tests/examples-test` to feed the checked-in files to the
real profile/selector/descriptor parser and lifecycle fixtures, including the
unavailable-then-available optional transition. Assert inspect mode remains
offline while converge mode performs the later activation. Do not duplicate
parser logic in the example test.

### 1.5 Load the module from the runtime

Source `lib/dot/profiles.sh` from `lib/dot/runtime.sh` after XDG/config helpers
and before overlay discovery. Load/validate definitions before phase one, then
invoke selector resolution with the eligible source directories after phase-one
sync. Ensure every command that calls final `_discover_overlays` uses the same
resolved profile state.

### 1.6 Run the focused suite and static checks

```bash
./tests/profiles-test
./tests/examples-test
./tests/config-test
./tests/library-test
```

Expected: all selected suites pass.

### 1.7 Commit D1 parser slice

Commit only the parser, selector/profile examples, runtime loading, and focused
tests.

---

## Task 2: Make overlay discovery consume the resolved profile

**Repository:** `cgraf78/dot`

**Files:**

- Modify: `lib/dot/overlays.sh`
- Create: `lib/dot/overlay-context.sh`
- Modify: `lib/dot/runtime.sh`
- Modify: `lib/dot/extension-worker.sh`
- Modify: `lib/dot/extension-worker-launch.sh`
- Modify: `lib/dot/extension-trust.sh`
- Modify: `lib/dot/pre-sync.sh`
- Modify: `lib/dot/merges.sh`
- Modify: `lib/dot/doctor.sh`
- Modify: `lib/dot/commands.sh`
- Modify: `lib/dot/update.sh`
- Modify: `lib/dot/repos/pull.sh`
- Modify: `lib/dot/init-client.sh`
- Modify: `tests/repos-test`
- Modify: `tests/init-test`
- Modify: `tests/cli-test`
- Modify: `tests/test-command-test`
- Create: `tests/extension-worker-context-test`
- Modify: `tests/extensions-api-test`
- Modify: `tests/hooks-test`
- Modify: `tests/doctor-test`
- Modify: `tests/run`

**Depends on:** Task 1

### 2.1 Add failing discovery tests

Cover these cases in `tests/repos-test`:

- only overlays in the flattened selected profile are active;
- the root base repository remains active for `base`, `editor`, and `dev`
  independently of overlay selection;
- an unselected overlay is not cloned, pulled, linked, fetched, pushed,
  inspected by status, or included in diff;
- an unselected descriptor with malformed contents or an inaccessible remote
  does not affect the selected profile;
- an unselected descriptor's companion `.ssh` file is never read or merged;
- phase one synchronizes only overlays selected by `base` before selector
  resolution, then phase two synchronizes only the final resolved additions;
- root, local, and available personal selector records cover user-only,
  host-only, combined, same-host/different-user, normalized-host, no-match, and
  conflict cases;
- an unavailable optional personal overlay preserves its advisory skip, does
  not expose its selector fragments, and falls back to an agreeing root/local
  match or `base`;
- profile membership does not change descriptor-defined precedence;
- selected platform/host-ineligible overlays remain inactive;
- missing selected required overlays fail;
- missing selected optional overlays retain the existing advisory skip;
- a selected optional private overlay with no usable SSH key is skipped without
  prompting during `init`/`update` and without turning inspection into network
  activity;
- an existing selected optional checkout whose remote is temporarily
  unreachable retains its current files and reports the existing optional
  warning/skip semantics rather than becoming a required-profile failure;
- an existing validated personal checkout retained after a failed optional pull
  still contributes its current selector fragments, while a missing/unclonable
  personal checkout contributes none;
- installing access later causes the next update to clone or resume the
  selected optional overlay without changing the profile file;
- changing `dev -> editor -> base` removes only exact managed links and restores
  shadowed lower-layer/base files;
- an existing checkout for a deselected overlay remains untouched as a cache;
- a selected `sync=none` overlay retains existing validation and cleanup rules.
- transport spies prove `status`, `diff`, `doctor`, and `test` make no network,
  clone, pull, fetch, or push attempt during resolution;
- transport spies prove `fetch` resolves from existing state, fetches only
  the root and selected existing Git repositories, never clones an absent
  optional checkout, and never updates a worktree;
- transport spies prove `push` performs no preparatory clone/pull/fetch and
  pushes only the root and selected existing Git repositories.
- every isolated worker mode (`pre-sync`, `merge`, and `doctor`) ignores an
  unselected malformed descriptor without opening it;
- a stale installed overlay manifest entry cannot authorize an extension after
  that overlay is deselected;
- eligible pre-sync extensions and active merge/component-doctor extensions
  still execute through the isolated worker with the expected records;
- a worker rejects a missing/expired context, token mismatch, content tamper,
  symlink substitution, wrong owner, unsafe file/directory modes, malformed or
  duplicate records, and attempted context reuse.
- the real descriptor parser produces a valid six-field record that round-trips
  through the shared context encoder and real worker decoder byte-for-byte;
- a selected, descriptor-valid, host/platform-eligible optional overlay is in
  the pre-sync context even while unavailable, its companion preparation can
  make a later sync succeed, and it is absent from merge/component-doctor
  contexts until its checkout becomes active;
- selected-ineligible overlays expose neither a companion nor any component
  extension.
- a phase-one `prepare` context preserves existing unmentioned managed-family
  blocks through a later selector conflict or malformed selected-descriptor
  failure, without serializing stale descriptor records;
- only a successful final `reconcile` to `base` or `editor` removes managed
  entries absent from the final eligible set;
- the worker rejects `prepare`/`reconcile` on non-pre-sync modes, `stage=none`
  on pre-sync, or eligible/active set kinds paired with the wrong worker mode.

### 2.2 Run repository tests and verify RED

```bash
./tests/repos-test
./tests/init-test
./tests/cli-test
```

### 2.3 Implement two-phase profile and overlay resolution

Keep the root repository active throughout. Resolve additional overlays in two
phases:

1. load tracked profile definitions from the root repository and flatten
   `base` without consulting selector records;
2. enumerate filenames and parse only descriptors selected by `base` (currently
   the optional personal overlay), derive phase-one eligible records, run
   non-pruning pre-sync `prepare` for only their transport companions, and
   synchronize their checkouts with existing optional semantics without
   publishing a new link manifest yet;
3. load selector records from root `.config/dot/profile-selectors.d/`, local
   `.config/dot/profile-selectors.local.d/`, and repository-only
   `dot/profile-selectors.d/` in successfully active phase-one overlays;
4. resolve the matching profile; no match means `base`, combined user-and-host
   matches override broader single-field defaults, agreeing winning matches are
   deduplicated, and conflicting profiles at the winning specificity fail
   before final overlay mutation;
5. flatten the final profile, fully validate its selected descriptors, derive
   final eligible records, run full-family pre-sync `reconcile`, and synchronize
   only its eligible additions, reusing an already active personal checkout
   rather than syncing it twice.

Expose one internal resolver with an explicit lifecycle mode (`converge`,
`inspect`, or `fetch`) rather than letting commands infer side effects. `push`
uses `inspect` resolution and then performs only its own selected-repository
push phase. `status`, `diff`, `doctor`, and `test` must never call a converge or
transport-preparation path.

Within each phase, update `_discover_overlays` in `lib/dot/overlays.sh` so
selection occurs before descriptor-content activation:

1. enumerate descriptor filenames in lexical order;
2. derive and validate their logical overlay names from filenames without
   reading descriptor contents;
3. reject duplicate or ambiguous filenames that resolve to the same logical
   name, including `*.conf` versus `*.local.conf` collisions;
4. report any phase-selected overlay name for which no descriptor filename
   exists;
5. read and validate contents only for filenames named by the flattened
   selected profile;
6. apply platform and host eligibility only to those selected descriptors;
7. preserve descriptor order while publishing distinct internal sets:
   `SELECTED_OVERLAY_NAMES`, six-field `ELIGIBLE_OVERLAYS`, and six-field
   `ACTIVE_OVERLAYS`; record structured lifecycle states for
   selected-ineligible, selected-unavailable, and active overlays.

Do not use `effective` as an overlay-set name. Selection is profile membership;
eligibility follows descriptor validation plus host/platform matching; active
status follows synchronization/source validation. Compatibility code may expose
an `OVERLAYS` array at a call boundary, but it must be an exact copy of the
explicit eligible or active set required by that operation, never a mixed or
implicitly rediscovered collection.

Malformed contents in an unselected/non-phase-one descriptor must not fail or warn on the
current machine. Global validation is limited to safe filename-derived identity
and ambiguity checks; descriptor schema and remote access belong only to a
selected overlay.

Do not add a profile field to individual overlay descriptors. Profiles own
membership centrally.

Profile selection is an activation-policy gate, not an availability guarantee.
After membership and platform/host filtering, preserve the descriptor's
existing `optional=true` behavior unchanged. Do not convert a selected optional
overlay into a required overlay merely because a profile names it.

### 2.4 Pass lifecycle-scoped overlay contexts to isolated extension workers

The current extension worker starts a clean Bash process. Do not rely on
coordinator arrays surviving that boundary, and do not let
`lib/dot/extension-worker.sh` call `_discover_overlays`; remove its private
`_dot_extension_worker_discover_overlays` path entirely. Before every worker
launch, the coordinator serializes the exact eligible or active records for
that lifecycle point into a versioned, data-only context and passes both its
absolute path and a per-launch unguessable token through
`lib/dot/extension-worker-launch.sh`. Do not export shell arrays, source the
context, or encode it as shell syntax.

Create each context immediately before one worker invocation inside the
already validated per-operation temporary directory. The directory must be a
current-user-owned, non-symlink directory with no group/world permissions; the
context must be a current-user-owned, non-symlink regular file with mode
`0600`, one link, a bounded size/count, and a token/version/mode header followed
by NUL-framed canonical overlay records. The launcher owns cleanup on every
pre-exec failure. The worker validates the parent and file again, verifies the
token and requested mode, reads the complete structured payload, unlinks it
before sourcing client code, and rejects trailing, duplicate, truncated, stale,
or reused data. Its lifetime is one launch; success or failure leaves no
reusable authority file.

Extend `_dot_extension_worker_run`/`_dot_extension_worker_exec` and the worker
entry point with explicit `context_path` and `context_token` arguments; reject
missing or extra arguments. Keep the result channel separate from the context
so extension output classification cannot overwrite its authorization input.
Implement the reusable codec/parser in `lib/dot/overlay-context.sh`, loaded by
both the coordinator runtime and the worker. Have
`pre-sync.sh`, `merges.sh`, and `doctor.sh` pass the coordinator-selected record
array explicitly rather than letting the helper perform discovery.

Use a dedicated `DOT_OVERLAY_CONTEXT` wire schema; do not reuse
`_overlay_parse_manifest_record`, which remains exclusively the installed-link
schema (`relative-path`, owner, target). Version 1 contains a magic value,
version, token, worker mode, set kind (`eligible` or `active`), pre-sync stage
(`prepare`, `reconcile`, or `none`), and decimal record count as NUL-terminated
header fields, followed by exactly six
NUL-terminated fields per record in this order:

```text
name, path, url, descriptor, optional, sync
```

The shared record validator requires exactly six fields; a valid logical name;
lexically canonical absolute `path` and `descriptor` paths; a descriptor path
whose canonical filename maps back to `name`; no control bytes or record
delimiters; exact `optional=true|false`; and exact `sync=git|none`. Reuse the
descriptor parser's field validators—extract shared helpers if necessary—so
descriptor parsing and context decoding cannot drift. Do not implement looser
worker-only rules. For `git`, require a nonempty valid URL and the canonical checkout path
derived for that name. For `sync=none`, require an empty URL, `optional=false`,
and the already validated canonical local-source path. Reject duplicate names,
header/record count mismatch, missing NUL terminators, extra fields, trailing
bytes/items, oversized input, and a mode/set-kind mismatch.

Validate the complete mode/set/stage matrix: `pre-sync` requires
`set=eligible` with `stage=prepare|reconcile`; `merge` and `doctor` require
`set=active` with `stage=none`; every other combination fails before client
code is sourced. After validation, expose the pre-sync stage to the extension as
readonly structured state (for example `DOT_PRE_SYNC_STAGE`); it must never
infer stage from record count, overlay names, installed state, or whether the
set appears incomplete.

Immediately before writing, the coordinator revalidates every six-field record
with this shared validator; it must not serialize an array merely because an
earlier discovery step populated it. The worker uses the same parser and
reconstructs each exact canonical `name|path|url|descriptor|optional|sync`
record in original order. A decode/re-encode mismatch is an error.

The worker reconstructs `OVERLAYS` only from that payload. It must not enumerate
or parse `overlays.d`, load `profiles.sh`, resolve selectors, or consult a previous
installed manifest to add membership. Preserve the existing checkout,
resolved-origin-URL, worktree, extension-file, and link-target trust validation,
but require every overlay-owned extension's owner to be present in the passed
context. A root/base-owned extension remains authorized only through the
validated root client identity and sees exactly the passed overlay records. An
old on-disk manifest may corroborate filesystem identity; it can never authorize
a deselected overlay owner absent from the coordinator-provided set.

Pass these contexts deliberately:

- first converge pre-sync: phase-one `ELIGIBLE_OVERLAYS` with
  `stage=prepare`, including a selected
  descriptor-valid host/platform-eligible optional overlay whose checkout or
  transport is not yet available;
- second converge pre-sync: final `ELIGIBLE_OVERLAYS` with `stage=reconcile`,
  so an idempotent
  reconciler can prepare newly selected transports and remove state for
  deselected/ineligible overlays; repository additions remain a separate
  coordinator-side concept;
- merge workers: final `ACTIVE_OVERLAYS` only;
- component-doctor workers: final `ACTIVE_OVERLAYS` only; lifecycle doctor
  reporting for selected-ineligible and selected-unavailable overlays remains
  coordinator-owned;
- inspect/fetch/push: no pre-sync worker is launched merely to resolve state.

Modify the public `pre-sync.d/10-overlay-ssh.sh` extension in D4/D5 to consume
only the passed `OVERLAYS` records. For each record, derive the companion path
from its descriptor path (`${descriptor%.conf}.ssh`, preserving the existing
local-descriptor restriction) and inspect no other `overlays.d/*.ssh` file. The
extension remains profile-agnostic about profile names but consumes the
validated stage explicitly:

- `prepare` may add or refresh blocks derived from the supplied phase-one
  eligible records, but must preserve every other existing
  `dot-managed:overlay-ssh` family entry byte-for-byte; it cannot call the
  full-family replacement/pruning operation;
- `reconcile` replaces the complete managed family from final eligible records
  and removes entries for overlays now deselected or ineligible.

Invoke `reconcile` only after selector records, the selected profile graph, all
selected descriptor files, duplicate-name checks, and host/platform eligibility
have fully validated. A conflict or malformed selected descriptor exits before
reconcile and leaves the pre-existing non-phase-one managed entries untouched.
A selected-ineligible record is absent from both contexts, so its companion is
never exposed; removal happens from managed state only during successful final
reconcile. Do not pass stale currently installed non-base records to `prepare`
as a preservation mechanism.

Add focused worker tests for every mode proving an unselected malformed
descriptor is unread, a stale old-manifest entry cannot authorize a deselected
extension, eligible pre-sync extensions work, and active merge/component-doctor
extensions work. Add adversarial
context tests for token/content tampering, symlink replacement, wrong ownership
or permissions, wrong field count, invalid paths/URL/boolean/sync, duplicate
names, invalid mode/set/stage combinations, malformed/trailing NUL framing,
reuse after unlink, and cleanup after worker failure. Add a real-code roundtrip test that parses a valid descriptor,
encodes its exact six-field record, decodes it in the worker, and compares the
reconstructed record byte-for-byte. Add lifecycle tests proving that
`dev -> base` removes the deselected overlay's managed SSH block, `base` ignores
malformed/unreadable unselected companions, and a selected eligible optional
overlay's companion may make a later sync succeed while that overlay remains
absent from merge/component-doctor contexts until active.

Add transition tests beginning with existing generic dev/work managed blocks.
Phase-one `prepare` must preserve those blocks. A subsequent selector conflict
or malformed selected descriptor must fail with both blocks still intact. A
successful final `reconcile` to `base` or `editor` then removes only the entries
absent from the final eligible set. Inspect the serialized prepare context to
prove it contains only current phase-one eligible descriptors and no stale
dev/work descriptor records.

### 2.5 Reload profiles after a base pull

Refactor `lib/dot/repos/pull.sh` and `lib/dot/update.sh` so the update sequence
is explicit:

1. load enough validated root configuration to pull the base client repository,
   without discovering non-base overlays;
2. pull the base client repository;
3. reload Dot config and profile definitions from the updated base;
4. derive phase-one `selected`, parse/filter it into `ELIGIBLE_OVERLAYS`, and
   run the first pre-sync with that eligible set before attempting availability;
5. synchronize/validate phase-one eligible sources to produce phase-one
   `ACTIVE_OVERLAYS`, then load root/local/active-personal selector records and
   resolve the final profile;
6. derive final `selected`, validate the complete profile graph, selector
   result, selected descriptor set, and duplicate/host/platform rules, then
   publish final `ELIGIBLE_OVERLAYS`; only after every validation succeeds run
   pre-sync `stage=reconcile` with that final eligible set and attempt final
   eligible additions;
7. synchronize/validate final eligible sources to produce final
   `ACTIVE_OVERLAYS`;
8. link the root plus the final active-overlay manifest and continue normal
   convergence.

Update progress totals after rediscovery instead of retaining a count derived
from the pre-pull selection.

### 2.6 Integrate initialization

In `_dot_init_forward_converge` in `lib/dot/init-client.sh`, resolve profiles
after publishing/loading the candidate base client. Synchronize the base-phase
eligible optional personal overlay only after running phase-one pre-sync as
`prepare`, producing an active phase-one set; load selector fragments only from
active personal, then resolve and fully validate final selected/eligible
records, run final pre-sync as `reconcile`, and synchronize them into the final
active set. A fresh client with no matching selector installs only the root
plus active base-selected personal overlay.

### 2.7 Split tracked and machine-local path reservations

Add a `kind=overlay` rule in `_repo_validate_candidate_tree` (or a dedicated
overlay-candidate helper) so an overlay cannot own:

```text
.config/dot/profiles.d/
.config/dot/profile-selectors.d/
```

Do not add those two tracked control-plane paths to the generic reserved-root
list, because the base
candidate must be allowed to publish `.config/dot/profiles.d/*.conf` and tracked
root selectors.

Separately reserve this path from every repository candidate, including base:

```text
.config/dot/profile-selectors.local.d/
```

The user exclusively owns the local selector directory; an ignore rule alone
cannot stop a future tracked base commit from colliding with it. Add candidate
tests proving the base accepts tracked `profiles.d` and
`profile-selectors.d`, while base and overlay candidates reject a regular file,
directory entry, and symlink anywhere below
`profile-selectors.local.d/`. Keep the `git check-ignore` test in Task 10.3 as a
separate defense.

An active
phase-one overlay may provide repository-only `dot/profile-selectors.d/*.conf`
outside `home/`; those files are parsed directly from its validated checkout
and never linked. Tests must also prove linked-home selector paths are rejected
in every overlay candidate, repository-only phase-one selector fragments are
accepted, and selector symlinks are rejected.

### 2.8 Run focused and full Dot tests

```bash
./tests/profiles-test
./tests/examples-test
./tests/repos-test
./tests/init-test
./tests/cli-test
./tests/test-command-test
./tests/extension-worker-context-test
./tests/extensions-api-test
./tests/hooks-test
./tests/doctor-test
./tests/run
```

`tests/run` intentionally remains the unfiltered full-provider command; do not
pass suite names to it unless filtering is separately implemented and tested.

### 2.9 Commit D1 integration slice

Use a second commit in the same Dot PR so parser review and lifecycle review
remain separable. Treat eligible/active context serialization, worker
validation, and all three extension modes as part of D1; do not defer the
worker boundary to the top-level consumer PR.

---

## Task 3: Report profiles through existing Dot commands

**Repository:** `cgraf78/dot`

**Files:**

- Modify: `lib/dot/doctor/overlays.sh`
- Modify: `tests/doctor-test`
- Modify: `docs/configuration.md`
- Modify: `docs/overlays.md`
- Modify: `README.md`

**Depends on:** Tasks 1-2

### 3.1 Add failing doctor tests

Assert that `dot doctor` reports:

- selected profile;
- normalized current user and short host;
- matching selector records and their source class: root, machine-local, or
  active personal overlay;
- selection result: implicit `base`, one agreed matched profile, or conflict;
- phase-one base overlay state separately from final selected additions;
- flattened included profiles;
- configured overlay names;
- every descriptor filename classified as exactly one of `not selected`,
  `selected but host/platform ineligible`, `selected optional but unavailable`,
  or `active`;
- selected required overlays that cannot become active as failures;
- invalid profile configuration as a failure.
- no network or repository mutation while resolving selector sources.

Keep control flow on structured resolver/discovery state; render prose only in
doctor. Only active overlays contribute component health checks. The top-level
doctor owns profile resolution and overlay lifecycle reporting, not health
checks for tools that moved to capability overlays.

### 3.2 Implement doctor reporting

Extend `lib/dot/doctor/overlays.sh`. Do not add `dot profile`, profile mutation,
or environment override commands. Report the root repository separately as the
always-active base substrate rather than synthesizing a `core` overlay record.
Use inspect-mode resolution only; an absent personal checkout is reported as an
optional unavailable phase-one source and is not cloned or pulled.

### 3.3 Document the contract

Document:

- profile file schemas;
- selector record schemas, exact matching/normalization, conflict behavior, and
  root/local/phase-one-personal sources;
- additive inclusion;
- default `base` behavior;
- the client/root repository is always active and profiles select only
  additional overlays;
- descriptor order versus profile membership;
- optional and platform/host filtering semantics;
- the distinct selected, eligible, and active sets and which worker modes
  consume eligible versus active records;
- phase-one pre-sync `prepare` preservation versus post-validation final
  `reconcile` pruning semantics;
- machine-local selector directory ownership and exact ignore rule;
- two-phase optional-personal bootstrap and fallback when it is unavailable;
- converge versus inspect/fetch/push lifecycle modes and their network/mutation
  boundaries;
- legacy behavior when a generic Dot client has no `profiles.d` directory.

Link the checked-in `examples/profile-dotfiles/` scenarios and run them through
the real parser in `tests/examples-test`. Use only reserved generic example
names and `example.invalid` URLs in standalone Dot documentation.

### 3.4 Verify D1 completely

```bash
./tests/run
```

Run the workflow-equivalent checks from `.github/workflows/ci.yml` that are
available locally.

### 3.5 Fresh-eyes review and open D1

Review profile parsing, path trust, cycle handling, update rediscovery, and
link cleanup as separate axes. Open D1, record its exact reviewed PR head SHA,
and monitor all available checks to green. During Phase A, do not merge D1 or
publish a release. D2/D3 and the D4/D5 integration harness consume that exact
PR head SHA; any D1 update requires repinning and rerunning all consumers.

---

## Task 3A: Freeze source and license evidence before capability bootstrap

**Repository:** `cgraf78/dotfiles`

**Files:**

- Create: `.local/share/doc/dotfiles/overlay-profile-source.lock`

**Depends on:** A clean isolated D4 worktree based on the reviewed current
`origin/main`; complete before initializing either capability repository

Fetch the source once, resolve a full immutable commit ID, verify that
`.github/LICENSE` exists at that commit, and record the SHA in
`overlay-profile-source.lock` as the first published D4-branch evidence commit.
Do this before creating either local capability bootstrap commit or GitHub
repository:

```bash
git fetch origin main
source_sha=$(git rev-parse --verify 'origin/main^{commit}')
git cat-file -e "$source_sha^{commit}"
git cat-file -e "$source_sha:.github/LICENSE"
printf '%s\n' "$source_sha"
git show "$source_sha:.github/LICENSE"
```

Record the printed full SHA with the repository's normal patch workflow. Read
the canonical license bytes locally with `git show
"$source_sha:.github/LICENSE"`; after this freeze, no bootstrap, CI, or
acceptance step may obtain canonical bytes from a moving default branch.
Publish the source-lock commit on the future D4 branch before Task 4 begins.

The SHA selected here is authoritative. Task 4 copies it into each capability
repository's `.github/dotfiles-source.lock`; Task 5 adopts it unchanged for the
baseline; and Task 10 records the same value as `source_dotfiles` in the stack
lock. Choosing a newer source is a Task 5.5 reconciliation, not a silent repeat
of this command.

---

## Task 4: Create the two optional capability overlay repositories

**Repositories:**

- `cgraf78/dotfiles-nvim`
- `cgraf78/dotfiles-dev`

**Depends on:** Stable profile/overlay contract from D1 and the published exact
source lock from Task 3A

### 4.1 Bootstrap each new repository, then branch from `origin/main`

These repositories do not yet have an `origin/main`. Read the GitHub PR
lifecycle playbook and construct each bootstrap repository locally before any
GitHub repository exists. For each repository:

1. Initialize a clean local repository with default branch `main`; add an MIT
   `LICENSE`, public README, and skeleton files. Before the bootstrap commit,
   read `source_sha` from Task 3A's published
   `overlay-profile-source.lock`, extract the exact bytes from the local source
   repository with `git show "$source_sha:.github/LICENSE"`, and copy those
   bytes to the new repository's root `LICENSE`. Do not extract, filter, graft,
   or copy Git history from `dotfiles`.
   Create `.github/dotfiles-source.lock` with this machine-readable content:

   ```text
   version=1
   repository=cgraf78/dotfiles
   commit=<exact-source-sha>
   license_path=.github/LICENSE
   ```

   Reject an abbreviated/non-commit SHA or any value unequal to the published
   Task 3A lock.
   Using a caller-supplied absolute `source_repo` that resolves to the audited
   local `cgraf78/dotfiles` repository, perform the copy and immediate local
   comparison:

   ```bash
   audit_dir=$(mktemp -d)
   readonly audit_dir
   trap 'rm -rf -- "$audit_dir"' EXIT HUP INT TERM
   git -C "$source_repo" show "$source_sha:.github/LICENSE" >"$audit_dir/source-LICENSE"
   cp "$audit_dir/source-LICENSE" LICENSE
   cmp LICENSE "$audit_dir/source-LICENSE"
   ```

2. Put only the new repository skeleton in the bootstrap commit. Tasks 7-8 may
   later copy literal capability paths allowlisted for that owner by the final
   ownership inventory. Review every copied file. A clean history is mandatory
   so deleted/private content cannot ride along in unreachable commits or blobs.
3. Before the first push, inspect the complete tracked content and Git object
   graph, run secret/privacy scanners over both the worktree and full history,
   compare the new root `LICENSE` byte-for-byte with the canonical
   `cgraf78/dotfiles:.github/LICENSE` MIT file at the frozen source revision,
   and obtain a fresh-eyes public-boundary review:

   ```bash
   git fsck --full --no-reflogs
   git rev-list --objects --all
   gitleaks dir . --redact --no-banner
   gitleaks git . --redact --no-banner
   ```

   Resolve every finding before pushing. The review must confirm there is no
   private or work-specific content, name, topology, configuration, fixture,
   comment, generated artifact, or history.
4. Only after the local bootstrap passes scans and fresh-eyes review, create the
   GitHub repository as public from the corresponding local repository and push
   only that reviewed `main`:

   ```bash
   gh repo create cgraf78/dotfiles-nvim --public --source=. --remote=origin --push
   gh repo create cgraf78/dotfiles-dev --public --source=. --remote=origin --push
   ```

   Run each command from its matching local bootstrap repository. Set and verify
   `main` as the default branch, then create D2/D3 branches from
   the verified `origin/main` in repo-local ignored `.worktrees/` directories.
   The clean bootstrap commit is the only direct-to-main setup step; all
   capability work proceeds through public PRs.
5. Audit and mirror the existing `cgraf78/dotfiles` repository settings with
   `gh api`. Record the audited method/path/normalization rules in
   `.github/repository-settings-endpoints.txt` and drive export, apply, and
   comparison from that manifest rather than an implementer's remembered list.
   Cover all configurable surfaces:
   general repository settings and merge policies, default branch, Actions
   permissions/settings, branch protection and rulesets, security features,
   topics, and any other setting exposed for the source repository. Use calls
   equivalent to:

   ```bash
   gh api repos/cgraf78/dotfiles
   gh api repos/cgraf78/dotfiles/actions/permissions
   gh api repos/cgraf78/dotfiles/actions/permissions/workflow
   gh api --paginate repos/cgraf78/dotfiles/rulesets
   gh api repos/cgraf78/dotfiles/branches/main/protection
   gh api repos/cgraf78/dotfiles/topics
   ```

   Apply the matching values to each target with the corresponding `gh api
   --method PUT/PATCH` endpoint, then export target state and compare normalized
   sorted JSON using an audited `jq -S` identity-field deletion list followed
   by `diff -u`. The comparison command must exit nonzero on any unexplained
   difference. Treat an absent endpoint or empty collection as an explicit
   source state to mirror, not a reason to skip the surface. Document only
   unavoidable identity-specific differences such as repository
   name/URL/description; do not silently accept policy drift. Settings parity
   means repository policy parity, not copying identity-bound access or secret
   material. Do not copy deploy keys, collaborators, GitHub App installations,
   webhooks, secrets, variables, environment credentials, or other integrations
   from the source repository. Require the new repositories to begin with none
   of those target-specific bindings, and record inaccessible credential/
   integration API surfaces as explicit audit exclusions rather than weakening
   the policy comparison.
   Record creation and completed-comparison timestamps in the repository
   bootstrap audit so the brief interval in which GitHub defaults applied is
   explicit. Apply and normalized-compare the mirrored settings immediately
   after creation and before accepting any external contribution or pushing
   anything beyond the reviewed bootstrap. No issue, PR, or contribution is
   accepted during that interval.
   D3's maintenance workflows may declare a new repository-specific deploy-key
   secret placeholder. Phase A creates or copies no credential: the workflows
   must fail closed until a fresh key is provisioned as an explicit Phase B
   pre-merge prerequisite.
   Use `test/lib/wait-github-state.sh` to poll the actual API predicates for
   initial license visibility and normalized settings equality. Use fresh API
   reads, a fixed deadline (for example 120 seconds), a modest poll interval,
   and timeout diagnostics containing the last status/diff; do not use an
   unconditional sleep or treat one transient 404/stale response as failure.
6. Before every later push that contains extracted capability content, repeat
   the worktree and full-history scans and obtain a fresh-eyes public-boundary
   review of the exact commits being pushed. Repeat both again for final
   acceptance.

The bootstrap state must be public from GitHub creation onward, with an MIT
license, default branch `main`, clean independent history, and settings
equivalent to `cgraf78/dotfiles` except for explicitly reviewed identity fields.

Give each repository:

```text
.github/workflows/test.yml
.github/workflows/retry-infrastructure.yml
.github/dependabot.yml
.github/dot-test-suites.txt
.github/shellcheck-files.txt
.github/cgraf78-actions.lock
.github/dot.lock
.github/dotfiles-source.lock
.github/repository-settings-endpoints.txt
.gitignore
LICENSE
README.md
home/
test/run
test/workflow-test
test/lib/capability-fixture.sh
test/lib/repository-settings.sh
test/lib/wait-github-state.sh
```

Copy the generic retry workflow and Dependabot Actions configuration from the
frozen source revision, preserving their immutable action pins. The tracked
`test/lib/repository-settings.sh` helper owns manifest parsing plus explicit
export, apply, and normalized-compare modes; it hard-allowlists the source and
the two target repository names and refuses mutation when a required source
policy read is unavailable.

### 4.2 Document the common overlay contract

Each README must state:

- only files below `home/` are linked;
- the repository is selected by a top-level dotfiles profile;
- dependency declarations, hooks, config, and tests move together;
- the install declaration, configuration/runtime, focused tests, doctor checks,
  and component documentation for one capability have the same owner;
- it must not define or mutate profile selection;
- configuration may reference only its own tools or tools inherited from a
  lower profile;
- private and work-specific material is forbidden in these public repos.

### 4.3 Add overlay-source test harnesses

Make `test/run` create a temporary HOME and a controlled fixture `PATH` that
contains only explicitly provisioned test doubles and required system commands.
Record the reviewed immutable D1 PR head commit in `.github/dot.lock` and
install that exact standalone Dot revision into the fixture's isolated XDG data root,
without treating the overlay checkout as a base dotfiles checkout.
Install the current overlay as a `sync=none` source, run the repo-owned focused
suite inventory and its component doctor checks through standalone Dot, and
preserve the real host state. Assertions about command availability must use the
selected dependency plan and controlled install roots, not accidental commands
from the host PATH. Use bounded temporary paths and no live HOME writes.

Name the minimal synthetic-root inputs explicitly. Each repository owns
`test/lib/capability-fixture.sh`, which creates only
`$fixture_root/.config/dot/config` and the canonical descriptor
`$fixture_root/.config/dot/overlays.d/20-nvim.conf` for `dotfiles-nvim` or
`$fixture_root/.config/dot/overlays.d/30-dev.conf` for `dotfiles-dev`. The
descriptor is generated with `sync=none` and the exact overlay checkout path.
Any inherited shell/tmux/Nvim adapter data lives under named files in
`test/fixtures/inherited/` and is copied only when that overlay's focused tests
need it. Do not point `DOT_SOURCE_ROOT`, HOME, or the base client at the overlay
checkout, and do not opportunistically copy a real root-dotfiles tree.

This harness intentionally exercises standalone Dot's supported
**no-base-repository** topology: the synthetic root contains configuration but
is not a Git worktree, base-repository detection must report absent, and the
capability checkout is visible only through its `sync=none` descriptor. Assert
all three facts before running suites. If that supported topology changes, make
an explicit reviewed harness change; do not silently initialize a synthetic
base Git client or repurpose the overlay checkout as one.

Do not clone or assemble lower capability overlays in capability-repository CI.
Where an overlay consumes an inherited interface, provide the smallest explicit
fixture or test double needed to validate this overlay's adapter. Profile
inheritance and real multi-overlay composition are top-level integration
responsibilities.

### 4.4 Add shared CI

Reuse the existing public dotfiles/shared shell CI workflow and its immutable
repository-owned pin. Copy `.github/cgraf78-actions.lock` from the audited
source decision, use that one value for every literal `cgraf78/actions` ref, and
add the adapted `actions-sync` verification job using
`verify-consumer-sync`. `test/workflow-test` must fail when the lock is missing,
the sync job is absent, or any literal shared-workflow/action SHA differs from
the lock. `test/run` executes this repository-infrastructure test before the
Dot-focused suite inventory, exactly once.

The same infrastructure test verifies `.github/dot.lock` is an immutable commit
identifier and that `test/run` installs exactly that revision rather than a
moving branch, skeleton default branch, or latest release. If D1 changes, update
the lock in both capability PRs and rerun their complete CI before either PR is
considered green.

Each repository's `test/run` must read only its literal
`.github/dot-test-suites.txt`, verify every listed suite exists in that source
tree, and run that selected list. Scope completeness validation specifically to
the installed Dot suite root at `home/.local/lib/dotfiles/tests/`: reject an
extra executable component `*-test` there, but do not treat repository
infrastructure under `test/` as a Dot component suite. The
inventory must contain only this overlay's focused behavior and doctor-check
tests; it must not name or invoke suites owned by an inherited overlay.
Call the reusable workflow with `setup: none` rather than `setup: dotfiles`, so
an overlay checkout is never treated as the base client. Select only the
repo-specific prerequisite profiles already exposed by `shell-ci.yml` (for
example base plus the required jq/python/zsh/lua/neovim/tmux/SSH/process/search
profiles), and let `test/run` construct the isolated overlay fixture.
Run:

```bash
test/run
```

plus ShellCheck over each repository's own executable shell inventory. Do not
bootstrap the top-level dotfiles checkout merely to rerun capability suites.

Drive settings audit from the checked-in
`.github/repository-settings-endpoints.txt`; the export/apply/compare tool must
fail if a required surface is absent from the manifest, and
`test/workflow-test` must verify the manifest covers the required settings
families. Record the exact canonical license locator
`cgraf78/dotfiles:.github/LICENSE` and the exact immutable source commit in
`.github/dotfiles-source.lock`. Make `test/workflow-test` parse that file,
validate its version/repository/path/full commit ID, and fail if either the
canonical path or source SHA changes, cannot be read, or differs from the
bootstrap evidence. Verify each new root
`LICENSE` both locally against those canonical source bytes and remotely
through GitHub:

```bash
set -o pipefail
source_sha=$(awk -F= '$1 == "commit" { print $2 }' .github/dotfiles-source.lock)
test -n "$source_sha"
audit_dir=$(mktemp -d)
readonly audit_dir
trap 'rm -rf -- "$audit_dir"' EXIT HUP INT TERM
gh api --method GET repos/cgraf78/dotfiles/contents/.github/LICENSE \
  -f ref="$source_sha" --jq .content |
  base64 --decode >"$audit_dir/source-LICENSE"
cmp LICENSE "$audit_dir/source-LICENSE"
test "$(gh api "repos/$target_repo/license" --jq .license.spdx_id)" = MIT
```

Set `target_repo` to only the repository running the workflow. Each capability
workflow verifies its own remote license/SPDX state and never waits for the
other capability repository to exist. After both public repositories have been
created and their own checks are visible, the bootstrap coordinator uses the
same bounded condition helper to verify both target SPDX results, immutable-ref
license bytes, and normalized settings together. This avoids an ordering race
between the two initial repository creations.
Treat the remote reads above as predicates passed to
`test/lib/wait-github-state.sh` during the first post-push run; later steady-
state CI may execute them directly because visibility has already converged.

Test the condition helper with scripted API responses: transient not-found,
stale settings, then success; and a never-ready case that exits at the deadline
with the last response/diff. The helper must re-read state each iteration and
sleep only between failed predicates, never as an unconditional post-push delay.

Add a harness fixture proving an unlisted executable under the installed Dot
suite root is rejected while declared `test/workflow-test` is accepted and
executed exactly once outside the component inventory.

### 4.5 Verify empty skeletons

Run every `test/run` and `test/workflow-test` locally before beginning file
moves. Verify the lock/sync contract, endpoint manifest, canonical MIT content,
remote SPDX identity, public visibility, default `main`, and normalized settings
comparison before beginning file moves. Verify the `commit=` value in both
capability `.github/dotfiles-source.lock` files exactly equals Task 3A's
`overlay-profile-source.lock`; neither bootstrap is green if the evidence
differs.

After both repositories exist, run the coordinator acceptance with bounded
condition polling until both own-license endpoints report `MIT` and every
settings endpoint reaches the normalized expected state, or the deadline
expires. On timeout, print the last HTTP/status result and normalized diff.
Never replace this predicate wait with a fixed post-creation sleep.

At bootstrap, an empty `.github/dot-test-suites.txt` is valid and `test/run`
must still execute `test/workflow-test` exactly once. The final D2 and D3 PR
heads each require at least one owner-focused installed Dot suite; their CI must
reject a final empty inventory as well as an unlisted executable component
suite.

---

## Task 5: Build exhaustive baseline and final ownership inventories

**Repository:** `cgraf78/dotfiles`

**Files:**

- Create: `.local/share/doc/dotfiles/overlay-profile-baseline-disposition.tsv`
- Create: `.local/share/doc/dotfiles/overlay-profile-final-ownership.tsv`
- Verify: `.local/share/doc/dotfiles/overlay-profile-source.lock`
- Create: `.local/lib/dotfiles/tests/overlay-profile-ownership-test`

**Depends on:** Task 3A's published source lock and agreed D2-D3 repository
layouts from Task 4

Continue on the published future-D4 branch after Task 3A's source-lock commit;
do not regenerate or replace that lock merely because Task 4 has completed.
D2/D3 use the reviewed inventories and immutable source lock to drive
extraction. Push the relevant D4 inventory update before the corresponding
extracted-content push so the recorded lineage is reviewable first.

### 5.1 Generate the baseline disposition inventory

Read the already-published full commit ID from
`overlay-profile-source.lock`, verify it is the Task 3A bootstrap source, and
capture every literal tracked path from `git ls-files` at that exact commit in
`overlay-profile-baseline-disposition.tsv`, keyed uniquely by old source path:

```bash
source_sha=$(tr -d '\n' <.local/share/doc/dotfiles/overlay-profile-source.lock)
git cat-file -e "$source_sha^{commit}"
printf '%s\n' "$source_sha"
git ls-tree -r --name-only "$source_sha"
```

The commands above verify the already frozen revision; they must not select or
rewrite it. Compare this SHA with both capability
`.github/dotfiles-source.lock` records before generating the baseline.

```text
source_path<TAB>component_id<TAB>category<TAB>transform<TAB>d4_action<TAB>d5_action<TAB>ownership_note
```

Allowed `transform` values are `keep`, `delete`, and `split`; allowed D4/D5
actions are `keep`, `remove`, `rewrite`, and `none`. Every old tracked path
appears exactly once. Categories distinguish at least `control`,
`config`, `dependency`, `runtime`, `test`, `doctor`, `docs`, `ci`, and
`repository`. Stable `component_id` values connect mixed/split old inputs to all
of their final outputs.

Use these phase rules:

- base/control paths: `d4_action=keep`, `d5_action=keep`;
- Nvim/dev focused tests, component doctor checks, and component-only docs:
  `d4_action=remove`, `d5_action=none` after their owning public CI is green;
- Nvim/dev config, runtime, dependency, and installation declarations:
  `d4_action=keep`, then `d5_action=remove` or `rewrite` so executable behavior
  transitions atomically at final cutover;
- mixed inputs such as a combined tmux, shell, mise, Shdeps, or generated-input
  file: use `transform=split`, rewrite the old path in the phase that produces
  the final base remainder, and connect every output through the same stable
  component ID.

D4 may temporarily contain identical dependency/install declarations in root
and a selected overlay; aggregation must deduplicate them deterministically and
the D4 composition test must enumerate the expected temporary duplicates. A
base machine remains a documented monolith until D5 removes/rewrites those root
declarations with the matching config/runtime.

Every D2/D3 allowlisted copy and every D4/D5 pre-cutover fixture reads from the
locked source commit, using a detached worktree or `git archive <locked-sha> --
<allowlisted-paths>`. It must never copy from a moving `origin/main` checkout.

### 5.2 Generate the exhaustive final ownership inventory

Create `overlay-profile-final-ownership.tsv`, keyed by the pair
`(repository,destination_path)`:

```text
repository<TAB>destination_path<TAB>component_id<TAB>category<TAB>origin<TAB>available_by<TAB>ownership_note
```

Allowed repositories are `dotfiles`, `dotfiles-nvim`, and `dotfiles-dev`.
`origin` is either `old:<source_path>` or `new`; `available_by` is one of
`bootstrap`, `d2`, `d3`, `d4`, or `d5`. This table covers every final tracked
path in all three public repositories, including new `LICENSE`, README, CI,
root/capability source locks, stack locks, settings-manifest, test harness,
selector, and migration metadata paths.

The same relative destination such as `README.md`, `LICENSE`, or `test/run` is
valid in different repositories. Reject duplicates only within the same
`(repository,destination_path)` key. One old source may map to many final rows,
many old sources may share a component ID, and a final row may use `origin=new`;
this supports one-to-many and many-to-many splits without fake metadata
exceptions. Every split output requires an owner, category, `available_by`, and
stable component ID.

Every agent-related row is classified path-by-path as `base-rule`,
`base-rule-aggregation`, or `dev-agent-tooling` in `ownership_note`. Only rule
files currently owned by the public base repo and required `agent-rules-sync`
machinery remain in `dotfiles`; unrelated agent tooling belongs to
`dotfiles-dev`. Private overlay rule fragments remain outside these public
inventories with their existing owners.

### 5.3 Add failing inventory validation

Write `.local/lib/dotfiles/tests/overlay-profile-ownership-test` to fail for:

- a missing, malformed, or non-commit source lock;
- either capability `.github/dotfiles-source.lock` using a repository/license
  path other than `cgraf78/dotfiles:.github/LICENSE`, or a commit unequal to the
  root source lock;
- a baseline path set that differs from `git ls-files` at the locked source
  commit;
- an old tracked path missing from or duplicated in the baseline table;
- an invalid transform/action combination or a `split` row without linked final
  outputs;
- a final tracked path in any public repository missing from the final table;
- duplicate destination ownership within one repository, while explicitly
  allowing the same relative path in different repositories;
- a final `old:<source_path>` origin absent from the baseline table;
- a split component without all output owners/categories/availability phases;
- a new metadata path missing an `origin=new` final row;
- an unknown owner or category;
- a capability implementation path assigned to `dotfiles`;
- a control-plane path assigned to a capability overlay;
- a component whose installation declaration, config/runtime, focused tests,
  doctor checks, or component docs have different owners;
- an Nvim/dev-focused test, component doctor check, or component-only document
  not removed from root in D4;
- an Nvim/dev dependency/install declaration removed in D4 instead of remaining
  with its legacy config/runtime until D5;
- an agent path whose owner conflicts with its `base-rule`,
  `base-rule-aggregation`, or `dev-agent-tooling` classification;
- a focused test, doctor check, or document whose agent classification differs
  from the runtime/rule files it covers;
- a capability destination that does not start below that repository's
  `home/` or documented repository-only test/docs roots.

Keep explicit, reviewed exceptions only for shared repository metadata such as
licenses and CI bootstrap. Do not use a broad exception that could hide an
unassigned implementation path.

### 5.4 Verify both complete inventories

```bash
.local/lib/dotfiles/tests/overlay-profile-ownership-test
```

Review both TSVs by component, category, owner, and phase before copying any
capability file. Treat them as the source of truth for Tasks 6-8 and both D4/D5
change lists.

### 5.5 Keep both inventories live through cutover

When a tracked path is added, removed, split, or changes destination during
implementation, first update the D4-branch inventories, push that reviewed
inventory commit, and only then push the corresponding D2/D3 extraction.
Record a coordinated commit set consisting of the inventory commit and exact
D2/D3 commits; one Git commit cannot atomically update multiple repositories.
D4 validates every old path's D4 disposition, every final path available by D4,
and the exact temporary legacy dependency/config/runtime set. D5 validates
every old path's final disposition and exact equality between each repository's
`git ls-files` output and its `(repository,destination_path)` final-ownership
rows.

If any split PR is rebased or updated onto a newer root `origin/main`, stop and
perform explicit source reconciliation: update `overlay-profile-source.lock`,
regenerate the baseline from the new exact commit, diff and review every changed
disposition and public-boundary consequence, refresh affected extracted files
and final-ownership rows, repin the coordinated commit set, and rerun all
ownership, privacy, content/history, and integration checks. Never let a
routine rebase silently change the extraction source.

Source reconciliation also invalidates both capability license/source-evidence
records. Extract `.github/LICENSE` locally from the new exact SHA, replace both
root `LICENSE` copies byte-for-byte, update both
`.github/dotfiles-source.lock` files, and require their commits to equal the new
root lock and stack-lock `source_dotfiles`. Repeat local `cmp`, immutable-ref
remote-byte comparison, GitHub `MIT` SPDX checks, workflow tests, privacy scans,
and fresh-eyes public-boundary review before pushing either updated capability
PR. A source-SHA advance may not retain an older license merely because its text
appears unchanged.

---

## Task 6: Define and preserve the always-active base substrate

**Repository:** `cgraf78/dotfiles`

**Depends on:** Task 5 ownership inventory

This task classifies the base paths that remain in the root repository and the
split points consumed by Tasks 7-8. Its changes land through D4/D5 rather than a
separate capability-overlay PR.

### 6.1 Separate D4 staging coverage from D5 base-boundary coverage

For D4, keep/run positive base-owned behavior tests that can pass while known
legacy Nvim/dev config/runtime remains temporarily shadowed. Assert that the
staging home provides:

- working shell startup and base-owned loaders;
- tmux base configuration;
- DS and terminal navigation expected by base;
- common search/navigation utilities;
- public/base agent rules and `agent-rules-sync` aggregation;
- baseline-inventory evidence identifying every expected temporary
  baseline path whose D4 action retains temporary Nvim/dev behavior.

Keep these suites in the top-level CI inventory because their implementation
owner remains `dotfiles`. Do not add or enable final absence assertions in D4;
the monolithic staging tree still intentionally contains legacy optional
config/runtime.

Define a separate `base-profile-boundary-test` for Task 12/D5 that asserts no
Nvim, global Git config, dev-owned agent tooling/configuration, development mise
tools, or development hooks remain after cutover.

### 6.2 Retain root shell entry points

Keep these tracked entry points in the always-active root repository:

```text
.bash_profile
.bashrc
.inputrc
.profile
.zprofile
.zshenv
.zshrc
```

Keep them as thin loaders and remove dependencies on optional editor/dev tools.

### 6.3 Retain and split base XDG configuration

Keep the base-owned portions of:

```text
.config/atuin/
.config/agent-rules/rules.d/
.config/agent-rules/playbooks.d/
.config/bottom/
.config/ds/
.config/htop/
.config/ripgrep/
.config/shell/
.config/tmux/
.config/wezterm/
```

Remove references to Nvim, Git development workflows, language toolchains,
Lazygit, Sley, Checkrun, unrelated agent executables/plugins/hooks, and
development-only environment state. Base shell policy must remain usable when
none of those optional commands exists.

Keep only the agent rule files currently owned by the public base repository,
plus the required `agent-rules-sync` machinery that already aggregates,
synchronizes, and applies those rules. Keep their focused tests, doctor checks,
and docs with them. Do not move existing personal or work rule fragments from
their current overlays, and do not use this rule decision to retain unrelated
agent binaries, skills, plugins, hooks, wrappers, or other dev tooling in base.

### 6.4 Fragment tmux configuration

Make `.config/tmux/tmux.conf` source ordered fragments from:

```text
.config/tmux/conf.d/*.conf
```

Place base server/session/terminal behavior in
`.config/tmux/conf.d/10-base.conf`. Leave Nvim-specific navigation and
opening behavior for `dotfiles-nvim`.

### 6.5 Keep Git bootstrap-only

Move `.config/git/` to `dotfiles-dev`. Retain only the Git executable, Dot's
PATH-visible routing/bootstrap pieces, and SSH support required to clone and
update overlays. A base machine receives upstream Git defaults when Git is
invoked directly.

### 6.6 Split base dependencies

Keep focused base Shdeps declaration files under:

```text
.config/shdeps/
```

Include only shell, tmux, DS/Termnav, navigation/search, archive, update, and
diagnostic dependencies needed by `base`, plus the `agent-rules-sync` provider
required to aggregate/synchronize/apply base and overlay-contributed rule
fragments. Install tmux 3.6b through a base-owned custom Shdeps hook using the
exact platform URLs and checksums frozen in the source Mise lock. Preserve
user-owned command paths, publish the managed payload atomically, and keep
Android on its native package path. The remaining Mise configuration, lock,
merge hook, and development tools move together to `dotfiles-dev`.

### 6.7 Keep base hooks, focused tests, doctor checks, and docs

Keep merge hooks, doctor checks, helper libraries, focused tests, and component
documentation whose implementation remains in `base`. Keep their installation
declarations and runtime code in the same root owner. Preserve existing suite
names when practical and list every retained executable suite in the top-level
`.github/dot-test-suites.txt`. This includes focused public agent-rule and
`agent-rules-sync` aggregation suites/checks; private overlay rule fragments
remain tested by their existing owners.

### 6.8 Reserve final base verification for D5

Do not run this gate in D4. After Task 12 removes every
baseline path scheduled for D5 removal/rewrite, add/enable
`base-profile-boundary-test`, run the
top-level CI inventory, and in the controlled fixture PATH prove:

```bash
command -v git
! test -e "$HOME/.config/git/config"
! command -v nvim
```

inside the clean fixture home.

### 6.9 Record base ownership for D4/D5

Mark retained base paths with `d4_action=keep`, `d5_action=keep`, and matching
`repository=dotfiles` final rows. Mark only Nvim/dev paths for D4 removal or D5
removal/rewrite.

---

## Task 7: Populate `dotfiles-nvim`

**Repository:** `cgraf78/dotfiles-nvim`

**Depends on:** Tasks 4-6

### 7.1 Add failing Nvim-owned behavior tests

Install only the Nvim overlay with minimal stubs for inherited shell/tmux
extension points and assert:

- Nvim starts headlessly;
- editor UI/navigation plugin specs load;
- no Mason, LSP, DAP, language toolchain, formatter, or linter is
  declared or installed by the Nvim overlay;
- the editor tmux fragment parses against the minimal inherited tmux interface
  fixture.

Do not assemble the full root `dotfiles` substrate or rerun its suites here. The
top-level composition fixture proves that `editor` preserves `base` and that the real
fragments compose without collision.

### 7.2 Move Nvim-owned configuration

Copy only Nvim-owned literal paths allowlisted by the final ownership inventory
from the exact commit in `overlay-profile-source.lock`; do not import source Git
history or read from a moving source worktree.
Move `.config/nvim/` under `home/`, then separate development additions into
files reserved for Task 8. Keep editor-owned behavior such as UI, navigation,
Tree-sitter syntax, sessions, buffers, file search, and basic Git indicators.

### 7.3 Add editor shell fragments

Create editor-owned shell fragments that set:

```bash
EDITOR=nvim
NVIM_COLORSCHEME=night-owl
```

and define the `vi` alias. Base must not mention Nvim.

### 7.4 Add the tmux editor fragment

Create `home/.config/tmux/conf.d/20-editor.conf` containing Nvim pane
navigation, file opening, editor-focused mouse behavior, and other bindings
that require the Nvim/Termnav editor adapter.

### 7.5 Isolate ripgrep editor linkification

Keep ordinary ripgrep policy usable in `base`. Put Nvim-specific hyperlink
routing in an editor-owned fragment or editor-owned generated target. Do not
make the base ripgrep invocation depend on `nvim-link-host`.

### 7.6 Make development plugins additive

Keep `lazyvim.json` limited to editor-level extras. Provide a documented Lua
import point that a later overlay can extend with development extras without
replacing the editor configuration. A superset `lazy-lock.json` is acceptable
because lock entries do not activate plugins.

### 7.7 Move Nvim hook, focused tests, doctor checks, and docs

Move the Nvim installation declaration, update merge hook, doctor checks,
`nvim-test`, Lua tests needed by the editor, component documentation, and
relevant ShellCheck inventory entries into this repository. The top-level
repository must not retain Nvim-focused tests or doctor checks after D4; mark
their baseline paths `d4_action=remove`. List every extracted suite exactly once in
this repository's `.github/dot-test-suites.txt`, including focused coverage
that loads and exercises the Nvim-owned doctor checks.

### 7.8 Verify editor footprint and behavior

```bash
test/run
```

Record the clean editor fixture's Nvim binary, plugin, state, and cache sizes.
Target an incremental footprint of no more than 500 MB above `base`; explain
any measured exception before D2 is considered green, and review it again
before Phase B landing.

### 7.9 Commit and open D2

Do not remove source copies from the top-level repository yet. Before every
push of extracted content, repeat the worktree/full-history scans and obtain the
fresh-eyes public-boundary review required by Task 4.1. Confirm the corresponding
D4 inventory commit is already published, pin the exact D1 head in
`.github/dot.lock`, record the exact D2 head in the coordinated commit set, and
monitor the PR to green without merging it.

---

## Task 8: Populate `dotfiles-dev`

**Repository:** `cgraf78/dotfiles-dev`

**Depends on:** Tasks 4-6 and Task 7's extension point

### 8.1 Add failing dev-owned behavior tests

Install only the dev overlay with minimal fixtures for inherited Nvim/shell
extension points and assert:

- global Git configuration is provided by this overlay;
- development Shdeps/mise dependencies are selected;
- language, formatter, linter, agent, and repository integrations are active;
- dev-owned Nvim plugin specs load without replacing editor-owned specs.

Do not assemble lower public overlays or invoke their focused suites here. The
top-level composition fixture proves that `dev` preserves `editor` and `base`
and that the real overlay stack has no path or generated-config collisions.

### 8.2 Move global Git configuration and hooks

Copy only dev-owned literal paths allowlisted by the final ownership inventory
from the exact commit in `overlay-profile-source.lock`; do not import source Git
history or read from a moving source worktree.
Move under `home/`:

```text
.config/git/
.gitleaks.toml
.local/lib/dotfiles/git-hooks/
```

Move Delta, git-tools, GitHub CLI, Difftastic, Lazygit, Sley-backed hooks, and
other advanced Git workflow dependencies into the dev dependency declarations.
Retain optional includes for personal/context Git fragments.

### 8.3 Move development configuration families

Move:

```text
.config/checkrun/
.config/direnv/
.config/gstack-register/
.config/lazygit/
.config/sley/
.vscode/
```

Move associated installation declarations, merge hooks, doctor checks, helpers,
schemas, generated-input fragments, focused tests, and component documentation
with their owning configuration/runtime.

Move public agent binaries, skills, plugins, hooks, wrappers, optional
configuration/tooling, installation declarations, focused tests, doctor checks,
and component documentation classified as `dev-agent-tooling`. Do not move the
public/base agent rule files or required `agent-rules-sync` aggregation tooling
here; Task 6 owns those. Do not alter rule fragments already owned by private
overlays.

### 8.4 Split development shell policy

Move Sley, git-tools, Direnv, Cargo/toolchain initialization, GitHub development
credentials, Lazygit wrappers, agent wrappers, and related environment settings
into dev-owned ordered shell fragments.

### 8.5 Split development dependencies

Move language toolchains, advanced Git tooling, dev-owned agent/provider
repositories, formatters, linters, LSP servers, and development-only packages
from the top-level Shdeps and mise declarations into this overlay. Keep the
required `agent-rules-sync` installation declaration with the root base.

### 8.6 Add development Nvim plugin specs

Contribute additive Lua specs/imports for:

- LSP and Mason;
- DAP;
- formatting and linting;
- language-specific integrations;
- development-only repository integrations.

Preserve only development-oriented Nvim behavior present at the frozen source
commit. This disaggregation does not introduce a Copilot integration or any
other new editor behavior. Keep large generated development metadata out of the
editor-only profile.

### 8.7 Move development merge hooks, tests, doctor checks, and docs

Move the hooks, focused suites, doctor checks, and component documentation for
Git, agents, Checkrun/Sley, development mise, VS Code, and other
development-only consumers. Preserve the existing single-source policy
boundaries with provider repositories. The top-level repository retains only
base-owned, profile/control-plane, and cross-overlay integration coverage after
D4; mark the legacy focused suite/check/doc paths `d4_action=remove`. List every
extracted public suite exactly once in this repository's
`.github/dot-test-suites.txt`, including focused coverage that loads and
exercises the dev-owned doctor checks.

### 8.8 Verify dev in isolation

```bash
test/run
```

Record clean profile size separately from language/package caches. The initial
target is 2.5-4.5 GB cumulative, with project build outputs excluded.

### 8.9 Commit and open D3

Do not include any private overlay content or documentation. Before every push
of extracted content, repeat the worktree/full-history scans and obtain the
fresh-eyes public-boundary review required by Task 4.1. Confirm the corresponding
D4 inventory commit is already published, pin the exact D1 head in
`.github/dot.lock`, record the exact D3 head in the coordinated commit set, and
monitor the PR to green without merging it.

### 8.10 Prepare PR-head public-repository acceptance in Phase A

Before each extracted-content push, scan and review the exact D2/D3 commits as
required by Task 4.1, run repository tests/CI, verify every tracked path is
allowlisted by the final ownership inventory, and normalized-compare current
repository settings from the checked-in endpoint manifest. This is PR-head
acceptance only; do not describe it as final-`main` acceptance and do not merge
either PR.

### 8.11 Perform final public-repository acceptance in Phase B

After D2 and D3 are merged, repeat the complete worktree and full-history scans
from Task 4.1 on both final `main` branches, run the repository tests/CI, and
obtain a fresh-eyes privacy review of each complete repository. Confirm every
tracked path is allowlisted by the final ownership inventory and that no
unreferenced Git object carries removed content.

Export all settings surfaces and normalized-compare them with
`cgraf78/dotfiles`. Verify public visibility, canonical MIT license text and
GitHub SPDX identity, default branch `main`, branch protection/rulesets, Actions
policy, security features, topics, and merge/general settings before D4
is authorized to land against those repository URLs.

---

## Task 9: Prepare runtime and selectors on existing machines

**Phase:** Phase B only; deferred until separate landing/rollout authorization

**Scope:** Existing installations only; complete before D4 is landed or deployed

**Depends on:** Landed/published D1 parser contract while D4 remains unmerged;
Phase A uses only sanitized isolated fixtures and must not perform this task

### 9.1 Inventory desired selections privately

Create a private exhaustive rollout ledger covering every known existing
installation without adding hostnames or inventory details to public
repositories or this plan. Every row records at least:

```text
desired_profile
selector_ready + selector evidence
runtime_ready + landed D1 commit/release + resolved executable/checkout evidence
verified pre-D4 root commit
deployment_hold status/reason/owner when not ready
```

Classify each installation:

- leave machines intended for `base` with no matching selector;
- use a machine-local exact user/host selector for unsynced local policy;
- where centrally managed private mappings are desired, keep them in
  `dotfiles-personal/dot/profile-selectors.d/` without changing that repository's
  privacy boundary;
- ensure editor and dev machines have exactly one resolved profile result and
  no conflicting root/local/personal match.

`selector_ready` is true only after that audit, including an intentional
no-selector `base` result. `runtime_ready` is independent and cannot be inferred
from the selector, installed tools, or release publication.

### 9.2 Pre-create selectors and install D1 while root remains pre-D4

On every existing non-base machine, create:

```text
~/.config/dot/profile-selectors.local.d/90-local.conf
```

when local policy is needed, with directory mode `0700`, file mode `0600`,
`version=1`, the intended `profile=`, and an exact `user=`, `host=`, or both.
Old Dot ignores this directory, so it is safe to publish before D4. Verify it is
untracked and accepted by D1's parser fixture. Do not infer a selection from
installed tools or overlay availability.

While D4 is still unmerged and deployment controls guarantee that the machine's
root checkout can reach only an approved pre-D4 commit, run the established
standalone-provider update/re-exec path. It may be initiated by old Dot, but any
base pull in this step must resolve to the recorded pre-D4 root revision. Do not
make a D4 branch/ref available to the installation yet.

After provider replacement/re-exec, verify all of the following before setting
`runtime_ready=true` in the private ledger:

- the installed standalone Dot checkout's full `HEAD` equals the exact landed
  D1 commit associated with the published release;
- the operator-visible `dot` executable resolves into that checkout and not an
  older host/Shdeps path or wrapper target;
- a fresh invocation/re-exec reports/uses the same checkout and can parse the
  sanitized profile fixtures;
- the root worktree is still at the recorded pre-D4 commit.

Record the commit, resolved executable, release identity, pre-D4 root commit,
verification time, and evidence location privately. Phase A does none of this
live-machine work.

### 9.3 Prove the old-Dot-to-new-Dot transition

In isolated fixtures representing existing installations, test the staged
handoff rather than one old-Dot-to-D4 transaction:

Use `.local/lib/dotfiles/tests/overlay-profile-rollout-test` for the sanitized
state-machine fixture. Phase A may rehearse it with immutable PR commits only;
Task 9 reruns it in Phase B with the exact landed D1 commit/release before any
live ledger row is changed.

1. start with old Dot and an approved pre-D4 root;
2. run the provider update/re-exec path while every reachable base ref remains
   pre-D4, then prove the executing checkout/executable is exact landed D1;
3. only after `runtime_ready` evidence exists, make the D4 candidate available;
4. invoke D1 to pull D4, resolve the prepared selector, and converge the
   selected profile.

Prove:

- a matching local `dev` selector preserves the previously active optional
  overlay and its managed links;
- a private personal selector becomes visible after phase-one personal sync;
- two different users on one host may resolve different profiles;
- an unavailable personal overlay keeps its advisory skip and a matching local
  selector still resolves;
- unavailable personal plus no root/local match resolves `base`;
- conflicting local/personal matches fail before final overlay relinking;
- an existing machine with no matching selector intentionally resolves `base`.

Add an interruption/retry fixture at the dangerous boundary: interrupt after
the old runtime has pulled the base but before provider replacement. Because
the deployment source is still pinned/pre-D4, the resulting root must contain
no D4 profile/descriptors. A retry under old Dot may only finish installing and
re-execing D1 against that pre-D4 root; after exact D1 verification, the harness
may release D4 and D1 performs the pull/resolution. Also attempt to release D4
while `runtime_ready=false` and require the deployment harness to fail closed
before an old-Dot invocation can process D4. At no point may old Dot parse a D4
descriptor.

### 9.4 Gate D4 deployment

Do not deploy D4 to any known existing installation until its ledger row is
resolved. Every reachable installation, including an intentional `base`
machine, must have both `runtime_ready=true` for the exact landed D1
commit/release and `selector_ready=true`. Non-base machines report one
unambiguous resolved selector from local config or a validated phase-one
personal checkout. Require a machine-local fallback where losing access to
personal could otherwise downgrade that installation.

For a temporarily unreachable installation, mark it explicitly
`deferred-unreachable`, record the missing runtime/selector evidence and
follow-up owner/action privately, and record the concrete hold mechanism,
enforcement point, verification command, observed protected revision, and
timestamp proving D4 cannot reach it. Landing/deploying D4 is allowed only when
every known row either has both readiness proofs or an explicit tested
deployment hold; never silently let automatic update reach an unverified
machine. Gate failures name the exact missing field (`runtime_ready`,
`selector_ready`, or verified hold evidence) for every unresolved row. Fresh
machines use the published D1 bootstrap and continue to receive the no-match
`base` default.

---

## Task 10: Stage profiles in the top-level `dotfiles` repository

**Repository:** `cgraf78/dotfiles`

**Depends on:** Phase A D1-D3 exact PR heads and the published D4 inventory
prefix. Task 9 is a Phase B landing gate, not a prerequisite for opening D4.

**Files:**

- Create: `.config/dot/profiles.d/base.conf`
- Create: `.config/dot/profiles.d/editor.conf`
- Create: `.config/dot/profiles.d/dev.conf`
- Create: `.config/dot/profile-selectors.d/README.md`
- Create: `.config/dot/overlays.d/20-nvim.conf`
- Create: `.config/dot/overlays.d/30-dev.conf`
- Rename: `.config/dot/overlays.d/05-personal.conf` to
  `.config/dot/overlays.d/80-personal.conf`
- Rename: `.config/dot/overlays.d/10-work.conf` to
  `.config/dot/overlays.d/90-work.conf`
- Rename: `.config/dot/overlays.d/10-work.ssh` to
  `.config/dot/overlays.d/90-work.ssh`
- Modify: `.config/dot/overlays.d/README.md`
- Modify: `.config/dot/README.md`
- Modify: `.local/share/doc/dotfiles/dotfiles.md`
- Modify: `.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns.gitignore`
- Modify: `.local/lib/dotfiles/pre-sync.d/10-overlay-ssh.sh`
- Modify: `.local/share/doc/dotfiles/overlay-profile-baseline-disposition.tsv`
- Modify: `.local/share/doc/dotfiles/overlay-profile-final-ownership.tsv`
- Modify: `.local/lib/dotfiles/tests/overlay-profile-ownership-test`
- Create: `.github/dot-test-suites.txt`
- Create: `.github/overlay-profile-stack.lock`
- Modify: `.github/workflows/test.yml`
- Create: `.local/lib/dotfiles/tests/run-ci`
- Create: `.local/lib/dotfiles/tests/measure-profile-footprint`
- Create: `.local/lib/dotfiles/tests/footprint-test`
- Create: `.local/lib/dotfiles/tests/overlay-profile-stack-test`
- Create: `.local/lib/dotfiles/tests/stack-dot-runtime`
- Create: `.local/lib/dotfiles/tests/overlay-profile-rollout-test`
- Add focused profile/overlay integration tests under
  `.local/lib/dotfiles/tests/`

### 10.1 Write failing configuration tests

Assert the exact profile graph:

```text
base   -> personal
editor -> base,nvim
dev    -> editor,dev,work
```

Assert `personal` and `work` remain optional, `nvim` and `dev` are required, the
root repository is always active without an overlay descriptor, and the local
selector directory is ignored by the base Git worktree.

Test user-only, host-only, combined, same-host/different-user, host
normalization, no-match/base fallback, agreeing duplicates, conflicting
profiles, unavailable personal with local fallback, and unavailable personal
with base fallback. Use generic placeholder identities only.

Add a fixture in which `dev` selects the optional work descriptor but its SSH
transport is unavailable. The profile must still converge `nvim` and `dev` on
top of the root base, record the optional skip, and return success.
Assert the work record is selected and eligible, so pre-sync sees its generic
companion before availability, but it is not active and therefore is absent
from merge/component-doctor contexts. In a sanitized later-available variant,
the prepared companion enables synchronization and only then does the record
enter the active set.

Add a sanitized transition fixture proving a descriptor and its same-stem SSH
companion move together from one numeric precedence prefix to another. Verify
the new descriptor discovers the renamed companion and the managed transport
block is preserved without embedding any real host, key, or topology detail.

Add an upgrade fixture with pre-existing generic dev/work managed SSH blocks.
Phase-one `prepare` receives only current base-phase eligible descriptors and
must preserve those unmentioned blocks. Inject a selector conflict and a
malformed selected descriptor in separate runs and prove neither failure prunes
them. Then resolve successfully to `base` and `editor` and prove only final
`reconcile` removes the now-deselected family entries; inspect the context to
ensure no stale dev/work descriptor was passed merely to preserve state.

Add bounded composition fixtures that assemble the real public overlays but do
not invoke their focused suites. Assert that `editor` preserves the base
contract, `dev` preserves the base and editor contracts, overlay paths and
generated fragments do not collide unexpectedly, and the expected component
suite/check files appear only when their owning overlay is active.
During D4, assert every temporary duplicate dependency/install declaration is
listed by the baseline table and aggregates idempotently without installing or
running the same provider twice.

Add fixture-construction tests for Task 10.5: the ephemeral candidate excludes
only the tracked Nvim/dev production descriptor copies, exposes generated
`sync=none` descriptors at the canonical filenames, contains exactly one
descriptor for each logical name, and cannot reach a public remote. Separately
assert the immutable checkout's tracked descriptors retain the reviewed public
URLs/`main` targets, reject local/test fields, remain byte-identical before and
after the run, and are absent from the convergence tree.

Add sanitized pull-request event fixtures for the D5 stack gate. The exact
locked D4 base ref/SHA plus matching merge base passes. A wrong base ref, an
event base SHA that advanced to a descendant while the old merge base still
matches, and a true merge-base mismatch each fail independently.

Add top-level transport-spy integration fixtures proving inspection commands do
not invoke the pre-sync transport worker or Git network operations, and that
`fetch`/`push` act only on selected repositories present before the command.

Add runtime-selection tests for `stack-dot-runtime`: place a failing fake host
`dot` earlier in the incoming PATH, expose a mismatched installed/release Dot,
and simulate an incidental shared-workflow setup. Every Phase A group must still
resolve the exact locked checkout executable and matching HEAD; a missing or
mismatched lock/checkout/runtime marker must fail before the group body runs.

### 10.2 Add descriptors and profile definitions

Use official public repository URLs for the two capability overlays. Keep
the work descriptor and all references to it generic; do not add private
implementation notes.

Update `.local/lib/dotfiles/pre-sync.d/10-overlay-ssh.sh` in the same staging PR
to consume only the eligible `OVERLAYS` records and validated `prepare` or
`reconcile` stage supplied by Task 2.4. `prepare` upserts supplied phase-one
blocks without pruning; `reconcile` replaces the full family after final
validation. This prevents the new `base` default from reading or merging
transport inputs for an unselected/ineligible overlay while avoiding premature
removal before selectors resolve.

Record both the old descriptor/companion paths in the baseline table and both
new same-stem paths in the final ownership table under one stable component ID.

### 10.3 Add selector documentation and exact ignore rule

Document machine-local creation of:

```text
~/.config/dot/profile-selectors.local.d/<name>.conf
```

Document root tracked selectors and repository-only personal selector fragments,
including two-phase resolution, all-fields-match semantics, conflict failure,
normalization, same-host/different-user behavior, and no-match `base` fallback.
Document the generic Phase B requirement that existing installations verify
the landed D1 runtime on a pre-D4 root before D4 exposure; keep the actual
runtime/selector readiness ledger private.
Do not add environment overrides or profile-management commands.

Add this exact tracked ignore pattern to
`.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns.gitignore`:

```gitignore
/.config/dot/profile-selectors.local.d/
```

Test it with
`git check-ignore -v .config/dot/profile-selectors.local.d/90-local.conf`
against both supported base repository topologies: the legacy bare repository
and the non-bare Git directory with explicit `core.worktree`.

### 10.4 Preserve the monolith during staging

Use the baseline disposition inventory to make the staging boundary explicit:

- retain legacy Nvim/dev config/runtime and dependency/install declarations
  whose D4 action is `keep` and D5 action is `remove`/`rewrite`, so rollout can
  still be staged safely before the destructive runtime cutover;
- remove every extracted component-focused test, component doctor check, and
  component-only document whose D4 action is `remove` as soon as D2-D3 CI owns
  it;
- retain permanent profile/control-plane tests, lifecycle doctor reporting, and
  integration documentation plus base-focused tests/doctor/docs marked `keep`.

This lets operators place local selections and lets the new overlay
repositories prove installation without leaving executable editor/dev test or
doctor surfaces visible on a `base` machine.

### 10.5 Pin and assemble the prospective unmerged stack

Implement the lock, checkout, ephemeral-tree construction, descriptor
uniqueness, production-descriptor validation, and transport-spy assertions in
`.local/lib/dotfiles/tests/overlay-profile-stack-test` so local and CI runs use
one implementation.

Store full immutable commit IDs for the frozen source-dotfiles revision and the
reviewed D1, D2, and D3 PR heads in `.github/overlay-profile-stack.lock`. Also
pin the released Shdeps commit/tag pair used only to provision an isolated
control-plane test HOME, plus the immutable installer revision used to fetch
that release and the exact base-owned `agent-rules-sync` provider revision.
These are CI prerequisites, not profile capabilities. The
ownership/integration test verifies each ID is a commit in the declared
repository, that `source_dotfiles` equals `overlay-profile-source.lock` and the
`commit=` value in both capability `.github/dotfiles-source.lock` files, and
that D2/D3 `.github/dot.lock` both equal the recorded D1 commit. It also verifies
both capability source records retain
`repository=cgraf78/dotfiles`/`license_path=.github/LICENSE`. Any head update
invalidates green status until the coordinated lock is refreshed and every
consumer reruns.

Use a deliberately small machine-readable format:

```text
version=1
source_dotfiles=<40-or-64-hex-commit>
dot=<immutable-D1-head>
dotfiles_nvim=<immutable-D2-head>
dotfiles_dev=<immutable-D3-head>
test_shdeps=<immutable-released-Shdeps-commit>
test_shdeps_release=<matching-Shdeps-release-tag>
test_shdeps_installer=<immutable-Shdeps-installer-commit>
test_agent_rules_sync=<immutable-agent-rules-sync-commit>
dotfiles_d4_base_ref=<published-D4-branch-name>
dotfiles_d4_base=<immutable-D4-head-on-which-D5-was-created>
```

Omit both `dotfiles_d4_base_ref` and `dotfiles_d4_base` in D4 and require both
in D5. Validate the ref as an exact branch name without a `refs/` prefix.
Reject duplicate/unknown-for-this-phase keys, abbreviated object IDs in commit
fields, or revisions that do not resolve to commits fetched from the declared
repository.

Implement `.local/lib/dotfiles/tests/stack-dot-runtime` as the only Phase A
D4/D5 entry point for any command that executes standalone Dot. It reads the
`dot=` commit from the stack lock, checks out exactly that commit into a bounded
isolated runtime directory, verifies the checkout origin and full HEAD, exposes
that checkout's `bin/dot` in an isolated XDG data root, prepends its `bin/` to a
controlled `PATH`, clears the shell command hash, and verifies both
`command -v dot` and `git -C "$runtime_repo" rev-parse HEAD` before launching a
named verification group. The wrapper exports the expected runtime path/SHA;
`run-ci` and fixture helpers refuse to run in Phase A if the marker, executable,
origin, or HEAD assertion is absent or mismatched.

Every Phase A D4/D5 group runs through that wrapper independently:

```text
control-plane-run-ci
ownership-and-stack-integration
profile-fixture-update
profile-doctor
installed-profile-dot-test (D5 Ubuntu CI plus local/end-to-end)
reproducible-cold-bootstrap
profile-footprint-fixtures (when they invoke Dot)
```

Reassert HEAD/PATH immediately before each group, not once per job. Invoke the
locked checkout's executable directly or through the verified PATH; never use
the top-level `.local/bin/dot` launcher, a host/Shdeps-installed Dot, a latest
or released version, a public shortcut, or the incidental runtime supplied by
`setup: dotfiles`. Phase A must fail if any command resolves a different Dot.
Run `overlay-profile-ownership-test` and `overlay-profile-stack-test` through
the `ownership-and-stack-integration` group even when a particular assertion is
pure shell, so the complete integration gate records one consistent D1 runtime.

In D4 and D5 CI, check out D1-D3 at those exact commits into bounded temporary
directories and check out the current D4/D5 PR head SHA supplied by the
pull-request event rather than a synthesized merge ref. Construct the
prospective root in a second ephemeral directory from that immutable D4/D5
checkout. Copy the candidate tree while deliberately excluding only these two
tracked files from the ephemeral copy:

```text
.config/dot/overlays.d/20-nvim.conf
.config/dot/overlays.d/30-dev.conf
```

Then generate test-only files at those same canonical paths and logical names
inside the ephemeral tree. Each generated descriptor uses `sync=none` and the
exact checked-out D2 or D3 path. Do not create `.local.conf` aliases or any
second filename for either logical name. Before convergence, enumerate visible
descriptor filenames and assert exactly one `nvim` and one `dev` descriptor,
assert neither tracked production descriptor inode/path is reachable through
the fixture, and install transport spies that fail on clone/fetch/pull or any
attempt to contact a bootstrap/moving `main`.

The exclusion and replacement are permitted only in the disposable fixture
copy. Never remove, edit, overwrite, or generate into the immutable D4/D5
checkout. Hash and parse the tracked production descriptors there separately
before and after the integration run; require their canonical logical names,
required-overlay semantics, official public repository URLs, and eventual
public `main` targets, and reject `sync=none`, local paths, PR refs, or fixture
content in those tracked files. Also assert the immutable checkout remains
clean after the run.

For D5, read the pull-request event rather than a locally guessed branch. Require
all three conditions:

1. `pull_request.base.ref` exactly equals the locked
   `dotfiles_d4_base_ref` published D4 branch name;
2. `pull_request.base.sha` exactly equals the locked `dotfiles_d4_base` commit;
3. `git merge-base <d5-head> <pull_request.base.sha>` exactly equals that same
   locked commit.

Fetch and verify the event's base SHA before the merge-base call. Do not infer
the stack from a generic parent, since D5 may contain multiple commits. Any D4
branch update invalidates D5 immediately; rebase D5 onto the new exact D4 head,
refresh both locked base fields, and rerun both PRs.

Production descriptors continue to point at the eventual public `main`
repositories. They are immutable inputs validated separately during Phase A,
not the source used by prospective-stack convergence until Phase B has landed
the capability PRs.

### 10.6 Restrict top-level public CI to base and control-plane coverage

Create the literal `.github/dot-test-suites.txt` inventory containing base-owned
focused suites plus profile/control-plane, ownership, overlay-composition,
migration, and bounded fixture integration suites. Add `run-ci` to validate the
inventory and invoke `dot test` with exactly those suite names. Update
`.github/workflows/test.yml` to call `run-ci`; do not invoke unfiltered
`dot test` in top-level public CI after capability suites have moved.

For D4/D5 Phase A PR jobs, call the reusable shared workflow with `setup: none`
and only the prerequisite tool profiles needed by the repository. Check out the
exact D1 commit from `.github/overlay-profile-stack.lock`, then invoke `run-ci`
through `stack-dot-runtime control-plane-run-ci`. Do not use `setup: dotfiles`:
its installed Dot is incidental and cannot satisfy the unmerged D1 contract.
Make `run-ci` verify the wrapper's runtime marker/HEAD before its first test and
again immediately before its selected `dot test` invocation.

Cross-check the top-level inventory against the two public overlay inventories
and both ownership tables. Fail for duplicate suite names, duplicate baseline
source rows, duplicate final `(repository,destination_path)` keys, an unlisted
executable top-level suite, a capability-focused suite or component doctor
extension remaining anywhere in the top-level tree, or a component suite/check
whose final-inventory owner differs from its overlay. The composition job reads
the D2-D3 suite inventories from the exact commits in
`.github/overlay-profile-stack.lock` to validate ownership and uniqueness but does not
execute the named suites. Capability repositories run their extracted suites in
their own CI only. Public CI does not execute private-overlay test suites.

The scheduled cold-bootstrap job may verify profile convergence, doctor
lifecycle state, and bounded composition smoke assertions, but it must not run
the overlay-owned behavioral suites again. Invoke `run-ci` or an explicit
top-level composition subset there through
`stack-dot-runtime reproducible-cold-bootstrap`. The locally reproducible
cold-bootstrap command uses the same exact D1 checkout and asserts it before
bootstrap starts.

D5 also adds one Ubuntu-only production-equivalent integration job named
`installed-profile-dot-test`. It creates isolated `base`, `editor`, and `dev`
homes and runs real, unfiltered `dot test` in each. This is deliberately one
platform integration gate rather than a second full OS matrix: the owning
public repositories retain their broad platform matrices for component-specific
behavior, while this job proves final profile composition without multiplying
the complete three-profile suite across every runner OS. Add a targeted
platform smoke later if evidence identifies an OS-specific composition gap.

During D4 staging, this gate runs real unfiltered `dot test --list` discovery
in each installed profile but does not execute the discovered overlay suites.
D4 intentionally retains the monolith payload scheduled for D5 removal, while
each capability suite already enforces its standalone post-cutover boundary;
executing those suites against the pre-cutover D4 tree would therefore test an
invalid hybrid state. D5 runs the full unfiltered installed `dot test` after
the remaining remove/rewrite actions establish the final composed tree.

### 10.7 Add repeatable footprint measurement and capture the baseline

Create `measure-profile-footprint` to accept an isolated fixture HOME and emit
sorted machine-readable byte counts for Git checkout/config payload,
user-managed binaries/repositories, native package payload where measurable,
Nvim plugins/state/cache, mise installs, and language/package caches. Report
host package-manager stores, workload caches, and optional private overlay
payloads separately from the public profile total. The `base` total includes the
always-active root `dotfiles` checkout and base-owned installed artifacts, not a
separate public base overlay. Canonicalize paths and use byte counts rather than
human-formatted input.

Add `footprint-test` to run the same script for clean `base`, `editor`, and
`dev` fixtures, validate category completeness, and prove that repeated
measurement of an unchanged fixture is identical. Record each D4 result as
`phase=pre-cutover-monolith`; it is a comparison baseline that is expected to
include the baseline inventory's D5 removal/rewrite paths, not evidence that final base or
profile budgets have been achieved. Enforce the final absence and footprint
targets only in D5.

### 10.8 Verify staging

Run:

```bash
.local/lib/dotfiles/tests/stack-dot-runtime control-plane-run-ci -- \
  .local/lib/dotfiles/tests/run-ci
.local/lib/dotfiles/tests/stack-dot-runtime profile-doctor -- dot doctor
```

Separately run `profile-fixture-update` and the local/end-to-end-only
`installed-profile-dot-test` group through the same wrapper in isolated
`base`, `editor`, and `dev` fixture homes to prove convergence and
active-overlay aggregation. Assert that unfiltered
`dot test --list` on `base` discovers the always-active top-level base/control
suites plus suites from available selected private overlays; editor/dev suite
names appear only when their owners are active. This D4 assertion is
discovery-only for the staging reason in Task 10.6; full unfiltered installed
suite execution is a D5 verification requirement. Make the parallel
assertion for `dot doctor`: no Nvim/dev component check is discovered on
`base`, while top-level profile/overlay lifecycle reporting remains available.
Use the baseline inventory to assert that any remaining Nvim/dev
config/runtime/dependency declarations are exactly the known D5
remove/rewrite set; do not assert
final base absence or final profile footprint in D4.
Confirm the live source checkout remains unchanged outside the feature
worktree. CI must print the coordinated commit set and prove the prospective
stack was assembled exclusively from those exact commits. It must also print
the ephemeral descriptor inventory, prove canonical-name uniqueness, show that
the tracked production descriptors were excluded only from the disposable
tree, and verify the immutable checkout hashes/config remained unchanged.
For every printed verification group, include the asserted D1 runtime path and
HEAD from the stack lock.

### 10.9 Commit and open D4

Open D4 against `cgraf78/dotfiles:main` using the exact unmerged D1-D3 heads and
test-only descriptors from Task 10.5. Record explicit dependencies in the PR
body/labels and block merge. Monitor checks to green, but do not land it or
change any live selector in Phase A. Phase B later requires Task 9, final
capability-main acceptance, and any necessary D6/D7 resolution before landing.

---

## Task 11: Validate `dotfiles-personal` without splitting it

**Repository:** `dotfiles-personal`

**Depends on:** D4 candidate fixture. Audit in Phase A; any landing is Phase B.

Both private overlays are expected to remain largely unchanged. Open D6 or D7
only when this audit finds a concrete compatibility or ownership defect. Do not
restructure a private repository merely to implement profile selection;
optional availability and graceful skipping belong to standalone Dot and the
public descriptors.

### 11.1 Run the personal overlay against `base`

Use a temporary base-profile home and the personal overlay checkout. Verify:

- its linked payload remains small;
- Grafhome CA and Smallstep client policy converge normally;
- host-only CA components remain host-filtered;
- personal SSH and DS configuration remain functional;
- any existing private selector mappings stay under
  `dot/profile-selectors.d/`, parse with the public schema, and produce no
  conflicting match for the audited user/host identities;
- optional editor/dev settings remain inert when their owning public hook or
  command is absent;
- the shell starts when optional personal commands are absent;
- personal tests do not require the `editor` or `dev` profile.

### 11.2 Fix only concrete failures

If a personal file actively requires an absent higher-profile tool, either add
a narrow presence guard or move that fragment into an appropriate capability
integration. Do not create `personal-editor` or `personal-dev` without a
measured need. Preserve all existing personal rule/config/test/doctor ownership.

### 11.3 Verify personal tests

Run the overlay's complete test set plus the top-level base-profile fixture.
If the ownership inventories find a personal-component focused test, doctor
check, or component document still in the public top-level repository, move it
to `dotfiles-personal` with its owning config/runtime instead of leaving public
CI to exercise it.
If no source change is required, record the successful validation in D4's test
plan rather than opening an empty PR. If D6 is required, open it and monitor it
to green in Phase A without merging it; Phase B lands it before D4 removes the
public legacy verification/documentation path.

### 11.4 Validate the optional work-overlay contract privately

Without copying filenames, tool names, host data, or implementation details
into public artifacts, verify that the optional overlay selected by `dev`
retains graceful unavailable-remote behavior and owns any focused tests and
doctor checks for its own components. Its existing private-repository CI policy
remains unchanged; public dotfiles CI must neither run nor replace those private
suites. The overlay may assume the `dev` profile and should otherwise retain its
existing rule/config/test/doctor ownership and privacy boundaries.

---

## Task 12: Cut over the top-level repository to the overlays

**Repository:** `cgraf78/dotfiles`

**Phase A dependency:** Green exact D1-D3 PR heads plus the published D4 branch.
Create D5 from the D4 branch and open it with that branch as its PR base.

**Phase B landing dependency:** D1-D4 and any required D6/D7 landed, final
capability-main acceptance complete, and D5 retargeted/rebased onto `main`.

### 12.1 Add failing absence/ownership tests

Before deleting files, extend the machine-checkable ownership test to assert
that the top-level base/control-plane repository no longer owns any
capability-assigned path and that each clean profile receives the exact declared
destinations from its overlay manifest. Fail for a missing destination, a
duplicate `(repository,destination_path)` key, any baseline D4 removal that
survived staging, any baseline D5 removal/rewrite that would survive cutover, or
any final tracked path absent from the final ownership inventory. Do not reject
the same relative metadata path when it belongs to different repositories.

### 12.2 Finalize the always-active base substrate

Keep all `owner=dotfiles` paths in the root repository. Finish the shell, tmux,
ripgrep, mise/Shdeps, and other fragment boundaries so base references only
base-owned commands. Keep raw Git only for Dot bootstrap, with global Git config
owned by dev. Keep the existing public/base agent rule files,
`agent-rules-sync` machinery, and their focused tests/doctor/docs in root. Do
not alter personal/work rule ownership.

Create `.local/lib/dotfiles/tests/base-profile-boundary-test` only in D5 and add
it to the top-level `.github/dot-test-suites.txt`. In a controlled PATH and
clean base fixture, assert raw Git remains available while Nvim, global Git
configuration, dev-owned agent tooling/configuration, development mise tools,
and development hooks are absent.

### 12.3 Remove editor-owned files from the top level

In the Phase A D5 fixture, remove only after exact pinned D2 is available and
selected by `editor`. Verify Nvim config,
hooks, and fragments resolve from `dotfiles-nvim`; its focused tests and doctor
checks already moved in D4.

### 12.4 Remove dev-owned files from the top level

In the Phase A D5 fixture, remove only after exact pinned D3 is available and
selected by `dev`. Verify Git config,
development dependencies, hooks, and agent configuration resolve from
`dotfiles-dev`; its focused tests and doctor checks already moved in D4.

### 12.5 Keep only base and control-plane behavior

The top-level repository should retain:

- the complete always-active base environment and its focused tests/doctor/docs;
- `.config/dot/config`;
- profile definitions;
- overlay descriptors and pre-sync transport preparation;
- Dot launcher/bootstrap policy;
- profile/control-plane tests, cross-overlay composition/lifecycle tests, and
  public integration documentation;
- no tool configuration merely because the tool is used to implement Dot.

Remove/rewrite only the remaining legacy Nvim/dev config/runtime and
dependency/install declaration paths scheduled by the baseline D5 actions; D4
already removed extracted focused tests, component doctor checks, and
component-only documentation. Do not leave a top-level test
aggregator that has to understand inactive tools; installed `dot test`
discovers tests contributed by the active-overlay manifest.

### 12.6 Test all three clean profiles

For each profile, create a new temporary HOME and run:

```bash
.local/lib/dotfiles/tests/stack-dot-runtime profile-fixture-update -- dot update
.local/lib/dotfiles/tests/stack-dot-runtime profile-doctor -- dot doctor
.local/lib/dotfiles/tests/stack-dot-runtime installed-profile-dot-test -- dot test
```

Each invocation uses the exact D1 commit in the D5 stack lock and a profile-
specific isolated XDG root; no result from a host-installed or released Dot is
accepted in Phase A.

Assert:

- `base` has raw Git but no global Git config and no Nvim;
- `editor` adds Nvim but not development Git configuration, Mason, LSP, DAP,
  or development toolchains;
- `dev` includes the full editor and development configuration;
- optional unavailable personal/work overlays do not fail convergence;
- a `dev` machine without credentials for the selected optional work overlay
  converges successfully and retries that overlay on later updates;
- switching downward removes deselected managed links and restores shadowed
  files without deleting cached repositories or native packages.

### 12.7 Measure profile footprints repeatably

Re-run the D4 `measure-profile-footprint` script against clean post-cutover
fixtures through `stack-dot-runtime profile-footprint-fixtures` whenever setup
or measurement invokes Dot, and compare the same separately reported
categories:

- Git checkout/config payload;
- user-managed binaries and repositories;
- native package payload where measurable;
- Nvim plugins/state/cache;
- mise installs;
- language/package caches.

Compare against the recorded D4 baseline and explain unexpected growth by owner
and category. Keep host package-manager stores and workload caches outside the
profile total, and report optional private overlay payloads separately so access
differences do not distort base/editor/dev comparisons.

Initial acceptance targets:

```text
base:   <= 500 MB fresh on representative Linux
editor: <= 500 MB incremental over base
dev:    2.5-4.5 GB cumulative before project build outputs
```

Treat platform package-manager differences as reported context, not as a reason
to weaken ownership boundaries.

### 12.8 Run repository verification

```bash
checkrun format
checkrun lint
.local/lib/dotfiles/tests/stack-dot-runtime control-plane-run-ci -- \
  .local/lib/dotfiles/tests/run-ci
.local/lib/dotfiles/tests/stack-dot-runtime profile-doctor -- dot doctor
```

Run the locally reproducible steps from `.github/workflows/test.yml`, including
the cold-bootstrap equivalent through the locked
`reproducible-cold-bootstrap` runtime group where practical. Confirm each public capability
repository's own CI has run its `.github/dot-test-suites.txt` exactly once, then
run `installed-profile-dot-test` through the locked wrapper in each clean
active-profile fixture.
Explicitly assess macOS and Termux compatibility. Ignore only the known GitHub
Actions billing failure; do not waive local failures.

### 12.9 Commit and open D5

Use a fresh-eyes review focused on missing files, profile leakage, downgrade
cleanup, public/private boundaries, and bootstrap recovery. Publish the D4
feature branch first, create D5 from its exact head, and open D5 with the D4
branch as its PR base. Add a dependency label/check and PR text that blocks D5
until D4 lands. Run D5 integration CI against the exact commit set in
`.github/overlay-profile-stack.lock`; require its locked base-ref, exact event
base-SHA, and merge-base checks from Task 10.5, then monitor it to green without
merging.

In Phase B, after D4 merges, retarget/rebase D5 onto `main`, update its base and
all coordinated locks to the landed immutable commits, rerun source
reconciliation if the root base changed, and repeat every D5 check before
merge. Never test or merge D5 by silently substituting moving branch names.

---

## Phase B Landing Gates and Order

Do not execute this section without separate authorization.

1. Re-review and land D1 through the standalone Dot repository's normal path;
   publish the required release, record the final immutable commit, and add a
   separate released-runtime bootstrap assertion. This Phase B check does not
   replace or retroactively weaken Phase A's exact PR-head runtime checks.
2. Update D2/D3 `.github/dot.lock` and the D4/D5 coordinated stack lock from
   the Phase A D1 head to the final D1 commit; rerun all affected CI.
3. Land D2/D3 after their exact heads are green, then perform Task 8.11 against
   the final `main` histories and immediately repeat normalized settings/license
   acceptance.
4. While D4 remains unmerged, complete Task 9's exhaustive private rollout
   ledger: install/verify exact landed D1 on every reachable existing machine,
   prepare/verify its selector result, and prove both `runtime_ready` and
   `selector_ready`. Install a tested deployment hold for every unreachable or
   otherwise incomplete row. Do not let D4 reach any unresolved row.
5. Land any required D6/D7, then refresh the D4 integration lock to the final
   D1-D3 commits and rerun the complete prospective-stack checks.
6. Land D4 only after its rollout gate is satisfied. Retarget/rebase D5 from
   the published D4 branch onto the resulting `main`; if the root base commit
   changed, execute Task 5.5's full source reconciliation.
7. Refresh all D5 locks, rerun final ownership/absence/footprint/integration
   checks, land D5, and only then perform Task 13 fleet rollout.

Final-main scans, final repository settings comparison, live selectors, D1
release publication, merges, and fleet convergence all belong to Phase B.

---

## Task 13: End-to-end rollout verification

**Phase:** Phase B only; deferred until separate landing/rollout authorization

**Depends on:** All required PRs landed

### 13.1 Force one full convergence per representative profile

```bash
dot update -f
dot doctor
dot test
```

Verify the installed/generated targets, not only overlay source files.

### 13.2 Exercise upgrades and downgrades

In isolated homes, test:

```text
base -> editor -> dev -> editor -> base
```

At every transition verify overlay links, generated config, shell startup,
doctor output, tests, and preservation of unmanaged files.

### 13.3 Test clean bootstrap

Run a clean Linux bootstrap with no selector and prove it receives `base`.
Repeat with local `editor` and `dev` selectors present before convergence.
Use the landed/published D1 release in this Phase B test and verify it maps to
the recorded final D1 commit. Keep this distinct from the Phase A wrapper,
which must continue to use the unmerged stack-lock commit while PR checks run.

### 13.4 Check platform compatibility

Run or obtain CI coverage for:

- Linux;
- macOS with Bash 4+;
- WSL where applicable;
- Android/Termux for supported base/editor paths.

### 13.5 Perform final fresh-eyes reviews

Review separately for:

- profile parser and update lifecycle correctness;
- overlay ownership and stale-link cleanup;
- missing cross-profile command references;
- public/private boundary violations;
- profile footprint regressions;
- test and CI gaps.

### 13.6 Publish final operator documentation

Update `.local/share/doc/dotfiles/dotfiles.md` with the final repository map,
profile files, manual selection instructions, troubleshooting, and recovery.
Document the existing-machine `runtime_ready` plus `selector_ready` gate and
the rule that D1 must be verified while root remains pre-D4.
Keep the documented interface configuration-only until repeated operator need
justifies dedicated profile commands.

## Phase A Definition of Green

- The reviewed public bootstrap repositories exist with only their skeleton
  commits on `main`; the default-settings interval is timestamped, settings are
  immediately mirrored/compared, and no contribution was accepted during it.
- D1-D5 are open and unmerged. D6/D7 are open only if a concrete compatibility
  defect required a change. No standalone Dot release was published and no
  live selector or installation was changed.
- D1 worker-context tests prove phase-one/final context routing, eligible
  pre-sync and active merge/component-doctor execution, unread unselected
  descriptors, stale-manifest rejection, a real six-field codec roundtrip,
  fixed-field/NUL/trailing-data validation, and
  tamper/symlink/ownership/mode/lifetime failure handling.
- Pre-sync context stage validation permits only eligible `prepare`/`reconcile`
  combinations. Phase-one prepare preserves unmentioned managed-family entries
  through selector/descriptor failure without passing stale descriptors; only a
  successfully validated final reconcile prunes deselected/ineligible entries.
- The frozen source-dotfiles SHA was recorded and published on the D4 branch
  before either capability bootstrap commit/repository was created. The
  baseline exactly matches `git ls-files` at that commit, and every D2/D3
  extraction came only from that revision after its D4 inventory rows were
  published.
- Both capability `.github/dotfiles-source.lock` commits and the stack lock's
  `source_dotfiles` exactly equal the root source lock. Each root `LICENSE` is a
  local byte copy of `.github/LICENSE` at that commit, and immutable-ref remote
  byte comparison plus both `MIT` SPDX checks pass with trap-based audit cleanup.
- Each capability harness asserts the supported no-base-repository topology:
  its synthetic config root is not a Git worktree, Dot reports no base client,
  and the capability checkout is used only by its canonical `sync=none`
  descriptor.
- D2/D3 pin the exact reviewed D1 head. D4/D5 pin exact D1-D3 heads, assemble
  the prospective stack from an ephemeral candidate copy with only canonical
  test-only `sync=none` Nvim/dev descriptors visible, and
  run from their exact PR head SHAs; D5 also pins and matches the exact D4 PR
  base ref name and event base SHA, with the same SHA as its merge base. The jobs
  fail closed instead of using skeleton `main`, synthesized merge refs, or
  moving branches.
- D4/D5 integration proves exactly one visible descriptor per public capability,
  no network access, and no mutation of the immutable checkout; separate
  production-descriptor validation proves the tracked URLs/`main` targets are
  unchanged and contain no fixture fields.
- Every D4/D5 Phase A group that executes Dot records the exact stack-locked D1
  runtime path and HEAD immediately before running. `run-ci`, profile updates,
  doctor, installed `dot test`, ownership/integration, footprint setup, and
  reproducible cold bootstrap reject host/latest/release or incidental
  `setup: dotfiles` runtimes.
- Each capability workflow polls and verifies only its own license/SPDX state;
  after both exist, the coordinator condition-polls both licenses and normalized
  settings to a bounded deadline with failure diagnostics.
- D5 is opened against the published D4 branch, shows only cutover changes, and
  both PRs are explicitly dependency-blocked from merge with a documented
  Phase B retarget plan.
- Every available local and CI check is green on the exact recorded heads;
  public-boundary scans/reviews cover every pushed extracted-content commit.
  Final-`main` acceptance and fleet checks are intentionally not claimed.

## Phase B Completion Criteria

- A clean install with no matching selector converges the always-active root
  plus the `base` profile's available optional overlays.
- The root `dotfiles` repository is always active and never appears as a
  selectable overlay; `base` selects only the optional personal overlay.
- `editor` is exactly the always-active root plus `base` and the Nvim overlay.
- `dev` is exactly `editor` plus the dev and optional work overlays.
- Profiles aggregate profiles additively and cycles fail before mutation.
- Selector records match exact normalized user/host identity, require every
  supplied field, support distinct users on one host, reject conflicting
  matching profiles, and default to `base` when nothing matches.
- Machine-local selectors are untracked config files; tracked private mappings
  may remain in `dotfiles-personal` outside `home/`.
- Base may track profile definitions and root selectors, but every repository
  candidate rejects files, directory entries, and symlinks below
  `.config/dot/profile-selectors.local.d/`; the exact Git ignore remains a
  separate defense.
- Resolution synchronizes root/base and optional personal first, then loads
  eligible root/local/personal selectors before parsing or synchronizing any
  non-base selected additions. Personal with no usable checkout preserves its
  advisory skip and falls back to local/root selection or `base`.
- `status`, `diff`, `doctor`, and `test` resolve exclusively from existing
  validated state and perform no network activity. `fetch` fetches only selected
  existing repositories plus root without cloning or updating worktrees;
  `push` performs no preparatory clone/pull/fetch and pushes only root plus
  selected existing repositories.
- A profile containing only non-empty parents is valid; explicitly empty lists,
  memberless profiles, and completely empty expansion are invalid.
- No unselected overlay is cloned, pulled, linked, component-tested,
  component-diagnosed, or included in repository status/diff/push operations;
  doctor may report only its filename-derived `not selected` lifecycle state.
- Unselected descriptor contents and SSH companions are not read; only safe
  filename identity/ambiguity validation occurs before selection.
- Every isolated pre-sync, merge, and doctor worker receives a one-use private
  structured context containing the coordinator's exact eligible or active
  overlay records. The dedicated versioned codec validates and reconstructs
  exactly six fields (`name`, `path`, `url`, `descriptor`, `optional`, `sync`)
  per record; the installed-link manifest parser remains separate. Workers
  validate/unlink that context, never enumerate `overlays.d`
  or re-resolve selectors, and require passed-set owner membership for
  overlay-owned extensions in addition to existing checkout/origin/extension
  trust validation. Stale manifests and
  malformed unselected descriptors cannot authorize or disrupt a worker.
- Phase-one/final pre-sync receives eligible records before availability,
  including selected optional unavailable overlays; merge and component doctor
  receive only active validated records. Selected-ineligible companions remain
  hidden, while lifecycle doctor reports selected-ineligible/unavailable state.
- The worker validates mode/set/stage combinations and exposes structured
  `prepare`/`reconcile` state to pre-sync extensions. Prepare never prunes
  unmentioned managed-family entries; final reconcile runs only after complete
  selector/profile/selected-descriptor validation and is the sole stage allowed
  to remove deselected or ineligible transport blocks.
- Descriptor prefix changes rename the same-stem SSH companion in the same D4
  change and preserve its managed transport block.
- A selected `optional=true` overlay retains existing graceful-skip behavior
  when credentials or network access are unavailable; profile membership never
  turns that condition into a failure.
- The root base remains the lowest layer, and descriptor ordering remains the
  only precedence order among additional overlays.
- Doctor distinguishes `not selected`, `selected but ineligible`, `selected
  optional but unavailable`, and `active` from structured state.
- Base has raw Git for Dot but no global Git configuration.
- Base shell startup does not reference Nvim or development commands.
- Editor Nvim does not install development tooling through Mason or another
  fallback.
- Dev adds advanced Git, language, agent, and Nvim development integrations.
- Agent binaries, skills, plugins, hooks, wrappers, and other tooling are
  dev-owned unless they are the `agent-rules-sync` machinery required solely to
  aggregate/synchronize/apply rules. Agent rule files currently owned by the
  public base repo and that required machinery remain root-dotfiles-owned, with
  matching focused tests, doctor checks, and docs; existing private rule
  fragments do not change owners.
- `dotfiles-personal` remains usable as a lightweight optional base overlay.
- Every public component's install declaration, config/runtime, focused tests,
  doctor checks, and component docs share one repository owner recorded in the
  exhaustive final ownership inventory, with old-path disposition and split
  lineage recorded separately.
- The baseline table covers every old tracked path exactly once; the final table
  exactly matches `git ls-files` in all three public repositories, permits the
  same relative path across different repositories, rejects duplicate keys
  within one repository, covers new metadata, and assigns every split output a
  component, category, origin, and availability phase.
- Nvim/dev dependency and installation declarations stay with their legacy
  config/runtime through D4 and move atomically in D5; D4 validates the exact
  temporary duplicate set and deterministic aggregation.
- D4 retains only temporary legacy Nvim/dev config/runtime in the top-level
  tree; extracted focused tests, component doctor checks, and component-only
  docs are already absent there and discoverable only from active owners. D5
  removes the remaining legacy Nvim/dev copies.
- D4 validates staging ownership/composition and records a clearly labeled
  monolith/pre-cutover footprint; only D5 enables final base absence tests and
  enforces the base/editor/dev footprint targets.
- Each public capability overlay runs its own focused suites and doctor-check
  tests in its own shared-workflow CI exactly once and does not rerun inherited
  overlay behavior. Top-level public CI runs base-owned focused suites plus
  control-plane/profile and bounded composition suites, validates ownership
  inventories without invoking overlay-owned suites, and never compensates for
  private-overlay CI.
- D5 top-level CI has one Ubuntu-only production-equivalent integration job
  that runs real unfiltered `dot test` for isolated `base`, `editor`, and `dev`
  homes; the complete three-profile gate is not duplicated across every OS.
- Each new public repository carries `.github/cgraf78-actions.lock`, an adapted
  consumer-sync verification job, and tests proving every literal
  `cgraf78/actions` ref matches the lock; CI still uses `setup: none` and only
  owner-focused suites.
- Capability CI installs standalone Dot from the immutable reviewed D1 commit in
  `.github/dot.lock`, never a moving branch or unpinned release.
- Every executable suite remaining in the top-level tree is listed in its CI
  inventory, and no capability-owned suite or component doctor extension
  remains there after D4.
- Installed `dot test` and component doctor discovery expose editor/dev suites
  and checks only when their owning overlays are active.
- Public repositories and documentation contain no private or work-specific
  implementation details.
- `dotfiles-nvim` and `dotfiles-dev` are public from GitHub creation, use the
  canonical MIT license, have default branch `main`, clean independent
  histories, only manifest-allowlisted content,
  and normalized GitHub settings matching `cgraf78/dotfiles` except for
  documented identity-specific fields.
- The root `LICENSE` in each new repository is byte-identical to
  `cgraf78/dotfiles:.github/LICENSE` at the exact commit shared by both
  capability source locks, `overlay-profile-source.lock`, and stack-lock
  `source_dotfiles`; `test/workflow-test` validates the path and SHA, immutable-ref
  local/remote byte comparisons and both GitHub `MIT` SPDX results pass, and the
  normalized settings comparison is driven by the checked-in endpoint manifest
  rather than an implicit endpoint list.
- Both new public repositories pass full worktree/history secret and privacy
  scans plus fresh-eyes public-boundary review before first push, before every
  later push containing extracted content, and at final acceptance; no
  private/work content, naming, topology, config, fixture, comment, generated
  artifact, or historical blob is present.
- Sanitized checked-in standalone Dot examples cover profile inheritance,
  descriptors, all three selector source classes, match/conflict/fallback cases,
  multiple users on one host, and optional-unavailable/later-available behavior;
  tests execute those files through the real parser and lifecycle
  implementation.
- `dotfiles-personal` remains base-compatible and `dotfiles-work` may assume
  dev; both remain largely unchanged unless the audit finds a concrete defect,
  and their existing private rule/config/test/doctor ownership remains intact.
- `dot update`, `dot doctor`, and `dot test` pass for all three clean profiles.
- Downgrading profiles removes only managed links and does not destroy native
  packages, caches, checkouts, or unmanaged files.
- Every known existing installation is covered by a private rollout ledger
  before D4. Each reachable row has both `runtime_ready` proof for the exact
  landed D1 checkout/executable and `selector_ready` proof; temporarily
  unreachable/incomplete rows are explicitly deferred and protected by tested
  deployment holds. The staged pre-D4-runtime upgrade, interruption/retry, and
  subsequent D1-to-D4 transition prove old Dot never processes D4 descriptors.
- Fresh Linux measurements meet the initial base/editor footprint targets or
  include an explicit reviewed explanation for any exception.
