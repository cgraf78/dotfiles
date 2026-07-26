# shellcheck shell=bash
# Platform and privilege helpers.

_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qi "microsoft" /proc/sys/kernel/osrelease
}

# Acquire sudo. Returns 0 if root or sudo obtained.
# In quiet mode, skips interactive prompt and returns 1 silently.
_require_sudo() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  sudo -n true 2>/dev/null && return 0
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && return 1
  sudo true 2>/dev/null
}
