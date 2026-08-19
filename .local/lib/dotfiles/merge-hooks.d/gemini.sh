# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge Gemini CLI settings into ~/.gemini/settings.json.
# Runs during standalone Dot client convergence.
# Requires jq.
#
# Layers come from gemini/settings.d. Direct files aggregate in lexical order;
# each immediate *.replace directory contributes only its last lexical file, so
# overlays can express environment-specific overrides without this hook knowing
# those environment names.
#
# Gemini-owned state (sessionRetention, trustedFolders, etc.) is preserved
# because the recursive merge only overwrites keys present in the source.

_merge_gemini_settings() {
  local src="$1" dst="$2"
  # shellcheck disable=SC2016 # jq owns $d/$s inside this filter.
  dot_json_layer "Gemini settings" "$src" "$dst" '$d[0] * $s[0]'
}

merge() {
  _dot_tool_present gemini || return 0
  dot_json_available || return 0

  local dst="$HOME/.gemini/settings.json"
  local -a src_files=()
  local src

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching gemini/settings.d '*.json' '*.replace/*.json')

  dot_hook_log "  Gemini CLI"

  # Reconciliation is provider-owned so event retirement and command changes
  # stay reusable outside this dotfiles repository. A failed required refresh
  # leaves the whole generated target unchanged and fails the merge hook.
  _merge_hook_agentguard_json_layer "Gemini settings" gemini "$dst" || return 1

  for src in "${src_files[@]}"; do
    _merge_gemini_settings "$src" "$dst"
  done
}
