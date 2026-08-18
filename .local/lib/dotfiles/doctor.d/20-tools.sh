# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/tools.sh || return

doctor() {
  _dr_check_tools
}
