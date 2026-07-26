# shellcheck shell=bash
# Shared Windows/WSL path discovery helpers.
#
# WSL has two user identities in play: the Linux account running dotfiles and
# the Windows profile that owns GUI apps. They often have the same short name on
# personal machines, but that is a convenience, not a contract. Keep Windows
# profile discovery behind this helper so hooks and interactive shell helpers do
# not drift back to guessing the Windows profile from the Linux username.

_dot_windows_cmd_exe() {
  local candidate converted

  if [ -n "${DOT_TEST_WINDOWS_CMD_EXE:-}" ]; then
    [ -x "$DOT_TEST_WINDOWS_CMD_EXE" ] || return 1
    REPLY="$DOT_TEST_WINDOWS_CMD_EXE"
    return 0
  fi

  if command -v wslpath >/dev/null 2>&1; then
    converted="$(wslpath 'C:\Windows\System32\cmd.exe' 2>/dev/null)" || converted=""
    if [ -n "$converted" ] && [ -x "$converted" ]; then
      REPLY="$converted"
      return 0
    fi
  fi

  for candidate in /mnt/c/Windows/System32/cmd.exe "$(command -v cmd.exe 2>/dev/null)"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    _dot_windows_is_system_cmd "$candidate" || continue
    REPLY="$candidate"
    return 0
  done

  return 1
}

_dot_windows_is_system_cmd() {
  local command_path="$1" windows_path

  # PATH inside WSL can contain stale or fake Windows command shims. Match the
  # stricter VS Code resolver policy: only the real System32 cmd.exe is allowed
  # to tell us which Windows profile owns GUI app state.
  command -v wslpath >/dev/null 2>&1 || return 1
  windows_path="$(wslpath -w "$command_path" 2>/dev/null)" || return 1
  windows_path="${windows_path//\//\\}"
  windows_path="$(printf '%s' "$windows_path" | tr '[:upper:]' '[:lower:]')"
  case "$windows_path" in
    [a-z]:\\windows\\system32\\cmd.exe) return 0 ;;
  esac
  return 1
}

# Query a raw Windows environment variable via cmd.exe, with no path
# conversion. Shared by the path-shaped resolver below and by plain
# (non-path) vars like USERNAME that wslpath cannot convert.
_dot_windows_env_raw() {
  local name="$1" cmd cmd_dir output line value=""

  _dot_windows_cmd_exe || return 1
  cmd="$REPLY"
  cmd_dir="$(dirname "$cmd")"

  # Start cmd.exe from a Windows-mounted directory. Otherwise Windows can print
  # a UNC-cwd warning before the real `set` output when dot runs from a Linux
  # path, and first-line parsers silently lose the value.
  output="$(
    cd "$cmd_dir" 2>/dev/null && "$cmd" /D /C "set $name" </dev/null 2>/dev/null | tr -d '\r'
  )" ||
    output=""
  while IFS= read -r line; do
    case "$line" in
      "$name="*)
        value="${line#"$name="}"
        break
        ;;
    esac
  done <<<"$output"
  [ -n "$value" ] || return 1

  REPLY="$value"
}

_dot_windows_env_path() {
  local name="$1" converted

  _dot_windows_env_raw "$name" || return 1

  converted="$(wslpath "$REPLY" 2>/dev/null)" || return 1
  [ -n "$converted" ] || return 1

  REPLY="$converted"
}

dot_wsl_windows_home() {
  local appdata

  # DOT_WINDOWS_HOME is the generic override for shell hooks. Keep the old test
  # variable for existing tests and let VS Code-specific callers keep their own
  # compatibility alias in the Python resolver.
  if [ -n "${DOT_TEST_WINDOWS_HOME:-}" ]; then
    REPLY="$DOT_TEST_WINDOWS_HOME"
    return 0
  fi
  if [ -n "${DOT_WINDOWS_HOME:-}" ]; then
    REPLY="$DOT_WINDOWS_HOME"
    return 0
  fi

  if [ "${DOT_TEST:-0}" = 1 ]; then
    # WSL exposes the real Windows profile even when tests replace HOME. Tests
    # must opt in explicitly so a unit test never writes into the host profile.
    return 1
  fi

  if _dot_windows_env_path USERPROFILE; then
    return 0
  fi

  if _dot_windows_env_path APPDATA; then
    appdata="$REPLY"
    case "$appdata" in
      */AppData/Roaming)
        REPLY="${appdata%/AppData/Roaming}"
        return 0
        ;;
    esac
  fi

  return 1
}

# Whether the current OS account is the one paired with the native Windows
# profile, i.e. the account GUI apps (VS Code, WezTerm, ...) actually run as.
# WSL conventionally runs one Linux account per Windows user, but the kernel
# and the mounted Windows filesystem are shared with any other Linux account
# on the same distro (root, secondary users). dot_wsl_windows_home() resolves
# the single shared Windows profile regardless of caller, so if more than one
# account runs `dot update` and each merges into that same native config file,
# their unlocked writes race on the same NTFS/9p file and can corrupt it. Guard
# call sites that write into the native Windows profile with this check.
#
# Compares live values instead of a configured or hardcoded account name so
# the check works on any host no matter what either account is named.
dot_wsl_is_paired_windows_account() {
  if [ -n "${DOT_TEST_WSL_PAIRED_ACCOUNT:-}" ]; then
    [ "$DOT_TEST_WSL_PAIRED_ACCOUNT" = 1 ]
    return
  fi

  if [ "${DOT_TEST:-0}" = 1 ]; then
    return 1
  fi

  local windows_user linux_user
  _dot_windows_env_raw USERNAME || return 1
  # dot update runs merge hooks under `set -euo pipefail`; a failing id/tr
  # here would abort the whole run (skipping every hook after this one,
  # including ones that have nothing to do with Windows) rather than just
  # treating this account as unpaired. Fall back to empty on failure instead.
  windows_user="$(printf '%s' "$REPLY" | tr '[:upper:]' '[:lower:]')" || windows_user=""
  linux_user="$(id -un 2>/dev/null | tr '[:upper:]' '[:lower:]')" || linux_user=""
  [ -n "$windows_user" ] && [ -n "$linux_user" ] && [ "$windows_user" = "$linux_user" ]
}

# dot_wsl_windows_home() itself stays unguarded: reading where the Windows
# profile lives is safe for any account (e.g. the interactive WINHOME shell
# aliases in 51-aliases-wsl.sh, usable from any Linux account on the distro).
# Writing dotfiles-managed config into it is not, since a second account can
# only get there by resolving the same path and racing the paired account's
# writes. Route every such write through this wrapper instead of chaining
# dot_wsl_is_paired_windows_account + dot_wsl_windows_home at each call site
# by hand — a future call site can forget to add that check, but it cannot
# get a path out of this function without it.
dot_wsl_writable_windows_home() {
  dot_wsl_is_paired_windows_account || return 1
  dot_wsl_windows_home
}
