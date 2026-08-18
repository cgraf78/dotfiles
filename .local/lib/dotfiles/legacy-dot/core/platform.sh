# shellcheck shell=bash
# Platform and privilege helpers.

_is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]] && return 0
  [[ -r /proc/sys/kernel/osrelease ]] && grep -qi "microsoft" /proc/sys/kernel/osrelease
}

_dot_tool_platform() {
  if _is_wsl; then
    printf '%s\n' WSL
  else
    uname -s
  fi
}

_dot_tool_command_present() {
  command -v "$1" >/dev/null 2>&1
}

_dot_tool_path_exists() {
  [[ -e "$1" ]]
}

_dot_tool_any_command() {
  local command_name
  for command_name in "$@"; do
    _dot_tool_command_present "$command_name" && return 0
  done
  return 1
}

_dot_tool_any_path() {
  local path
  for path in "$@"; do
    _dot_tool_path_exists "$path" && return 0
  done
  return 1
}

# Report whether a logical tool is installed on this host.
#
# Merge hooks use logical names so platform-specific executable aliases and GUI
# application layouts stay centralized. Unknown names fail closed: callers must
# add an explicit mapping instead of silently treating a typo as installed.
_dot_tool_present() {
  local tool="$1" platform

  case "$tool" in
    agent-rules) _dot_tool_any_command agent-rules-sync ;;
    claude) _dot_tool_any_command claude ;;
    codex) _dot_tool_any_command codex ;;
    cron) _dot_tool_any_command crontab ;;
    gemini) _dot_tool_any_command gemini ;;
    gh) _dot_tool_any_command gh ;;
    git) _dot_tool_any_command git ;;
    grafhome-ca) _dot_tool_any_command grafhome-ca ;;
    gstack) _dot_tool_any_command gstack-register ;;
    hive-memory) _dot_tool_any_command hm ;;
    ignore) _dot_tool_any_command rg fd fdfind ;;
    mise) _dot_tool_any_command mise ;;
    muse) _dot_tool_any_command muse ;;
    nvim) _dot_tool_any_command nvim ;;
    opencode) _dot_tool_any_command opencode ;;
    sapling) _dot_tool_any_command sl ;;
    ssh) _dot_tool_any_command ssh ;;
    sshd) _dot_tool_any_command sshd ;;
    tmux) _dot_tool_any_command tmux ;;
    iterm2)
      platform="$(_dot_tool_platform)"
      [[ "$platform" == Darwin ]] || return 1
      _dot_tool_any_path \
        "/Applications/iTerm.app" \
        "${HOME:-}/Applications/iTerm.app"
      ;;
    karabiner)
      platform="$(_dot_tool_platform)"
      [[ "$platform" == Darwin ]] || return 1
      _dot_tool_any_path \
        "/Applications/Karabiner-Elements.app" \
        "${HOME:-}/Applications/Karabiner-Elements.app" \
        "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
      ;;
    vscode)
      _dot_tool_any_command \
        code code-insiders cursor codium codium-insiders \
        code.exe code-insiders.exe cursor.exe codium.exe \
        codium-insiders.exe && return 0
      if [[ -n "${HOME:-}" ]]; then
        _dot_tool_any_path \
          "$HOME/.vscode-server" \
          "$HOME/.vscode-server-insiders" \
          "$HOME/.vscode-remote" \
          "$HOME/.cursor-server" && return 0
      fi
      platform="$(_dot_tool_platform)"
      [[ "$platform" == Darwin ]] || return 1
      _dot_tool_any_path \
        "/Applications/Visual Studio Code.app" \
        "${HOME:-}/Applications/Visual Studio Code.app" \
        "/Applications/Visual Studio Code - Insiders.app" \
        "${HOME:-}/Applications/Visual Studio Code - Insiders.app" \
        "/Applications/Cursor.app" \
        "${HOME:-}/Applications/Cursor.app" \
        "/Applications/VSCodium.app" \
        "${HOME:-}/Applications/VSCodium.app"
      ;;
    wezterm)
      _dot_tool_any_command wezterm wezterm.exe && return 0
      platform="$(_dot_tool_platform)"
      [[ "$platform" == Darwin ]] || return 1
      _dot_tool_any_path \
        "/Applications/WezTerm.app" \
        "${HOME:-}/Applications/WezTerm.app"
      ;;
    *) return 1 ;;
  esac
}

# Acquire sudo. Returns 0 if root or sudo obtained.
# In quiet mode, skips interactive prompt and returns 1 silently.
_require_sudo() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  sudo -n true 2>/dev/null && return 0
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && return 1
  sudo true 2>/dev/null
}
