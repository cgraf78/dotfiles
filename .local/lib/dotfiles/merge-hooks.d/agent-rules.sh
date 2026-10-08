# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Resolve dotfiles-owned rule policy for the standalone agent-rules-sync provider.
#
# Dotfiles deliberately retains source ordering, overlay trust, and target
# selection. The provider owns all generic parsing, rendering, publication,
# migration, and cleanup behavior. Keeping this hook at that boundary prevents
# the reusable repository from learning anything about dot overlay internals.

# The manifest is generated state rather than user configuration: its records
# contain resolved overlay paths which can differ across machines and runs.
_dot_agent_rules_manifest_path() {
  dot_xdg_path state "dot/agent-rules-sync-manifest-v1.tsv"
}

# Expand the intentionally small target-file policy language without sourcing
# configuration as shell. Symbolic provider targets can be added later if they
# create real value; preserving the existing declarative files is simpler now.
_dot_agent_rules_expand_target() {
  local target="$1"
  local home_ref="\$HOME"
  local tilde_ref="~"
  case "$target" in
    "$home_ref") printf '%s\n' "$HOME" ;;
    "$home_ref"/*) printf '%s/%s\n' "$HOME" "${target#"$home_ref"/}" ;;
    "$tilde_ref") printf '%s\n' "$HOME" ;;
    "$tilde_ref"/*) printf '%s/%s\n' "$HOME" "${target#"$tilde_ref"/}" ;;
    /*) printf '%s\n' "$target" ;;
    *)
      dot_hook_warn "    warning: skipping relative agent rule target: $target"
      return 1
      ;;
  esac
}

_dot_agent_rules_sources() {
  # The prose has a first-class config home; only target-profile selection
  # remains merge-hook config. The generic family helper still provides the
  # established numeric ordering and .replace semantics at this new root.
  dot_family_files_matching \
    "$HOME/.config/agent-rules/rules.d" \
    '[0-9][0-9][0-9]-*.md' \
    '[0-9][0-9][0-9]-*.replace/*.md'
}

_dot_agent_rules_target_confs() {
  dot_hook_family_files_matching \
    agent-rules/targets.d \
    '*.txt' '*.replace/*.txt' \
    '*.conf' '*.replace/*.conf'
}

# TSV is intentionally used so manifests stay inspectable and shell tooling
# can produce them without a serializer. Reject its delimiters before writing
# anything so a path can never silently become a different policy record.
_dot_agent_rules_manifest_field_valid() {
  local field="$1"
  [[ -n "$field" &&
    "$field" != *$'\t'* &&
    "$field" != *$'\n'* &&
    "$field" != *$'\r'* ]]
}

_dot_agent_rules_emit_rules() {
  local listing source
  listing=$(_dot_agent_rules_sources) || return 1
  while IFS= read -r source; do
    [[ -n "$source" ]] || continue
    _dot_agent_rules_manifest_field_valid "$source" || return 1
    printf 'rule\t%s\n' "$source"
  done <<<"$listing"
}

_dot_agent_rules_emit_playbooks() {
  local root="$1" listing file route

  # An absent playbook root represents an empty optional input. Once the root
  # exists, discovery errors are fatal because silently dropping an overlay's
  # policy would publish an incomplete ruleset.
  [[ -d "$root" ]] || return 0
  listing=$(_dot_playbook_files) || return 1
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    case "$file" in
      "$root"/*.md) route=${file#"$root"/} ;;
      *) return 1 ;;
    esac
    _dot_agent_rules_manifest_field_valid "$route" || return 1
    _dot_agent_rules_manifest_field_valid "$file" || return 1
    printf 'playbook\t%s\t%s\n' "$route" "$file"
  done <<<"$listing"
}

_dot_agent_rules_emit_targets() {
  local listing conf line target
  local -A seen=()

  listing=$(_dot_agent_rules_target_confs) || return 1
  while IFS= read -r conf; do
    [[ -n "$conf" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line=$(printf '%s\n' "$line" |
        sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//')
      [[ -n "$line" ]] || continue
      target=$(_dot_agent_rules_expand_target "$line") || continue
      _dot_agent_rules_manifest_field_valid "$target" || return 1
      [[ -n "${seen[$target]+x}" ]] && continue
      seen[$target]=1
      printf 'target-file\t%s\n' "$target"
    done <"$conf"
  done <<<"$listing"
}

_dot_agent_rules_build_manifest() {
  local destination="$1" rule_root playbook_root

  rule_root="$HOME/.config/agent-rules/rules.d"
  playbook_root=$(_dot_playbook_root) || return 1
  _dot_agent_rules_manifest_field_valid "$destination" || return 1
  _dot_agent_rules_manifest_field_valid "$rule_root" || return 1
  _dot_agent_rules_manifest_field_valid "$playbook_root" || return 1

  {
    printf 'version\tagent-rules-sync-manifest-v1\n' &&
      printf 'rule-root\t%s\n' "$rule_root" &&
      printf 'playbook-root\t%s\n' "$playbook_root" &&
      _dot_agent_rules_emit_rules &&
      _dot_agent_rules_emit_playbooks "$playbook_root" &&
      _dot_agent_rules_emit_targets
  } >"$destination"
}

# Build the complete manifest beside its destination and rename it only after
# every dot-owned trust and policy input has resolved. This keeps the previous
# good manifest intact if an overlay link is stale or a path cannot be encoded.
_dot_agent_rules_write_manifest() {
  local manifest tmp

  _dot_agent_rules_manifest_path || return 1
  manifest="$REPLY"
  # mkdir honors the caller's existing state directory, while a newly created
  # directory is private even under an unexpectedly permissive umask.
  (umask 077 && mkdir -p "$(dirname "$manifest")") || return 1
  dot_sibling_tmp_for "$manifest" || return 1
  tmp="$REPLY"

  _dot_agent_rules_build_manifest "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$manifest" || {
    rm -f "$tmp"
    return 1
  }
  REPLY="$manifest"
}

# Report whether the installed manifest and targets match current policy for
# dot doctor. Dotfiles owns only the manifest: rebuilding it catches source,
# overlay, and target-profile changes since the last update. Whether each
# target is current is the provider's `check` contract, so this adapter never
# learns its ownership markers, header lines, or target mode.
#
# REPLY is a reason key, optionally followed by TAB and a detail. A provider
# target state arrives as `target-<state>` so doctor can name the file.
_dot_agent_rules_check_installed() {
  local provider manifest mode work status state target line=''

  REPLY='provider-missing'
  provider=$(command -v agent-rules-sync) || return 1
  REPLY='manifest-path-failed'
  _dot_agent_rules_manifest_path || return 1
  manifest="$REPLY"
  REPLY='manifest-missing'
  [[ -f "$manifest" ]] || return 1
  # The manifest names private source paths and is written 0600 by
  # _dot_agent_rules_write_manifest above; this checks dotfiles' own policy.
  mode=$(stat -c '%a' "$manifest" 2>/dev/null || stat -f '%Lp' "$manifest" 2>/dev/null) || {
    REPLY='manifest-mode-unreadable'
    return 1
  }
  if [[ "$mode" != 600 ]]; then
    REPLY='manifest-mode'
    return 1
  fi
  REPLY='temporary-workspace-failed'
  work=$(mktemp -d 2>/dev/null || mktemp -d -t dot-agent-rules-check) || return 1

  if ! _dot_agent_rules_build_manifest "$work/expected.tsv"; then
    REPLY='source-selection-failed'
  elif ! dot_config_files_equal "$work/expected.tsv" "$manifest"; then
    REPLY='manifest-mismatch'
  else
    "$provider" check --manifest "$manifest" >"$work/check.out" 2>"$work/check.err"
    status=$?
    case "$status" in
      0) REPLY='current' ;;
      2)
        # Our invocation is fixed and valid, so a usage status means a
        # provider release from before `check`, which rejects the unknown
        # command without touching anything. Hosts float to the latest
        # provider, so this is a rollout window, not a policy failure.
        # Bash also exits 2 on a syntax error, so confirm the launcher
        # itself still works before calling it merely old.
        if "$provider" --help >/dev/null 2>&1; then
          REPLY='provider-check-unsupported'
        else
          REPLY='check-failed'
        fi
        ;;
      3)
        # Any state other than `current` is drift, including states a newer
        # provider adds later; report the first so doctor can name a file.
        REPLY='check-failed'
        while IFS=$'\t' read -r state target || [[ -n "$state" ]]; do
          [[ -n "$state" && "$state" != current ]] || continue
          REPLY="target-$state"$'\t'"$target"
          break
        done <"$work/check.out"
        ;;
      *)
        # Carry the provider's own first error line so doctor can show why
        # validation failed without rerunning anything.
        REPLY='check-failed'
        IFS= read -r line <"$work/check.err" || :
        [[ -z "$line" ]] || REPLY+=$'\t'"$line"
        ;;
    esac
  fi

  rm -rf "$work"
  [[ "$REPLY" == current ]]
}

merge() {
  _dot_tool_present agent-rules || return 0
  local provider manifest
  provider=$(command -v agent-rules-sync) || return 0

  _dot_agent_rules_write_manifest || {
    dot_hook_warn "    warning: invalid agent rule policy; keeping existing generated rules"
    return 2
  }
  manifest="$REPLY"

  dot_hook_log "  Agent rules"
  "$provider" --manifest "$manifest"
}
