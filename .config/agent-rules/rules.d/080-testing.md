# Testing

<!-- agent-rule-id: global-testing-practices -->

- Add tests for new or changed executable behavior. For documentation,
  configuration, schemas, or generated artifacts, run the closest applicable
  validation.
- Analyze edge cases before writing tests — boundary values, missing data, error
  paths, concurrency, invalid input.
- Dedicated test case per edge case, not bundled into happy-path tests.
- For asynchronous or process tests, poll the observable condition with a
  bounded deadline instead of sleeping for a guessed duration. On timeout,
  report the state needed to diagnose the failure.
- Before committing in a GitHub repo, check `.github/workflows/` for CI steps
  and run what reproduces locally (linters, tests, type checks). Skip CI-only
  infrastructure (deployment, secrets, matrix OS variants).
