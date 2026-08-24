# Generated Artifact Consistency

<!-- agent-rule-id: engineering-generated-artifact-consistency -->
<!-- agent-rule-trigger: Changing or repairing a generated artifact family, including its generators, templates, validators, outputs, or published copies -->

Repair generated systems at their canonical producer and keep every derived
artifact family consistent. Do not make a generated file the accidental source
of truth.

## Find the complete artifact family

- Resolve the owning generator, template, source fragment, or schema before
  editing output.
- Inventory every derived form: generated source, UI and API representations,
  fixtures, packaged or published copies, installed targets, documentation, and
  validators.
- Determine whether the defect is local to one input or systemic across every
  artifact produced by the same rule.

## Fix and regenerate

- Change the canonical producer. Update validators and fixtures in the same
  change so they encode the corrected contract rather than the old output.
- When the defect is systemic, regenerate and review the complete related
  family, not only the file named in the report.
- Use the supported generation or publication entry point and inspect every
  producer status. Do not hand-copy output in a way the next generation run
  will overwrite.
- Keep publication atomic and failure-safe by following the transactional-state
  playbook when persistent destinations are replaced.

## Verify every boundary

- Compare canonical source, generated output, published copies, and installed
  state where each boundary exists.
- Validate syntax and structure, then exercise a real consumer path. A parser or
  schema check cannot prove application-specific serialization or runtime use.
- Search for stale siblings, duplicated vocabulary, retired paths, and generated
  files that were not refreshed.
- Commit source and required derived artifacts together only when the repository
  intentionally tracks both.
