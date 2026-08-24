# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/agent-rules.sh || return

doctor() {
  _dr_check_agent_rules
}
