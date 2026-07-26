# Code Style

<!-- agent-rule-id: global-code-style -->

- **Brief function names** — concise verbs, no unnecessary prefixes/suffixes.
- **Comments explain WHY, not WHAT** — comments are valuable for non-obvious
  performance decisions, hardware behaviors, workarounds,
  regulatory/compliance requirements, and complex algorithms.
- **Add generous comments when they carry genuine context** — prefer useful
  notes that explain invariants, tradeoffs, surprising constraints, or
  cross-system assumptions over sparse code that forces future readers to
  rediscover intent. Large blocks of code with no comments are discouraged.
- **Docstrings** for classes, public methods, and non-trivial private methods.
  Skip simple getters/setters and obvious helpers. Use Doxygen style: `/** */`
  blocks with `@brief`, `@param`, `@tparam`, `@return`, `@note`. Use
  `/// @brief` for one-liners.
- Follow any applicable language playbook referenced by the on-demand index in
  addition to these global style rules.
- **Keep code tidy** - delete dead comments, commented-out code, and debugging
  leftovers.
