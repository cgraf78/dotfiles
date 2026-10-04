# shellcheck shell=bash
# dot doctor: inputs and leftovers of managed configuration.
#
# Merge hooks layer JSON, TOML, and YAML fragments into application configs
# and skip a layer that does not parse with only a warning in the update
# log, so a broken fragment silently stops applying. Pre-sync extensions run
# before every repository sync, and one that cannot load aborts the sync.
# Atomic config writes leave a sibling temporary behind when an update is
# interrupted (doctor.d/lib/config-temporaries.sh). Each check is a handful
# of processes over small, fixed trees.

dot_doctor_source doctor.d/lib/config-temporaries.sh || return

# Report via REPLY a mikefarah yq, the parser the TOML and YAML merge hooks
# use (from PATH, or shdeps' bin directory), or fail. Another program named
# yq (the Python wrapper) reads different flags and would flag every file.
# This mirrors the hooks' `_merge_hook_mikefarah_yq`, which lives behind the
# hook runtime in merge-hooks.d/lib/compat.sh and cannot be loaded here.
_dr_mikefarah_yq() {
  local candidate version
  for candidate in "$(command -v yq 2>/dev/null)" "$HOME/.local/bin/yq"; do
    [[ -n $candidate && -x $candidate && ! -d $candidate ]] || continue
    version=$("$candidate" --version 2>/dev/null </dev/null) || continue
    [[ $version == *mikefarah* ]] || continue
    REPLY=$candidate
    return 0
  done
  return 1
}

# Append to the caller's `bad` array every file of FORMAT (toml or yaml)
# that yq cannot parse. One yq call reads them all, each as its own
# document stream, and fails on the first bad one; only then does a second
# pass name every bad file, one call each.
_dr_yq_unparsable() {
  local yq=$1 format=$2 file
  shift 2
  "$yq" eval-all -p "$format" -o json 'select(false)' "$@" \
    </dev/null >/dev/null 2>&1 && return 0
  for file; do
    "$yq" eval -p "$format" -o json 'select(false)' "$file" \
      </dev/null >/dev/null 2>&1 || bad+=("$file")
  done
}

# Validate every fragment the merge hooks read, in the parser its hooks
# use. JSON goes through one jq call per file: jq reads several files as one
# stream, so a combined call can join a truncated file with the next one and
# pass. TOML and YAML go through mikefarah yq. JSONC fragments (comments
# allowed) are skipped, and so are the vscode family's `.json` fragments,
# which its hook strips of comments before merging.
_dr_check_fragments() {
  local root=$HOME/.config/dot/merge-hooks.d file yq='' summary=''
  local -a json=() toml=() yaml=() bad=() items=()

  [[ -d $root ]] || return 0
  # -L follows the overlay symlinks that carry most fragments.
  while IFS= read -r -d '' file; do
    case $file in
      "$root"/vscode/*.json) ;;
      *.json) json+=("$file") ;;
      *.toml) toml+=("$file") ;;
      *.yml | *.yaml) yaml+=("$file") ;;
    esac
  done < <(find -L "$root" -type f \( -name '*.json' -o -name '*.toml' \
    -o -name '*.yml' -o -name '*.yaml' \) -print0 2>/dev/null)

  if ((${#json[@]} > 0)); then
    if command -v jq >/dev/null 2>&1; then
      for file in "${json[@]}"; do
        jq empty "$file" >/dev/null 2>&1 || bad+=("$file")
      done
      summary+="${#json[@]} JSON"
    else
      _dr_skip "merge-hook JSON fragments unchecked" "jq not installed"
    fi
  fi
  if ((${#toml[@]} + ${#yaml[@]} > 0)); then
    if _dr_mikefarah_yq; then
      yq=$REPLY
      if ((${#toml[@]} > 0)); then
        _dr_yq_unparsable "$yq" toml "${toml[@]}"
        summary+="${summary:+, }${#toml[@]} TOML"
      fi
      if ((${#yaml[@]} > 0)); then
        _dr_yq_unparsable "$yq" yaml "${yaml[@]}"
        summary+="${summary:+, }${#yaml[@]} YAML"
      fi
    else
      _dr_skip "merge-hook TOML and YAML fragments unchecked" "mikefarah yq not installed"
    fi
  fi
  [[ -n $summary ]] || return 0

  if ((${#bad[@]} == 0)); then
    _dr_ok "merge-hook fragments parse" "$summary file(s)"
    return 0
  fi
  for file in "${bad[@]}"; do
    items+=("$(_dr_tilde "$file")")
  done
  _dr_list_row warn "${#bad[@]} merge-hook fragment(s) do not parse" \
    "dot update skips them, or the whole config they feed, until fixed: check each with 'jq empty <file>' or 'yq <file>'" \
    "${items[@]}"
}

# Every pre-sync extension must parse and define prepare(): Dot loads them
# before each repository sync and aborts the sync when one fails.
_dr_check_pre_sync_extensions() {
  local dir=$DOT_EXTENSIONS_DIR/pre-sync.d file name count=0 list=''
  local -a broken=()

  [[ -d $dir ]] || return 0
  for file in "$dir"/*.sh; do
    [[ -f $file ]] || continue
    count=$((count + 1))
    _dr_one_line "${file##*/}"
    name=$REPLY
    # Dot runs them with a Bash 4+ interpreter; the worker's own Bash is
    # one, while the first `bash` on PATH may be macOS's 3.2.
    if ! "$BASH" -n "$file" >/dev/null 2>&1; then
      broken+=("$name (syntax error)")
    elif ! grep -Eq '^[[:space:]]*(function[[:space:]]+prepare([[:space:]]|\(|\{|$)|prepare[[:space:]]*\(\))' "$file" 2>/dev/null; then
      broken+=("$name (no prepare function)")
    fi
  done
  ((count > 0)) || return 0
  if ((${#broken[@]} == 0)); then
    _dr_ok "pre-sync extensions load" "$count extension(s)"
  else
    for name in "${broken[@]}"; do
      list+=${list:+; }$name
    done
    _dr_hint_row fail "pre-sync extensions are broken: $list" \
      "dot update aborts repository sync until they are fixed" \
      "check each with 'bash -n <file>' and make sure it defines prepare()"
  fi
}

_dr_check_managed_config() {
  _dr_section "Managed configuration"
  _dr_check_fragments
  _dr_check_pre_sync_extensions
  _dr_check_base_config_temporaries
}
