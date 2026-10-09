# shellcheck shell=bash
# Byte budget for one rendered agent-rules target.
#
# Every agent session loads the whole aggregate, so its size is prompt cost
# paid on every task. The base rule test fails a composed aggregate above
# this budget and `dot doctor` warns as a live target nears it; both read the
# value here so the limit and the warning cannot drift apart. The work
# overlay's aggregate test sources this file directly, so it stays free of
# hook-runtime dependencies and keeps this function name.

_dot_agent_rules_budget_bytes() {
  REPLY=20000
}
