# shellcheck shell=bash
dot_doctor_source doctor.d/lib/compat.sh || return
dot_doctor_source doctor.d/lib/managed-config.sh || return

doctor() {
  _dr_check_managed_config
}
