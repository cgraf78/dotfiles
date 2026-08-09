# Python Style

<!-- agent-rule-id: language-python-style -->
<!-- agent-rule-trigger: Editing Python -->

- Use structured standard-library APIs for structured data: `pathlib`, `json`,
  `tomllib`, `argparse`, `dataclasses`, and typed collections where they fit.
  Avoid ad hoc string parsing when a real parser or model is available.
- Use `Path` for filesystem paths in implementation code. Accept `str | Path` or
  a target-runtime-compatible equivalent at boundaries when useful, then
  normalize once near the boundary.
- Use type hints for function signatures, structured return values, and module
  interfaces. Prefer precise generics and unions over untyped dictionaries or
  `Any` unless the boundary is genuinely dynamic; choose annotation syntax that
  the target Python runtime can parse, using `from __future__ import annotations`
  where postponed evaluation is useful.
- Follow standard PEP 8 naming: `snake_case` for functions, variables, modules,
  and parameters; `PascalCase` for classes; `UPPER_SNAKE_CASE` for constants.
- Keep CLI entry points thin: parse arguments, call library functions, print or
  exit. Reusable policy and data handling should return structured values.
- Do not parse human-readable display text for control flow. Use typed values,
  explicit status fields, keys, enums, or structured dictionaries internally.
- Prefer explicit error handling with actionable messages for expected user,
  config, and filesystem failures. Avoid tracebacks for normal invalid input.
- Keep functions focused and side effects narrow. Put cwd, environment, process,
  and filesystem discovery near adapter/CLI boundaries.
- Use docstrings for public classes/functions and non-trivial private helpers.
  Use comments for invariants, compatibility constraints, and cross-system
  policy, not for restating each line of code.
- Respect project-local formatter and linter config. In dotfiles or when no
  local config says otherwise, use 4-space indentation, 100-column wrapping,
  sorted imports, and modern Python idioms where supported by the target runtime.
