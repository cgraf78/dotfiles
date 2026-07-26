# Design Principles

<!-- agent-rule-id: global-design-principles -->

- **Favor clean, elegant designs** — keep solutions cohesive, readable, and
  nicely componentized. Prefer small, well-named pieces with clear boundaries
  over tangled or overly clever implementations.
- **Single-source shared knowledge** — when two or more places need the same
  value, decision, or logic, extract it to one authoritative location and have
  consumers call into it. Don't duplicate constants, resolution logic, or
  convention knowledge across files.
- **Expose clean interfaces** — provide a function or module API to access
  shared state rather than forcing callers to reimplement the same steps.
  Callers should say *what* they want, not *how* to get it.
- **Compose from single-purpose parts** — build higher-level behavior by
  aggregating small, focused components with clean interfaces. Each piece does
  one thing well; composition gives flexibility to recombine them differently
  without rewriting internals.
- **Consolidate after the second use** — the first duplication is fine; when a
  second consumer appears, refactor to a shared source. Don't preemptively
  abstract, but don't tolerate three copies.
- **Separate machine semantics from display text** — never parse or compare
  human-readable output text to drive behavior. Use structured keys, enums,
  status fields, typed reasons, or model metadata for control flow, summaries,
  APIs, grouping, ordering, and rendering; render prose only at the output
  boundary.
- **Centralize durable vocabulary** — persisted strings, API event names, phase
  keys, manifest method names, and other domain identifiers must have one owning
  module. Callers should import constants or use helper functions instead of
  retyping string literals that must stay aligned.
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
