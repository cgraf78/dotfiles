# shellcheck shell=bash
# Client-owned hook helpers. Every implementation below is either client policy
# or a thin adapter to the standalone hook API; no standalone private function
# is imported.

dot_hook_source merge-hooks.d/lib/windows.sh || return
dot_hook_source merge-hooks.d/lib/agent-playbooks.sh || return
dot_hook_source merge-hooks.d/lib/shdeps-assets.sh || return

_dot_tool_command_present() {
  command -v "$1" >/dev/null 2>&1
}

_dot_tool_path_exists() {
  [[ -e $1 ]]
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

_dot_account_home() {
  local account entry name _password _uid _gid _gecos home _shell
  local candidate id_command="" getent_command=""

  REPLY=
  for candidate in \
    /data/data/com.termux/files/usr/bin/id \
    /usr/bin/id \
    /bin/id; do
    [[ -x "$candidate" ]] || continue
    id_command=$candidate
    break
  done
  [[ -n "$id_command" ]] || return 1
  account=$("$id_command" -un 2>/dev/null) || return 1
  case "$account" in
    "" | *[!A-Za-z0-9._-]*) return 1 ;;
  esac

  # Account authority must not come from a caller-controlled HOME or PATH.
  for candidate in \
    /usr/bin/getent \
    /bin/getent \
    /data/data/com.termux/files/usr/bin/getent; do
    [[ -x "$candidate" ]] || continue
    getent_command=$candidate
    break
  done
  if [[ -n "$getent_command" ]]; then
    entry=$("$getent_command" passwd "$account" 2>/dev/null) || entry=
    if IFS=: read -r name _password _uid _gid _gecos home _shell <<<"$entry" &&
      [[ "$name" == "$account" ]]; then
      REPLY=$home
    fi
  fi

  if [[ -z "$REPLY" &&
    "$id_command" == /data/data/com.termux/files/usr/bin/id &&
    -d /data/data/com.termux/files/home ]]; then
    REPLY=/data/data/com.termux/files/home
  fi

  if [[ -z "$REPLY" && -x /usr/bin/dscl ]]; then
    entry=$(/usr/bin/dscl /Search -read "/Users/$account" NFSHomeDirectory 2>/dev/null) || entry=
    case "$entry" in
      "NFSHomeDirectory: "*) REPLY=${entry#NFSHomeDirectory: } ;;
    esac
  fi

  if [[ -z "$REPLY" && -r /etc/passwd ]]; then
    while IFS=: read -r name _password _uid _gid _gecos home _shell; do
      [[ "$name" == "$account" ]] || continue
      REPLY=$home
      break
    done </etc/passwd
  fi

  [[ "$REPLY" == /* && -d "$REPLY" ]]
}

_dot_account_scoped_command() {
  local label="$1" command_name="$2" test_command="${3:-}"
  local account_home

  if [[ "${DOT_TEST:-0}" == "1" ]]; then
    if [[ -z "$test_command" || ! -x "$test_command" ]]; then
      dot_hook_warn "  warning: $label skipped: test $command_name is not configured"
      return 1
    fi
    REPLY="$test_command"
    return 0
  fi

  if ! _dot_account_home; then
    dot_hook_warn "  warning: $label skipped: account home could not be resolved"
    return 1
  fi
  account_home="$REPLY"
  if [[ ! -d "$HOME" || ! "$HOME" -ef "$account_home" ]]; then
    dot_hook_warn "  warning: $label skipped: HOME is not the account home: $HOME"
    return 1
  fi

  REPLY=$(command -v "$command_name" 2>/dev/null) || return 1
}

_dot_tool_platform() {
  local kernel

  if [[ -n ${WSL_DISTRO_NAME:-} || -n ${WSL_INTEROP:-} ]]; then
    printf '%s\n' WSL
    return
  fi

  kernel=$(uname -r 2>/dev/null) || kernel=''
  case ${kernel,,} in
    *microsoft*) printf '%s\n' WSL ;;
    *) uname -s ;;
  esac
}

# Logical application presence is client policy. The public API deliberately
# exposes only literal command/path probes, so platform aliases stay here.
_dot_tool_present() {
  local tool=$1 platform

  case $tool in
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
    tmux) _dot_tool_any_command tmux ;;
    iterm2)
      platform=$(_dot_tool_platform)
      [[ $platform == Darwin ]] || return 1
      _dot_tool_any_path /Applications/iTerm.app "$HOME/Applications/iTerm.app"
      ;;
    karabiner)
      platform=$(_dot_tool_platform)
      [[ $platform == Darwin ]] || return 1
      _dot_tool_any_path \
        /Applications/Karabiner-Elements.app \
        "$HOME/Applications/Karabiner-Elements.app" \
        '/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli'
      ;;
    vscode)
      _dot_tool_any_command \
        code code-insiders code-fb code-fb-insiders cursor codium codium-insiders \
        code.exe code-insiders.exe cursor.exe codium.exe \
        codium-insiders.exe && return 0
      _dot_tool_any_path \
        "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" \
        "$HOME/.vscode-remote" "$HOME/.cursor-server" && return 0
      platform=$(_dot_tool_platform)
      [[ $platform == Darwin ]] || return 1
      _dot_tool_any_path \
        '/Applications/Visual Studio Code.app' \
        "$HOME/Applications/Visual Studio Code.app" \
        '/Applications/Visual Studio Code - Insiders.app' \
        "$HOME/Applications/Visual Studio Code - Insiders.app" \
        '/Applications/VS Code @ FB.app' \
        "$HOME/Applications/VS Code @ FB.app" \
        '/Applications/VS Code @ FB - Insiders.app' \
        "$HOME/Applications/VS Code @ FB - Insiders.app" \
        /Applications/Cursor.app "$HOME/Applications/Cursor.app" \
        /Applications/VSCodium.app "$HOME/Applications/VSCodium.app"
      ;;
    wezterm)
      _dot_tool_any_command wezterm wezterm.exe && return 0
      platform=$(_dot_tool_platform)
      [[ $platform == Darwin ]] || return 1
      _dot_tool_any_path /Applications/WezTerm.app "$HOME/Applications/WezTerm.app"
      ;;
    *) return 1 ;;
  esac
}

_merge_hook_mikefarah_yq() {
  local path_yq='' shdeps_yq='' yq_bin
  path_yq=$(command -v yq 2>/dev/null) || path_yq=''
  shdeps_yq=$HOME/.local/bin/yq
  for yq_bin in "$path_yq" "$shdeps_yq"; do
    [[ -n $yq_bin && -x $yq_bin ]] || continue
    if "$yq_bin" --version 2>/dev/null | grep -qi mikefarah; then
      printf '%s\n' "$yq_bin"
      return 0
    fi
  done
  return 1
}

_merge_hook_agentguard_json_layer() {
  local label=$1 agent=$2 destination=$3
  local source='' reconciler='' live=/dev/null temporary=''

  source=$(dot_agentguard_integration_file "$agent" hooks.json 2>/dev/null) || source=''
  reconciler=$(dot_agentguard_integration_file _shared reconcile-hooks.jq 2>/dev/null) ||
    reconciler=''
  if [[ ! -r $source || ! -r $reconciler ]]; then
    dot_hook_warn "    warning: AgentGuard $agent integration unavailable — preserving $destination"
    return 1
  fi
  if ! jq empty "$source" 2>/dev/null; then
    dot_hook_warn "    warning: invalid AgentGuard $agent integration — preserving $destination"
    return 1
  fi
  if [[ (-e $destination || -L $destination) && -s $destination ]] &&
    jq empty "$destination" 2>/dev/null; then
    live=$destination
  elif [[ -e $destination || -L $destination ]]; then
    dot_hook_warn "    warning: corrupt $destination — rebuilding"
  fi

  mkdir -p "${destination%/*}"
  dot_sibling_tmp_for "$destination" || return 1
  temporary=$REPLY
  if ! jq -n --sort-keys --indent 2 \
    --arg agent "$agent" \
    --slurpfile d "$live" \
    --slurpfile s "$source" \
    -f "$reconciler" >"$temporary" ||
    [[ ! -s $temporary ]] || ! jq empty "$temporary" 2>/dev/null; then
    dot_hook_warn "    warning: AgentGuard $label reconciliation failed — preserving $destination"
    rm -f "$temporary"
    return 1
  fi
  if [[ ! -L $destination ]] && cmp -s "$temporary" "$destination" 2>/dev/null; then
    rm -f "$temporary"
    return 0
  fi
  dot_commit_tmp "$temporary" "$destination" || {
    rm -f "$temporary"
    return 1
  }
}
