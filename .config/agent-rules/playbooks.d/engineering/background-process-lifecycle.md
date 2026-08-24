# Background Process Lifecycle

<!-- agent-rule-id: engineering-background-process-lifecycle -->
<!-- agent-rule-trigger: Launching, supervising, cancelling, or testing background processes -->

Treat every spawned process as an owned resource with an explicit lifecycle.
Design normal completion, partial startup, failure, and cancellation together.

## Establish ownership

- Install cleanup before launching the first child or creating the first
  temporary resource.
- Track only process IDs, process groups, files, sockets, and directories
  created by the current invocation. Never sweep unrelated processes by a broad
  name match.
- Use a process group or equivalent supervision boundary when terminating one
  child must also terminate its descendants.
- Give concurrent invocations distinct state. Include a stable resource
  identity plus an invocation-specific component when paths can overlap.

## Shut down completely

- Prefer a documented graceful-stop path, then escalate to forced termination
  only after a bounded deadline.
- Reap every owned child after termination so cancellation cannot leave
  zombies. Continue cleanup when one child has already exited or a signal
  races with normal completion.
- Make cleanup idempotent and safe after partial initialization.
- In sourced shell code, restore caller traps, shell options, `IFS`, and globals
  after cleanup. Return errors instead of exiting the caller.
- Preserve the primary failure or signal status while still reporting cleanup
  failures that need diagnosis.

## Test the lifecycle

- Exercise normal completion, child failure, partial startup, `INT`, `TERM`,
  and any platform-specific shutdown path.
- Poll observable state with a bounded deadline rather than relying on fixed
  sleeps.
- Assert that owned children and descendants are gone, no zombies remain, and
  temporary files, sockets, locks, and sessions are removed.
- Test concurrent invocations and prove that one cleanup path cannot terminate
  or delete another invocation's resources.
