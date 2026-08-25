# Local Tool Selection

<!-- agent-rule-id: global-local-tool-selection -->
<!-- agent-rule-trigger: Discovering available local capabilities, choosing an unfamiliar tool, or deciding between overlapping tools -->

Use this guide to notice capable local tools before recreating their behavior
with ad hoc shell, scripts, or a new dependency. It is a decision guide, not a
promise that every named command exists on every host.

## Check Live Availability

Dotfiles manages tools through Shdeps, mise, custom hooks, and tracked local
commands. Platform and package-manager filters mean the effective inventory
varies by host. A configured dependency may be installed, missing, skipped, or
provided under another command name.

Before relying on an optional tool, check the current environment:

```bash
command -v <tool>
shdeps list
shdeps dep-links <dependency>
mise ls --current
```

Use `command -v` as the final check for an executable. Use `shdeps list` to
distinguish installed, missing, and filtered dependencies. When a Shdeps
dependency name differs from its public commands, use `shdeps dep-links
<dependency>` to list its managed entry points. Use `mise ls --current` for
mise-managed tools. The authoritative managed sources are:

- `~/.config/shdeps/00-toolchains.conf`
- `~/.config/shdeps/10-deps.conf`
- `~/.config/mise/config.toml`
- `~/.config/shdeps/hooks.d/`
- tracked commands under `~/.local/bin/`

Also inspect repository-local scripts, configuration, and contributor guidance;
they take precedence over a generic global preference. A missing optional tool
is not authorization to install it. Use an available alternative or ask when
installation would expand the requested scope.

## Selection Principles

- Prefer repository-owned entry points such as `checkrun`, `dot test`, build
  scripts, or package-manager scripts over reconstructing their internals.
- Prefer semantic tools when syntax or structure matters; do not force a text
  search or regular expression to model a programming-language grammar.
- Prefer structured output and stable machine interfaces over parsing display
  text. Render prose only after decisions have been made from structured data.
- Start with the narrowest useful inspection. Avoid scanning or transforming an
  entire repository when a scoped query answers the question.
- Check local `--help` before assuming unfamiliar flags. For behavior that may
  have changed, consult current official documentation.
- Before proposing a new dependency, confirm that the existing environment does
  not already provide the capability.
- Respect privilege and mutation boundaries. Availability of a command does not
  authorize installation, system changes, network publication, or privileged
  tracing.

## Diagnose Managed Tool Failures

An executable on `PATH` is not proof that its provider, cache, or installed
payload is healthy. Trace the complete provenance chain before pinning,
reinstalling, or changing managers:

```text
declaration -> owning manager -> platform filter -> resolver or method
  -> upstream metadata -> cache or installed payload -> managed link -> PATH
```

- Check overlapping Shdeps, mise, hook, package-manager, and tracked-command
  ownership before editing a selector or lock.
- Inspect the resolver's effective configuration and state root. Environment
  overrides can still resolve to a live global project instead of the intended
  worktree.
- Compare the public command, managed link, installation payload, cached
  metadata, and upstream release shape. `command -v` establishes only the first
  boundary.
- Distinguish a transient or incomplete upstream publication from a durable
  local defect. Do not add a pin or fallback until the failed provider contract
  is identified.
- Generate lock or resolved state in an isolated configuration root when the
  tool cannot reliably target the worktree, then copy back only reviewed output.

## High-Leverage Tools Agents May Overlook

Check these before writing custom scripts or falling back to broad text
processing. They are elevated here because they add substantial capability and
are less likely to be inferred from a standard development environment.

| Tool | Reach for it when |
| --- | --- |
| `ast-grep` | A search or rewrite depends on syntax, node relationships, or language structure. |
| `duckdb` | Logs, inventories, benchmark output, CSV, JSONL, or Parquet need joins, grouping, aggregation, or schema inference. |
| `watchexec` | A command must repeat after file changes; prefer it over a handwritten polling loop. |
| `difft` | A syntax-aware comparison would explain a code change better than line-oriented output. |
| `hyperfine` | A performance claim needs repeatable command-level evidence rather than one timing sample. |
| `bpftrace` | Linux behavior requires kernel, syscall, probe, or runtime tracing and the task authorizes the needed privileges. |
| `git absorb-and-rebase` | Uncommitted fixes belong in existing non-HEAD commits; inspect the branch and pushed state first. |
| `checkrun` | A repository's own formatter, linter, schema, or verification policy should choose the underlying tools. |
| `sley` | Staged changes need the environment's established safety and verification boundary. |
| `hm` | Prior decisions, durable preferences, or cross-agent project context may affect the task. |
| `gitleaks`, `actionlint`, `zizmor` | Secrets or GitHub Actions correctness and security need purpose-built validation. |

The table is deliberately selective. Familiar baseline commands remain in the
capability guide below, and the live registries remain the complete inventory.

## Capability Guide

