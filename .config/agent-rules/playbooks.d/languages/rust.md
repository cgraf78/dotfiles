# Rust Style

<!-- agent-rule-id: language-rust-style -->
<!-- agent-rule-trigger: Editing Rust -->

- Model domain concepts with small structs, enums, and newtypes instead of
  stringly typed maps once values cross a module boundary.
- Keep parsing, filesystem access, environment access, and process execution at
  clear boundary modules. Core policy should operate on typed inputs.
- Use borrowed inputs (`&str`, `&Path`, slices) for read-only parameters and own
  data at persistence, threading, and API boundaries.
- Use `Path`/`PathBuf` for paths, not raw strings, except at CLI/display edges.
- Return `Result` for expected failures and preserve context in error messages.
  Use `Option` for absence, and reserve panics for tests or impossible internal
  invariants.
- Prefer focused modules and small functions. Iterator chains are welcome when
  they stay readable; choose a clear loop when error handling or branching would
  otherwise be hidden.
- Keep durable vocabulary centralized as constants, enums, or helper functions
  so CLI commands, hooks, and tests do not drift.
- Use Rustdoc/module comments to explain ownership boundaries, persistence
  contracts, compatibility promises, and security/privacy assumptions.
- Let project-local formatter and linter config handle mechanical style. In
  dotfiles or when no local config says otherwise, use 4-space indentation,
  100-column wrapping, explicit derives, and idiomatic standard-library types.
