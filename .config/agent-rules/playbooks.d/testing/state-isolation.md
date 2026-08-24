# Stateful Test Isolation

<!-- agent-rule-id: testing-stateful-application-isolation -->
<!-- agent-rule-trigger: Testing applications or plugins that can write user configuration, state, cache, sessions, history, or credentials -->

Run stateful tests without reading or modifying the user's live application
state. Core runtime isolation flags may not cover plugin-owned persistence.

- Inventory every persistent channel the process can use: `HOME`, XDG config,
  data, state, and cache roots, application-specific directories, sessions,
  history, credential stores, and plugin-managed files.
- Redirect writable channels to invocation-owned temporary roots. Disable
  persistence hooks explicitly when the test does not need them.
- Do not assume one application's clean-start flag isolates extensions or
  plugins. Inspect the loaded configuration and persistence owners.
- Exercise startup, normal exit, failure, and forced termination where each can
  publish state.
- Assert that expected isolated state is empty or contains only declared
  fixtures and that live user paths are unchanged.
- Clean only invocation-owned temporary state. Preserve it on failure when it is
  needed for diagnosis, without exposing credentials or private content.
