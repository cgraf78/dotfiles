# Durable Memory Hygiene

<!-- agent-rule-id: memory-durable-hygiene -->
<!-- agent-rule-trigger: Writing, correcting, superseding, reconciling, retagging, scoping, troubleshooting, or auditing durable memory and its retrieval health -->

Keep durable memory current, discoverable, and narrowly scoped. Search before
writing so a correction updates prior knowledge instead of creating an
unresolved contradiction.

## Choose scope deliberately

- Use project scope for repository-specific facts and pass
  `--project <file-or-repo-path>` using the relevant project or file, not an
  incidental shell working directory.
- Use explicit global scope only for guidance that should be recalled across
  unrelated repositories, machines, and agents.
- Do not broaden a host-specific, employer-specific, or private operational
  fact merely to make retrieval easier.

## Maintain current truth

- Search for existing memories about the subject before adding a new one.
- When a fact changes, use `hm reconcile` or `hm remember --supersedes <id>` so
  the old statement is explicitly retired instead of leaving two competing
  claims.
- Use `--valid-from` and `--valid-to` for facts whose applicability has a known
  time boundary.
- Use `hm retag` or another supported command to correct metadata. Do not
  hand-edit stored records because the indexed event may remain stale.
- If expected context is missing, inspect project resolution and
  `hm sync-status` before assuming the memory was never written.

## Keep signal high

- Store the durable conclusion, rationale, and future action, not raw command
  output or a transcript of the investigation.
- Record hypotheses and unconfirmed observations as notes until evidence makes
  them durable facts.
- Do not generalize a single incident into a universal rule without repeated
  evidence or a clearly stated invariant.
- Never store secrets, credentials, access tokens, or private data outside its
  authorized scope.

## Diagnose memory health and retrieval

- Separate store reachability, synchronization status, index freshness,
  conflicts, query latency, project resolution, and result relevance. A slow or
  irrelevant query is not evidence of corruption.
- Check `hm sync-status` and the resolved store and project before forcing a
  refresh or concluding that a memory is missing.
- Prefer a non-destructive index refresh when canonical data is healthy but the
  local index is stale. Do not delete, redact, reconcile, or retag records during
  a health review without separate authorization for those content mutations.
- Treat doctor warnings and timing as diagnostic evidence. Verify whether reads
  complete and whether canonical and indexed state agree before declaring the
  service unavailable.
