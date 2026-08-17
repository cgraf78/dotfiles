# shellcheck shell=bash
# Client-owned compatibility helpers while concrete hooks move off the embedded
# engine. Every implementation below is either client policy or a thin adapter
# to the standalone hook API; no standalone private function is imported.

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
        code code-insiders cursor codium codium-insiders \
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
