# Performance Investigation

<!-- agent-rule-id: engineering-performance-investigation -->
<!-- agent-rule-trigger: Investigating or changing startup, hook, CLI, test-runner, or activation performance -->

Treat performance work as an evidence-driven behavior change. Optimize a
representative workload at realistic scale, preserve semantics, and avoid
complexity whose practical benefit is too small to matter.

## Establish the baseline

- Define the user-visible operation, environment, input size, and success
  criteria before measuring. Include common invocation locations and execution
  modes rather than benchmarking only a convenient synthetic path.
- Separate cold, warm, and cached behavior when users encounter each of them.
  Record whether network, filesystem, process startup, or background load can
  affect the result.
- Use repeated samples with warmups and report a useful distribution such as
  median plus a high percentile or range. Use `hyperfine` for command-level
  comparisons when appropriate.
- Profile or instrument enough to attribute the cost before changing code. Do
  not infer the bottleneck solely from total wall time.
- Preserve the baseline command, raw measurements, environment details, and
  relevant version or commit so another run can reproduce the comparison.

## Choose the lightest useful tool

- Use the shell's `time` for a quick one-shot view of wall and CPU time. Use the
  platform-specific `/usr/bin/time` options when peak memory and other resource
  counters matter. Do not treat one sample as a stable benchmark.
- Use `hyperfine` for repeated command comparisons, warmups, preparation
  commands, parameter sweeps, and machine-readable result export.
- Prefer application-native instrumentation for attribution when available:
  examples include Git Trace2, timestamped shell tracing, test-runner timing,
  and language runtime profilers.
- On Linux, use `strace -f -c` for syscall and subprocess summaries and
  `strace -f -ttT` for timing a specific path. Use `perf stat` for hardware and
  scheduler counters, then `perf record` and `perf report` when CPU hotspots
  matter. On macOS, use Instruments or `sample` for the equivalent process-level
  investigation.
- Use `bpftrace` only when the question requires kernel or system-wide
  visibility that narrower tools cannot provide and the task authorizes the
  necessary privileges.
- Use `jq` for individual structured results and `duckdb` when multiple JSON,
  JSONL, CSV, or Parquet runs need aggregation, grouping, or comparison.
- Benchmark and profile separately when instrumentation materially changes
  timing. Use profiling to explain the cost and the low-overhead harness to
  report the improvement.

## Evaluate a change

- Define the minimum practical improvement before implementation. Compare the
  measured gain with added code, state, invalidation, concurrency, and
  maintenance cost.
- Change the narrowest layer that owns the measured cost. Avoid moving work to
  startup, hiding it in background processes, or weakening validation merely to
  improve the reported number.
- Verify output, side effects, error handling, and compatibility are unchanged.
  Include boundary cases and realistic loaded conditions, not only the fastest
  happy path.
- When adding a cache, document its key, authority, invalidation events,
  lifetime, atomic update behavior, stale-state fallback, and cleanup. Add
  lifecycle tests where stale data could affect correctness.
- When adding parallelism, bound concurrency and verify cancellation, output
  ordering, resource use, and failure aggregation.

## Report and stop

- Report before-and-after measurements using the same harness and conditions.
  Distinguish observed results from projections.
- Keep regression coverage for the behavior and for any new cache or scheduling
  boundary.
- Stop when the path is already healthy, the gain is within noise, realistic
  workloads do not benefit, or the complexity costs more than the measured
  improvement. Record promising but unsupported ideas as deferred context
  rather than turning them into active work.
