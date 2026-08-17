# shellcheck shell=bash
# Codex config merge implementation for the dot Codex merge hook.
#
# The hook is intentionally thin; this module owns the stateful Codex merge
# policy so the large TOML/profile/trust workflow can be reviewed and tested as
# a focused component.

# Source-relative lookup keeps this component usable from tests, bootstrap
# fixtures, and ad-hoc shells where HOME may not point at the real checkout.
_DOT_CODEX_CONFIG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return

if ! declare -F _merge_hook_source >/dev/null 2>&1; then
  # The normal dot runtime sources merge-hooks.sh before it sources hooks. This
  # fallback keeps the private Codex helper debuggable from a shell and reliable
  # in tests that source the real hook while HOME points at a fixture.
  # shellcheck source=../../../../.local/lib/dot/core/merge-hooks.sh
  . "$_DOT_CODEX_CONFIG_DIR/../../../../.local/lib/dot/core/merge-hooks.sh"
fi
if ! declare -F dot_agentguard_integration_file >/dev/null 2>&1; then
  # AgentGuard assets are resolved by the shared Shdeps adapter, not by the
  # merge library above. The normal dot runtime loads both libraries before this
  # module, but its documented clean-shell/test fallback must be complete too;
  # otherwise source discovery fails only in the very environments the fallback
  # exists to support.
  # shellcheck source=../../../../.local/lib/dot/core/shdeps-assets.sh
  . "$_DOT_CODEX_CONFIG_DIR/../../../../.local/lib/dot/core/shdeps-assets.sh"
fi

_codex_toml_renderer() {
  printf '%s\n' "$_DOT_CODEX_CONFIG_DIR/toml-render.py"
}