| Need | Prefer | Selection boundary |
| --- | --- | --- |
| text search | `rg` | Default content search; preserve ignore policy unless the task requires otherwise. |
| file discovery | `fd` | Default path search; use explicit roots and filters. |
| structural code search or rewrite | `ast-grep` | Use when language syntax matters or textual replacement would be unsafe. |
| JSON processing | `jq` | Use for document queries, transformations, and streaming JSON. |
| YAML processing | `yq` | Use for YAML-aware queries and transformations. |
| tabular or artifact analysis | `duckdb` | Use for joins, aggregation, CSV, JSONL, Parquet, or data too relational for `jq`. |
| command benchmarking | `hyperfine` | Use for repeatable comparative timing with warmups and multiple runs. |
| repeat on file changes | `watchexec` | Prefer repository-owned watch tasks, then `watchexec` over handwritten polling loops. |
| Linux kernel and runtime tracing | `bpftrace` | Linux and WSL only; verify kernel support, BTF, and authorization for required privileges. |
| disk-usage analysis | `dust`, `ncdu` | Use `dust` for summaries and `ncdu` for interactive exploration. |
| syntax-aware diffs | `difft` | Use when a structural code comparison is clearer than a line diff. |
| GitHub operations | `gh` | Use for pull requests, issues, releases, checks, and other GitHub state. |
| secret scanning | `gitleaks` | Use for repository secret detection; do not expose findings containing secrets. |
| GitHub Actions validation | `actionlint`, `zizmor` | Use `actionlint` for workflow correctness and `zizmor` for security findings. |
| shell diagnostics and formatting | `shellcheck`, `shfmt` | Use diagnostics and formatting separately; follow repository policy first. |
| Markdown, config, and code linting | `rumdl`, `taplo`, `ruff`, `biome`, language-specific tools | Prefer the repository's `checkrun` selection instead of invoking an arbitrary global tool. |
| route and latency diagnosis | `trip` | Use for read-only network path analysis; do not infer policy changes from one trace. |
| interactive process and resource inspection | `btm`, `htop` | Use for live observation, not durable machine-readable evidence. |
| Git history and change inspection | `git`, `delta`, `difft` | In Git-owned repositories, keep Git as the source of truth; use renderers for comprehension, not control flow. |
| Jujutsu version control | `jj` | Use only when repository guidance or current repository state establishes Jujutsu ownership. |

## Managed Workflow Tools and Integrations

These commands and Shdeps-managed integration suites encode local workflow or
infrastructure knowledge that is not obvious from their names. For commands,
check `--help`; for a dependency identity, use `shdeps dep-links <dependency>`
to discover its public commands. Consult repository guidance for exact
interfaces.

- `checkrun`: repository-aware formatting, linting, schema validation, and
  verification. Prefer it when a repository provides Checkrun policy.
- `sley`: staged-change and pre-commit safety verification. Let existing hooks
  invoke it; do not bypass failures to force a commit.
- `hm`: Hive Memory's cross-agent durable context interface. Follow the global
  memory rules for search, project scoping, and writes.
- `sysup`: cross-platform system upgrade and post-upgrade health checks. Treat
  package and service mutations as operational work requiring appropriate
  authorization.
- `ds`: project and tmux session workflow. Use its public interface rather than
  manipulating owned session state directly.
- `termnav`: Shdeps-managed focus-aware terminal and nested-tmux integration;
  public entry points include `termnav-switch-tab` and `nvim-tmux-open`.
- `ettun` and `fwdports`: remote transport and forwarding workflows. Inspect
  their help and current state before changing connectivity.
- `agentguard`: Shdeps-managed agent-hook safety and lifecycle integration;
  it exposes `agent-hook-*` commands rather than an `agentguard` executable.
- `agent-rules-sync`: validates and publishes the shared rule and playbook
  manifest to supported agent runtimes. Edit source fragments, never generated
  targets.
- `vscode-exts`: managed VS Code extension inventory and synchronization.

## When This Guide Is Not Enough

The dependency registry intentionally records installation mechanics rather
than full semantics. If a tool is unfamiliar, use its local help and official
documentation. If two tools overlap, choose based on the task's data model,
required output stability, platform support, and repository conventions—not
merely because one command is newer or more convenient.

## Maintenance Contract

Do not mirror package versions, aliases, provider filters, or the complete
dependency inventory here. Shdeps, mise, custom hooks, and tracked local
commands remain authoritative for those facts. Update this playbook only when:

- a tool adds a capability that agents would not otherwise discover;
- the preferred tool for a task changes;
- overlapping tools need a new selection boundary; or
- privilege, platform, or mutation constraints change materially.

Removing or renaming a highlighted capability requires reviewing this guide in
the same change. This is a deliberate human review boundary: tests validate the
route and durable discovery rules, while the live registries remain the only
machine-readable inventory. Ordinary package upgrades and implementation-only
dependencies require no playbook edit.
