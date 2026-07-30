# Design Principles

<!-- agent-rule-id: global-design-principles -->

- **Favor small, single-purpose parts** — build higher-level behavior by
  composing cohesive, readable, well-named components with clear boundaries and
  clean interfaces, so pieces recombine without rewriting internals. Prefer
  that over tangled or overly clever implementations.
- **Single-source shared knowledge** — when a second place needs the same
  value, decision, or logic, extract it to one authoritative location and have
  consumers call into it; don't duplicate constants, resolution logic, or
  convention knowledge across files. The first duplication is fine — don't
  preemptively abstract, don't tolerate three copies.
- **Expose clean interfaces** — give callers a function or module API for
  shared state so they say *what* they want, not *how* to get it, instead of
  reimplementing the same steps.
- **Centralize durable vocabulary** — persisted strings, API event names, phase
  keys, manifest method names, and other domain identifiers must have one
  owning module. Import constants or helpers instead of retyping literals that
  must stay aligned.
- **Separate machine semantics from display text** — never parse or compare
  human-readable output text to drive behavior. Use structured keys, enums,
  status fields, typed reasons, or model metadata for control flow, summaries,
  APIs, grouping, ordering, and rendering; render prose only at the output
  boundary.
- **Guard at async boundaries** — any callback that fires after a delay (timers,
  deferred functions, completion handlers) must re-validate every handle it
  touches. Resources can disappear between scheduling and execution.
- **Prevent re-entrancy in polled loops** — if a timer or event can fire while a
  previous invocation is still in flight, use a flag to skip overlapping runs
  rather than queuing unbounded work.
- **Isolate by separation, not by crippling** — when sandboxing components,
  prefer running normal code in a separate process or scope over stripping
  everything and manually re-adding pieces. Only remove what actually causes
  interference.
