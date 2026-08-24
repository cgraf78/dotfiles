# Transactional State Updates

<!-- agent-rule-id: engineering-transactional-state-updates -->
<!-- agent-rule-trigger: Writing or replacing persistent configuration, cache, session, manifest, or generated state -->

Publish durable state only after a complete replacement is ready. A failed
update must not expose partial content or destroy the last known-good state.

## Prepare safely

- Decide which process owns the destination, whether concurrent writers are
  allowed, and what readers may observe during an update.
- Create sensitive files and newly managed directories with restrictive
  permissions from the beginning. A later `chmod` does not prevent exposure
  during creation.
- Use an invocation-unique temporary file in the destination directory when
  atomic replacement is required; cross-filesystem moves are not atomic.
- Install cleanup before writing and remove only temporary state owned by the
  current invocation.

## Validate and publish

- Write the complete candidate, check every producer status, and validate its
  syntax or invariants before publication.
- Apply the intended final mode and ownership before replacing the destination.
- Atomically rename the validated candidate into place. Preserve the previous
  destination byte-for-byte on every failure before that point.
- Do not claim crash durability unless file and directory synchronization is
  part of the implementation and has been verified on the target filesystem.
- Respect caller-owned directory permissions unless changing them is an
  explicit part of the contract.

## Verify failure behavior

- Inject failures during generation, validation, permission changes, and final
  publication.
- Test restrictive and permissive umasks, concurrent writers, empty content,
  and an existing valid destination.
- Prove that failures preserve the prior state, publish no partial result, and
  leave no temporary files behind.
