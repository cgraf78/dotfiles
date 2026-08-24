# Release Lifecycle

<!-- agent-rule-id: git-release-lifecycle -->
<!-- agent-rule-trigger: Publishing, verifying, or cleaning up a software release, including immutable consumer repins in its rollout -->

Treat release publication as a separate lifecycle after pull-request landing.
A merge or tag push is not proof that users can obtain a valid release.

## Prepare from authoritative state

- Use the repository-supported release entry point instead of reconstructing
  packaging or tagging manually.
- Start from a clean local default branch that matches its authoritative remote.
  Confirm required pull requests and CI have completed.
- Run the supported dry-run or preflight first. Record the exact proposed tag,
  version, commit, platforms, and artifacts before publication.
- Recheck release documentation and automation in the current repository; do
  not copy command names or tag conventions from another project.

## Publish and observe

- Publish through the supported workflow and monitor the authoritative release
  job to completion. Pending or partially green jobs are not completion.
- Verify the remote tag and release object, including draft and prerelease state,
  expected asset names and counts, and checksums or signatures when provided.
- Inspect representative archives or packages. Where practical, run the
  packaged executable and confirm its embedded version and platform contract.

## Complete the consumer loop

- When consumers use immutable release digests, tags, or commit pins, verify the
  published value and update each intended consumer in a separate, safely
  ordered change.
- Verify installer resolution, ABI or platform coverage, and downstream CI when
  those are part of the release contract.
- Report publication and consumer rollout separately. Do not imply that a
  published release is deployed or adopted when repins remain outstanding.