# Discover Codex profile families rendered as standalone
# ~/.codex/<name>.config.toml overlays.
#
# `--profile NAME` loads config.toml, then overlays ~/.codex/NAME.config.toml
# on top. Any `codex/profiles/<name>.d` family becomes one such rendered
# profile, so overlays can add profiles without editing this shell module.
# `default` is intentionally ignored: its settings are folded into config.toml's
# base keys, which are what bare `codex` (no --profile) resolves to.
#
# Args: none
# Returns profile names on stdout, one per line.
_codex_profiles() {
  local hooks_dir dir base profile
  hooks_dir="$(_merge_hook_dir)"

  for dir in "$hooks_dir"/codex/profiles/*.d; do
    [[ -d "$dir" ]] || continue
    base="$(basename "$dir")"
    profile="${base%.d}"
    [[ -n "$profile" && "$profile" != "default" ]] || continue
    printf '%s\n' "$profile"
  done | LC_ALL=C sort -u
}

# Print profile names whose source families were intentionally removed.
#
# Removing a family stops future rendering, but it cannot remove an overlay
# produced by an older dot update. Keep the exact former dot-owned names here
# so cleanup stays narrow and does not infer ownership from arbitrary files in
# ~/.codex.
_codex_retired_profiles() {
  printf '%s\n' allow_all no_prompt
}

_codex_prune_retired_profiles() {
  local profile path

  while IFS= read -r profile; do
    path="$HOME/.codex/$profile.config.toml"

    # A directory at a retired path is not an output this hook could have
    # generated. Remove only regular files and symlinks, including dangling
    # symlinks left by the older generated-config layout.
    if [[ -f "$path" || -L "$path" ]]; then
      rm -f -- "$path" || return 1
    fi
  done < <(_codex_retired_profiles)
}

# Print the main Codex config source stream.
#
# The hook treats this as the only authoritative config-layer discovery path.
# Cache signatures and the actual merge both call this helper so a future family
# policy change cannot make the cache skip a fragment that the merge would read,
# or vice versa.
#
# Args: none
# Returns absolute TOML fragment paths on stdout, one per line.
_codex_agentguard_source() {
  dot_agentguard_integration_file codex hooks.toml
}

_codex_agentguard_reconciler() {
  dot_agentguard_integration_file _shared reconcile-hooks.jq
}

_codex_config_sources() {
  local agentguard_src=""

  # This complete stream feeds cache signatures. The actual merge preflights
  # both AgentGuard assets and applies the first source through the provider's
  # ownership-aware reconciler rather than treating it as an ordinary layer.
  agentguard_src=$(_codex_agentguard_source 2>/dev/null) || agentguard_src=""
  [[ -r "$agentguard_src" ]] && printf '%s\n' "$agentguard_src"

  _merge_hook_family_files_matching codex/config.d '*.toml' '*.replace/*.toml'
}

# Print the source stream for a named Codex profile overlay.
#
# Profiles are still an explicit Codex concept, but their internal layering is
# the generic family policy. That keeps per-profile overrides extensible without
# teaching this module about environment names such as personal or work.
#
# Args: $1 = profile name from _codex_profiles
# Returns absolute TOML fragment paths on stdout, one per line.
_codex_profile_sources() {
  local profile="$1"
  _merge_hook_family_files_matching "codex/profiles/$profile.d" '*.toml' '*.replace/*.toml'
}

_codex_yq() {
  _merge_hook_mikefarah_yq
}

_codex_file_fingerprint() {
  local path="$1"
  if [[ -f "$path" ]]; then
    printf 'file\t%s\t%s\n' "$path" "$(cksum <"$path" 2>/dev/null || printf 'unreadable 0')"
  elif [[ -e "$path" || -L "$path" ]]; then
    printf 'other\t%s\n' "$path"
  else
    printf 'missing\t%s\n' "$path"
  fi
}

_codex_config_cache_file() {
  printf '%s\n' "$HOME/.codex/.dotfiles-config-merge-cache-v1"
}

_codex_config_signature() {
  local dst="$1" helper="$2" reconciler=""
  reconciler=$(_codex_agentguard_reconciler 2>/dev/null) || reconciler=""

  {
    # v6 adds provider-owned generation reconciliation. Include the full source
    # stream and the reconciliation program so either a native mapping change or
    # an ownership-rule migration forces one complete merge before the cache can
    # skip future no-op updates.
    printf 'version\t%s\n' 'dotfiles-codex-config-merge-v6'
    local source
    while IFS= read -r source; do
      _codex_file_fingerprint "$source"
    done < <(_codex_config_sources)
    _codex_file_fingerprint "$reconciler"
    _codex_file_fingerprint "$helper"
    _codex_file_fingerprint "$dst"

    # Profile source families and their rendered destinations are part of the
    # same no-op decision: editing a profile fragment should refresh the profile
    # output even when the main config family and trust helper are unchanged.
    local profile
    while IFS= read -r profile; do
      while IFS= read -r source; do
        _codex_file_fingerprint "$source"
      done < <(_codex_profile_sources "$profile")
      _codex_file_fingerprint "$HOME/.codex/$profile.config.toml"
    done < <(_codex_profiles)
  } | cksum | awk '{ print $1 ":" $2 }'
}

_codex_config_cache_current() {
  local dst="$1" helper="$2"
  local cache
  cache=$(_codex_config_cache_file)
  [[ -f "$cache" ]] || return 1
  [[ "$(cat "$cache" 2>/dev/null || true)" == "$(_codex_config_signature "$dst" "$helper")" ]]
}

_codex_write_config_cache() {
  local dst="$1" helper="$2"
  local cache tmp
  cache=$(_codex_config_cache_file)
  _dot_sibling_tmp_for "$cache" || return 1
  tmp="$REPLY"

  _codex_config_signature "$dst" "$helper" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv "$tmp" "$cache" || {
    rm -f "$tmp"
    return 1
  }
}

_merge_codex_config() {
  local src="$1" dst="$2"
  local out

  local yq_bin=""
  yq_bin=$(_codex_yq) || {
    _warn "    warning: mikefarah/yq not found; skipping Codex config merge"
    return 1
  }
  command -v python3 >/dev/null 2>&1 || {
    _warn "    warning: python3 not found; skipping Codex config merge"
    return 1
  }

  # If destination is missing, empty, or corrupt TOML, skip the merge and
  # just copy the source layer directly. This handles first-run bootstrap,
  # dangling-symlink migration, and recovery from a corrupted config.
  if [[ ! -s "$dst" ]] || ! "$yq_bin" eval --input-format toml '.' "$dst" >/dev/null 2>&1; then
    _dot_sibling_tmp_for "$dst" || return 1
    out="$REPLY"
    cp "$src" "$out" || {
      rm -f "$out"
      return 1
    }
    mv "$out" "$dst" || {
      rm -f "$out"
      return 1
    }
    return 0
  fi

  local merged_json=""
  merged_json=$(mktemp) || return 1
  _dot_sibling_tmp_for "$dst" || {
    rm -f "$merged_json"
    return 1
  }
  out="$REPLY"

  # yq recursive multiply: source scalars/objects win on conflicts, while
  # destination-only Codex state (CLI counters, migration notices) is preserved.
  # Note: arrays are replaced wholesale, not merged element-by-element.
  #
  # del(.profiles)/del(.profile) then drops stale inline profile tables and the
  # old selector. The multiply alone would never remove them (it only
  # adds/overrides, preserving dest-only keys), so stripping here is what
  # actually completes the migration. It is a harmless no-op on the profile
  # overlay files, which never carry those keys.
  #
  # yq's TOML writer can place root scalars after nested tables, and TOML then
  # interprets those scalars as belonging to the most recent table. The Python
  # renderer keeps scalars ahead of child tables so top-level keys like model
  # stay at the root after a merge.
  if ! "$yq_bin" eval-all --input-format toml --output-format json \
    'select(fileIndex == 0) * select(fileIndex == 1) | del(.profiles) | del(.profile)' \
    "$dst" "$src" >"$merged_json"; then
    _warn "    warning: Codex config merge failed; skipping"
    rm -f "$merged_json"
    return 1
  fi

  if ! python3 "$(_codex_toml_renderer)" render-json "$merged_json" >"$out"; then
    _warn "    warning: Codex config merge failed; skipping"
    rm -f "$out" "$merged_json"
    return 1
  fi

  rm -f "$merged_json"
  mv "$out" "$dst" || {
    rm -f "$out"
    return 1
  }
}

# Apply AgentGuard's complete Codex generation before ordinary dotfiles layers.
#
# Codex stores both declarative hook arrays and mutable trust metadata below the
# same TOML tree. Convert each document to JSON, let AgentGuard's shared jq
# program replace only its prior commands/events, then render the result through
# the existing stable TOML writer. This keeps runtime ownership upstream while
# preserving Codex state and user hooks that dotfiles does not own.
_merge_codex_agentguard_config() {
  local src="$1" dst="$2" reconciler="$3"
  local yq_bin="" dst_json="" src_json="" merged_json="" out=""

  yq_bin=$(_codex_yq) || {
    _warn "    warning: mikefarah/yq not found; skipping Codex config merge"
    return 1
  }
  command -v jq >/dev/null 2>&1 || {
    _warn "    warning: jq not found; skipping Codex AgentGuard reconciliation"
    return 1
  }
  command -v python3 >/dev/null 2>&1 || {
    _warn "    warning: python3 not found; skipping Codex config merge"
    return 1
  }

  dst_json=$(mktemp) || return 1
  src_json=$(mktemp) || {
    rm -f "$dst_json"
    return 1
  }
  merged_json=$(mktemp) || {
    rm -f "$dst_json" "$src_json"
    return 1
  }
  _dot_sibling_tmp_for "$dst" || {
    rm -f "$dst_json" "$src_json" "$merged_json"
    return 1
  }
  out="$REPLY"

  if [[ -s "$dst" ]] &&
    "$yq_bin" eval --input-format toml '.' "$dst" >/dev/null 2>&1; then
    if ! "$yq_bin" eval --input-format toml --output-format json '.' \
      "$dst" >"$dst_json"; then
      _warn "    warning: Codex config conversion failed; preserving target"
      rm -f "$dst_json" "$src_json" "$merged_json" "$out"
      return 1
    fi
  else
    # Preserve an unreadable target until every later conversion succeeds. The
    # final sibling rename recovers it atomically instead of deleting first.
    [[ ! -e "$dst" && ! -L "$dst" ]] ||
      _warn "    warning: corrupt $dst — rebuilding"
    printf '{}\n' >"$dst_json"
  fi

  if ! "$yq_bin" eval --input-format toml --output-format json '.' \
    "$src" >"$src_json" ||
    ! jq -n --sort-keys --indent 2 \
      --arg agent codex \
      --slurpfile d "$dst_json" \
      --slurpfile s "$src_json" \
      -f "$reconciler" >"$merged_json" ||
    [[ ! -s "$merged_json" ]] || ! jq empty "$merged_json" 2>/dev/null ||
    ! python3 "$(_codex_toml_renderer)" render-json "$merged_json" >"$out"; then
    _warn "    warning: Codex AgentGuard reconciliation failed; preserving target"
    rm -f "$dst_json" "$src_json" "$merged_json" "$out"
    return 1
  fi

  rm -f "$dst_json" "$src_json" "$merged_json"
  if [[ ! -L "$dst" ]] && cmp -s "$out" "$dst" 2>/dev/null; then
    rm -f "$out"
    return 0
  fi
  if ! mv "$out" "$dst"; then
    rm -f "$out"
    return 1
  fi
}

_trust_codex_dotfile_hooks() {
  local dst="$1"
  local out
  command -v python3 >/dev/null 2>&1 || return 1
  [[ -s "$dst" ]] || return 1

  local helper
  # The trust helper lives beside the hook source, which matters in tests and
  # bootstrap flows that source the real hook while HOME points at a fixture.
  helper="${_dot_codex_trust_helper:-$(_merge_hook_source codex/refresh-trust.py)}"

  if [[ ! -f "$helper" ]]; then
    _warn "    warning: Codex hook trust helper not found; skipping"
    return 1
  fi

  _dot_sibling_tmp_for "$dst" || return 1
  out="$REPLY"
  if ! python3 "$helper" "$dst" >"$out"; then
    _warn "    warning: Codex hook trust refresh failed; skipping"
    rm -f "$out"
    return 1
  fi

  mv "$out" "$dst" || {
    rm -f "$out"
    return 1
  }
}

_inject_codex_home_trust() {
  # Inject [projects."$HOME"] trust_level = "trusted" after the TOML layers are
  # merged. The source TOML can't use shell variables in table headers, so this
  # step writes the actual home path at merge time rather than baking a username
  # into the dotfiles. Works for both /home/<user> (Linux) and /Users/<user>
  # (macOS) without any per-machine config.
  local dst="$1"
  [[ -s "$dst" ]] || return 0

  local yq_bin tmp toml out
  yq_bin=$(_codex_yq) || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  toml=$(mktemp) || return 0
  tmp=$(mktemp) || {
    rm -f "$toml"
    return 0
  }
  _dot_sibling_tmp_for "$dst" || {
    rm -f "$toml" "$tmp"
    return 0
  }
  out="$REPLY"

  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$HOME" >"$toml"

  if "$yq_bin" eval-all --input-format toml --output-format json \
    'select(fileIndex == 0) * select(fileIndex == 1)' \
    "$dst" "$toml" >"$tmp" &&
    python3 "$(_codex_toml_renderer)" render-json "$tmp" >"$out"; then
    mv "$out" "$dst"
  else
    _warn "    warning: Codex home trust injection failed; skipping"
    rm -f "$out"
  fi

  rm -f "$toml" "$tmp"
}

dot_codex_config_merge() {
  local dst="$HOME/.codex/config.toml"
  local trust_helper agentguard_src="" agentguard_reconciler=""

  # Retirement is independent of the current provider and source signature.
  # Run it before both provider preflight and the cache fast path so stale
  # policy cannot survive an otherwise skipped or partially unavailable update.
  _codex_prune_retired_profiles || return 1

  trust_helper="$(_merge_hook_source codex/refresh-trust.py)"

  agentguard_src=$(_codex_agentguard_source 2>/dev/null) || agentguard_src=""
  agentguard_reconciler=$(_codex_agentguard_reconciler 2>/dev/null) ||
    agentguard_reconciler=""
  if [[ ! -r "$agentguard_src" || ! -r "$agentguard_reconciler" ]]; then
    _warn "    warning: AgentGuard codex integration unavailable — preserving $dst"
    return 1
  fi

  local -a config_sources=()
  local source
  while IFS= read -r source; do
    [[ "$source" == "$agentguard_src" ]] && continue
    config_sources+=("$source")
  done < <(_codex_config_sources)

  # The Codex merge is intentionally heavier than most hooks: yq preserves
  # local CLI-owned state while Python serializes TOML in a shape Codex parses
  # correctly and refreshes hook trust hashes. Cache only a checksum of the
  # source layers, trust helper, and final destination. Any local Codex state
  # edit changes the destination checksum and falls back to the full merge, so
  # this fast path only skips the common no-op update where nothing changed
  # since the last successful merge+trust pass.
  if _codex_config_cache_current "$dst" "$trust_helper"; then
    return 0
  fi

  _log "  Codex"

  # The provider pass reads through a legacy symlink and renames a fully
  # rendered sibling temp over it only after success, preserving Codex-owned
  # state without an unlink-before-refresh failure window.
  _merge_codex_agentguard_config \
    "$agentguard_src" "$dst" "$agentguard_reconciler" || return 1

  for source in "${config_sources[@]}"; do
    _merge_codex_config "$source" "$dst" || return 1
  done

  _inject_codex_home_trust "$dst"

  # Render each named profile into its own ~/.codex/<name>.config.toml overlay.
  # config.toml (built above) had stale [profiles.*] tables and the old selector
  # stripped by _merge_codex_config; each named profile now lives in a
  # standalone file loaded via --profile NAME. The same multiply-merge preserves
  # CLI-owned per-profile state (selected model, [features] toggles).
  local profile profile_dst
  while IFS= read -r profile; do
    profile_dst="$HOME/.codex/$profile.config.toml"
    while IFS= read -r source; do
      _merge_codex_config "$source" "$profile_dst" || return 1
    done < <(_codex_profile_sources "$profile")
  done < <(_codex_profiles)

  _trust_codex_dotfile_hooks "$dst" || return 1
  _codex_write_config_cache "$dst" "$trust_helper" || true
}
