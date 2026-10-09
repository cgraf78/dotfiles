# Code Style

<!-- agent-rule-id: global-code-style -->

- **Brief function names** — concise verbs, no unnecessary prefixes/suffixes.
- **Comment the WHY, generously** — explain intent and non-obvious context:
  invariants, tradeoffs, performance decisions, hardware behaviors, workarounds,
  regulatory/compliance requirements, complex algorithms, surprising
  constraints, and cross-system assumptions. Don't restate WHAT the code does,
  and large uncommented blocks are discouraged.
- **Docstrings** for classes, public methods, and non-trivial private methods,
  in language-native syntax; skip simple getters/setters and obvious helpers.
- Also follow any applicable language playbook, including its exact docstring
  conventions.
- **Keep code tidy** - delete dead comments, commented-out code, and debugging
  leftovers.
