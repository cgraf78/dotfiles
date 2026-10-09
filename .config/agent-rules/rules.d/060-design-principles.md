# Design Principles

<!-- agent-rule-id: global-design-principles -->

- **Favor small, single-purpose parts** — compose higher-level behavior from
  cohesive, readable, well-named components with clear boundaries and clean
  interfaces so pieces recombine without rewriting internals; avoid tangled or
  overly clever implementations.
- **Single-source shared knowledge** — once a second place needs a value,
  decision, or logic, move it to one authoritative location that consumers
  call into. Don't abstract before then; don't duplicate constants, resolution
  logic, or convention knowledge across files.
- **Expose clean interfaces** — give callers a function or module API for
  shared state so they say *what* they want instead of reimplementing *how*.
- **Centralize durable vocabulary** — persisted strings, API event names,
  phase keys, manifest method names, and other domain identifiers must have
  one owning module; import its constants or helpers instead of retyping
  literals that must stay aligned.
- **Separate machine semantics from display text** — never drive behavior by
  parsing or comparing human-readable output. Use structured keys, enums,
  status fields, typed reasons, or model metadata for control flow, summaries,
  APIs, grouping, ordering, and rendering; render prose only at the output
  boundary.
- **Guard at async boundaries** — delayed callbacks (timers, deferred
  functions, completion handlers) must re-validate every handle they touch;
  resources can disappear between scheduling and execution.
- **Prevent re-entrancy in polled loops** — if a timer or event can fire while
  a previous run is in flight, skip overlapping runs with a flag rather than
  queuing unbounded work.
- **Isolate by separation, not by crippling** — when sandboxing, prefer running
  normal code in a separate process or scope over stripping everything and
  re-adding pieces; remove only what actually interferes.
