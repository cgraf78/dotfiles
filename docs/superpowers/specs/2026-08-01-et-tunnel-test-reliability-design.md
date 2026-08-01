# ET Tunnel Test Reliability Design

## Problem

`dot-test` fails and takes 188 seconds on NAS even though the same revision is
green in CI. The failures come from host state leaking into the test:

- the generated remote supervisor prefers the host's real `socat`, bypassing
  the test's fake `ncat` relay and its PID/FIFO observations;
- QEMU listeners already own ports 5901 and 5902, so custom-transport cases
  fail before their adapter runs;
- the portable timeout supervisor leaves same-session descendants alive when
  the suite leader exits normally.

The monolithic ET suite also takes 57-76 seconds when healthy in CI, making it
the full runner's critical path.

## Design

### Host-independent relay and port fixtures

The remote-supervisor fixture will expose doubles for both supported relay
programs. Both doubles will drive the same observable PID, FIFO, and log
contract, so the generated supervisor can exercise its real preference order
without reaching host-installed binaries.

Tests that deliberately use recognizable VNC ports will explicitly make the
existing `lsof` double report those ports as free. Production port detection
will remain unchanged.

### Suite process containment

`timeout.py` will treat the child session as owned for its entire lifecycle.
After the suite leader exits, the supervisor will terminate any remaining
members of that process group before returning the leader's original status.
Cancellation and deadline behavior will retain their current status codes.

A runner regression fixture will spawn a background descendant, exit
successfully, and prove that `dot-test` removes the descendant.

### Runtime reduction

First benchmark the repaired ET suite. If it remains above 45 seconds on NAS,
split its independent behavior groups into parallel `et-tunnel-*-test` shards.
Shared fixture construction will live in one non-discovered helper so relay,
transport, and assertion behavior has a single source. `dot-test et-tunnel`
will continue to select the complete group.

Safety deadlines will not be shortened. Runtime improvements must come from
removing failure cascades and parallelizing independent coverage.

## Acceptance Criteria

- `dot-test et-tunnel` passes on NAS with real `socat` installed and ports
  5901/5902 occupied.
- The aggregate ET selection completes within 45 seconds on NAS.
- A normally exiting suite cannot leave a same-session descendant running.
- No process command line references a completed dot-test temporary root.
- Focused runner tests and the complete `dot-test` suite pass.
- The existing Linux, macOS, WSL, and container CI matrix remains green.
