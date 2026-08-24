# Dotfiles Ownership and Extraction

<!-- agent-rule-id: dotfiles-ownership-and-extraction -->
<!-- agent-rule-trigger: Extracting reusable functionality from dotfiles or deciding whether functionality belongs in dotfiles, an overlay, or a standalone repository -->

Use ownership boundaries to decide where behavior belongs. Optimize for one
clear authority and thin integrations, not for minimizing the size of the
dotfiles repository.

## Decide whether to extract

- Require a cohesive capability, an independent lifecycle, or a second real consumer
  before creating a standalone provider. Similar-looking code or a
  large file alone is not enough.
- Keep a feature in dotfiles when it primarily expresses personal activation,
  aliases, keybindings, presentation choices, or local environment policy.
- Prefer extending an existing provider whose domain already owns the behavior
  over creating a narrowly useful repository.
- Do not extract merely to satisfy line-count or aesthetic goals. Leave
  justified, cohesive code in place when separation would add coordination
  without improving ownership.

## Define the provider boundary

- The provider owns reusable implementation, stable interfaces, portable
  defaults, detailed tests, and integration documentation.
- Dotfiles owns discovery and installation of the provider plus the thinnest
  adapter needed to express local policy.
- Keep environment-specific activation, credentials, private topology,
  employer-specific behavior, and host inventories in the appropriate private
  or work overlay. A public provider may expose generic extension points but
  must not encode those details.
- Preserve one source of truth. Do not keep parallel implementations or copied
  constants in the provider and its consumers.
- Preserve established command names, configuration paths, data formats, and
  fallback behavior unless changing them is an explicit part of the task.

## Plan the migration

- Identify every caller, test, configuration reference, documentation link,
  installation path, and generated-facing reference before moving code.
- Separate provider and consumer changes into independently reviewable commits
  or pull requests when repository boundaries require it. State the dependency
  and safe landing order explicitly.
- Prefer a direct current-version contract when the provider and consumer are
  upgraded together. Add compatibility negotiation only for a demonstrated
  skew requirement.
- Keep the adapter useful when the optional provider is absent when absence is
  already a supported state. Do not turn an optional integration into a startup
  failure.

## Verify the boundary

- Test the provider through its public interface, not through consumer-owned
  implementation details.
- Test the consumer with the provider present and, when supported, absent.
- Verify installation and update behavior from a clean environment as well as
  the existing configured environment.
- Search the old owner for leftover implementation, duplicated vocabulary, and
  stale documentation after cutover.
- Reassess the result as an ownership boundary: a new consumer should normally
  need configuration or a thin adapter, not copied lifecycle logic.
