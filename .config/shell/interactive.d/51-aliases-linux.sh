# shellcheck shell=bash
# Linux-specific aliases (excludes WSL and MINGW/MSYS, which have their own file).
# Depends on _UNAME and _bat_cmd from earlier files.

[[ "$_UNAME" == "Linux" && -z "${WSL_DISTRO_NAME:-}" ]] || return 0

# Native ls coloring (eza takes precedence in 50-aliases.sh if installed).
command -v eza >/dev/null 2>&1 || alias ls='ls --color=auto'

# Debian/Ubuntu ship `bat` as `batcat`; surface it under the standard name.
[[ "${_bat_cmd:-}" == "batcat" ]] && alias bat='batcat'
