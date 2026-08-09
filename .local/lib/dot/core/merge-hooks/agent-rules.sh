# shellcheck shell=bash
# Resolve dotfiles-owned rule policy for the standalone agent-rules-sync provider.
#
# Dotfiles deliberately retains source ordering, overlay trust, and target
# selection. The provider owns all generic parsing, rendering, publication,
# migration, and cleanup behavior. Keeping this hook at that boundary prevents
# the reusable repository from learning anything about dot overlay internals.

if ! declare -F _merge_hook_family_files_matching >/dev/null 2>&1; then
  _dot_agent_rules_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../merge-hooks.sh disable=SC1091
  . "$_dot_agent_rules_hook_dir/../merge-hooks.sh"
fi
if ! declare -F _dot_xdg_path >/dev/null 2>&1; then
  _dot_agent_rules_hook_dir="${_dot_agent_rules_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../xdg.sh disable=SC1091
  . "$_dot_agent_rules_hook_dir/../xdg.sh"
fi
if ! declare -F _dot_sibling_tmp_for >/dev/null 2>&1; then
  _dot_agent_rules_hook_dir="${_dot_agent_rules_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../temp.sh disable=SC1091
  . "$_dot_agent_rules_hook_dir/../temp.sh"
fi
if ! declare -F _dot_playbook_files >/dev/null 2>&1; then
  _dot_agent_rules_hook_dir="${_dot_agent_rules_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../agent-playbooks.sh disable=SC1091
  . "$_dot_agent_rules_hook_dir/../agent-playbooks.sh"
fi

# The manifest is generated state rather than user configuration: its records
# contain resolved overlay paths which can differ across machines and runs.
_dot_agent_rules_manifest_path() {
  _dot_xdg_path state "dot/agent-rules-sync-manifest-v1.tsv"
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
      _warn "    warning: skipping relative agent rule target: $target"
      return 1
      ;;
  esac
}

_dot_agent_rules_sources() {
  _merge_hook_family_files_matching \
    agent-rules/rules.d \
    '[0-9][0-9][0-9]-*.md' \
    '[0-9][0-9][0-9]-*.replace/*.md'
}

_dot_agent_rules_target_confs() {
  _merge_hook_family_files_matching \
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

# Build the complete manifest beside its destination and rename it only after
# every dot-owned trust and policy input has resolved. This keeps the previous
# good manifest intact if an overlay link is stale or a path cannot be encoded.
_dot_agent_rules_write_manifest() {
  local manifest tmp rule_root playbook_root

  _dot_agent_rules_manifest_path || return 1
  manifest="$REPLY"
  rule_root="$HOME/.config/dot/merge-hooks.d/agent-rules/rules.d"
  playbook_root=$(_dot_playbook_root) || return 1
  _dot_agent_rules_manifest_field_valid "$rule_root" || return 1
  _dot_agent_rules_manifest_field_valid "$playbook_root" || return 1

  # mkdir honors the caller's existing state directory, while a newly created
  # directory is private even under an unexpectedly permissive umask.
  (umask 077 && mkdir -p "$(dirname "$manifest")") || return 1
  _dot_sibling_tmp_for "$manifest" || return 1
  tmp="$REPLY"

  {
    printf 'version\tagent-rules-sync-manifest-v1\n' &&
      printf 'rule-root\t%s\n' "$rule_root" &&
      printf 'playbook-root\t%s\n' "$playbook_root" &&
      _dot_agent_rules_emit_rules &&
      _dot_agent_rules_emit_playbooks "$playbook_root" &&
      _dot_agent_rules_emit_targets
  } >"$tmp" || {
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

merge() {
  local provider manifest
  provider=$(command -v agent-rules-sync) || return 0

  _dot_agent_rules_write_manifest || {
    _warn "    warning: invalid agent rule policy; keeping existing generated rules"
    return 2
  }
  manifest="$REPLY"

  _log "  Agent rules"
  "$provider" --manifest "$manifest"
}
