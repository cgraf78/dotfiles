# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge Claude Code settings into ~/.claude/settings.json.
# Shared by dotbootstrap and dot (on pull).
# Requires jq.
#
# Layers come from claude/settings.d. Direct files aggregate in lexical order;
# each immediate *.replace directory contributes only its last lexical file, so
# overlays can express personal/work mutual exclusivity without this hook knowing
# those environment names.
#
# Array-valued keys under "permissions" (allow, additionalDirectories) are
# concatenated and deduplicated instead of replaced. Hook arrays are merged
# per event by identity (matcher + command), so a config change to an
# existing hook replaces it instead of appending a duplicate.

# Merge a Claude settings layer into an existing settings.json.
# Policy: source wins on conflicts (same key, different value).
# Existing scalar keys and non-conflicting object keys are preserved.
# Permission arrays (allow, additionalDirectories) are concatenated and
# deduplicated instead of replaced. Hook arrays are merged per event by
# identity (matcher + command) so re-merging is idempotent.
_merge_claude_settings() {
  local src="$1" dst="$2"
  local filter

  # Merge: existing settings * source settings (recursive merge, source wins).
  # Permission arrays are concatenated + deduplicated instead of replaced.
  # Exact Tool(*) rules mean "all uses of this tool", but the public schema
  # wants that written as bare Tool; normalize stale live settings during merge.
  # shellcheck disable=SC2016 # jq owns $d/$s inside this filter.
  filter='
    def normalize_permission:
      if type == "string" and test("^(Agent|Bash|Edit|ExitPlanMode|Glob|Grep|KillShell|LSP|Monitor|NotebookEdit|PowerShell|Read|Skill|TaskCreate|TaskGet|TaskList|TaskOutput|TaskStop|TaskUpdate|TodoWrite|ToolSearch|WebFetch|WebSearch|Write)\\(\\*\\)$") then
        sub("\\(\\*\\)$"; "")
      else
        .
      end;

    ([$d[0].permissions.allow? // [] | .[]]
     + [$s[0].permissions.allow? // [] | .[]] | map(normalize_permission) | unique) as $all_allow |
    ([$d[0].permissions.additionalDirectories? // [] | .[]]
     + [$s[0].permissions.additionalDirectories? // [] | .[]] | unique) as $all_dirs |

    # A hook group'"'"'s identity is its matcher plus which commands it runs;
    # timeout/type are just that hook'"'"'s execution parameters, not part of
    # what makes it "the same hook". Existing (destination) groups sharing an
    # incoming group'"'"'s identity are dropped before appending the incoming
    # group, so re-running this merge is idempotent (no accumulation run over
    # run) and self-healing (an already-duplicated live settings.json collapses
    # to one canonical copy per event on the next `dot update`, and a config
    # change like a new timeout cleanly replaces the old value instead of
    # sitting duplicated alongside it forever).
    def hook_group_identity:
      {matcher: (.matcher // null), commands: [(.hooks // [])[].command]};
    def merge_hook_group_list($existing; $incoming):
      ($incoming | map(hook_group_identity)) as $incoming_ids |
      ($existing | map(select((hook_group_identity as $id | ($incoming_ids | index($id))) | not)))
        as $kept |
      $kept + $incoming;

    # Merge hook arrays per event instead of letting `*` replace them: `*` would
    # overwrite the base layer'"'"'s hooks (e.g. Stop) as soon as a later layer
    # defines any hooks at all. Concatenate each event'"'"'s groups, base first.
    (($d[0].hooks // {}) as $dh | ($s[0].hooks // {}) as $sh |
      reduce (($dh | keys_unsorted) + ($sh | keys_unsorted))[] as $e
        ({}; .[$e] = merge_hook_group_list($dh[$e] // []; $sh[$e] // []))) as $merged_hooks |

    $d[0] * $s[0] |

    .permissions.allow = $all_allow |
    (if ($merged_hooks | length) > 0 then .hooks = $merged_hooks else . end) |
    if ($all_dirs | length) > 0
      then .permissions.additionalDirectories = $all_dirs
      else .
    end
  '
  dot_json_layer "Claude settings" "$src" "$dst" "$filter"
}

merge() {
  _dot_tool_present claude || return 0
  dot_json_available || return 0

  local dst="$HOME/.claude/settings.json"
  local -a src_files=()
  local src

  while IFS= read -r src; do
    src_files+=("$src")
  done < <(dot_hook_family_files_matching claude/settings.d '*.json' '*.replace/*.json')

  dot_hook_log "  Claude Code"

  # AgentGuard supplies the complete current generation and its generic
  # ownership-aware reconciler. Do not apply later policy layers unless that
  # required base refresh succeeds; this preserves the entire last-known-good
  # target during a dependency or coordinated-rollout gap.
  _merge_hook_agentguard_json_layer "Claude settings" claude "$dst" || return 1

  for src in "${src_files[@]}"; do
    _merge_claude_settings "$src" "$dst"
  done
}
