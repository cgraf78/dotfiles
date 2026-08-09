# Code Style

<!-- agent-rule-id: global-code-style -->

- **Brief function names** — concise verbs, no unnecessary prefixes/suffixes.
- **Comment the WHY, generously** — explain intent and non-obvious context:
  invariants, tradeoffs, performance decisions, hardware behaviors, workarounds,
  regulatory/compliance requirements, complex algorithms, surprising
  constraints, and cross-system assumptions. Don't restate WHAT the code does,
  and large blocks of code with no comments are discouraged.
- **Docstrings** for classes, public methods, and non-trivial private methods.
  Skip simple getters/setters and obvious helpers. Use Doxygen style: `/** */`
  blocks with `@brief`, `@param`, `@tparam`, `@return`, `@note`. Use
  `/// @brief` for one-liners.
- Follow any applicable language playbook referenced by the on-demand index in
  addition to these global style rules.
- **Keep code tidy** - delete dead comments, commented-out code, and debugging
  leftovers.
