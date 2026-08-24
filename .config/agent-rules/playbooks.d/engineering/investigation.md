# Systematic Investigation

<!-- agent-rule-id: engineering-systematic-investigation -->
<!-- agent-rule-trigger: Diagnosing a bug, failure, incident, or unexpected behavior -->

Find the producing cause before changing state. Preserve enough evidence to
distinguish the fault from transport errors, diagnostic limitations, and
secondary symptoms.

## Reproduce the real path

- Reproduce the user's exact operation and record the observed boundary where
  behavior first diverges. A nearby synthetic command is supporting evidence,
  not a substitute for the real client or consumer.
- Decompose the path into producer, intermediate transforms or transports,
  persistent state, consumer, and display layer. Test each boundary separately.
- Compare structured before-state and after-state when a sequence changes
  behavior. Correlation alone does not identify which step produced the state.
- Keep local quoting, shell, SSH, sandbox, and diagnostic-tool failures separate
  from target-system evidence. A probe that did not reach the target proves
  nothing about the target.

## Establish ownership and provenance

- Identify the component that owns the executable, configuration, generated
  output, persisted value, listener, or policy before editing it.
- Trace aliases, wrappers, PATH precedence, dependency managers, generators,
  proxies, and adapters until the actual producer and consumer are known.
- Prefer authoritative structured state and source-owned interfaces over
  display text, cached summaries, or inferred implementation details.
- Preserve uncertainty. State what the evidence proves, what it merely
  implicates, and what could not be inspected.

## Preserve evidence before recovery

- Inspect relevant process state, logs, counters, ownership, timestamps,
  configuration, and live resource identity before restarting, killing,
  recreating, deleting, or cleaning up.
- Do not patch a visible symptom while a broader state or provenance anomaly is
  unexplained. Use known-good absolute tools if PATH or the runtime environment
  may itself be compromised.
- Keep diagnosis read-only unless the request includes remediation. A recovery
  action can destroy the evidence needed to determine a recurring cause.

## Verify the conclusion

- Test the narrow hypothesis at the boundary that can falsify it.
- After an authorized fix, re-read authoritative state and exercise the real
  end-to-end consumer path. A successful write, restart, or HTTP response alone
  is not proof that the intended behavior changed.
- If unrelated checks fail, reproduce them on an unchanged baseline before
  classifying them as pre-existing. Never report a partially observed path as a
  completed diagnosis.
