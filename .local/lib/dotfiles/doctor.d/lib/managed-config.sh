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

# Append to the caller's `bad` array every TOML file that Python's tomllib
# rejects, or fail when python3 is missing or predates tomllib (3.11; older
# macOS ships 3.9) so the caller can fall back to yq. One python3 reads
# them all and prints the index of each bad one, which survives any byte a
# file name can hold, then a closing line: a python3 that exits 0 without
# running the script (a shim or wrapper) prints none and also falls back,
# rather than passing every file unchecked. -I -S keeps the user's PYTHON*
# environment and site packages out: tomllib is in the standard library.
_dr_tomllib_unparsable() {
  local out index closed=0
  local -a files=("$@") found=()
  out=$(python3 -I -S -c '
import sys
try:
    import tomllib
except ImportError:
    sys.exit(2)
for index, name in enumerate(sys.argv[1:]):
    try:
        with open(name, "rb") as handle:
            tomllib.load(handle)
    except Exception:
        print(index)
print("done")
' "$@" </dev/null 2>/dev/null) || return 1
  while IFS= read -r index; do
    case $index in
      done) closed=1 ;;
      *[!0-9]* | '') return 1 ;;
      *) found+=("${files[index]}") ;;
    esac
  done <<<"$out"
  ((closed == 1)) || return 1
  bad+=(${found[@]+"${found[@]}"})
}

# Validate every fragment the merge hooks read, in the parser its hooks
# use. JSON goes through one jq call per file: jq reads several files as one
# stream, so a combined call can join a truncated file with the next one and
# pass. TOML and YAML go through mikefarah yq, except the vscode family's
# extensions.d TOML (direct and .replace/ files): those are extension
# manifests the vscode-exts provider reads with Python's tomllib, which
# rejects duplicate keys and redefined tables that yq accepts, so tomllib
# judges them where python3 has it. JSONC fragments
# (comments allowed) are skipped, and so are the vscode family's `.json`
# fragments, which its hook strips of comments before merging.
_dr_check_fragments() {
  local root=$HOME/.config/dot/merge-hooks.d file yq='' summary='' toml_checked=0
  local -a json=() toml=() vscode_toml=() yaml=() bad=() items=()

  [[ -d $root ]] || return 0
  # -L follows the overlay symlinks that carry most fragments.
  while IFS= read -r -d '' file; do
    case $file in
      "$root"/vscode/*.json) ;;
      "$root"/vscode/extensions.d/*.toml) vscode_toml+=("$file") ;;
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
  # Without tomllib the provider cannot run either, but yq still names a
  # truncated manifest, so the manifests join the yq call.
  if ((${#vscode_toml[@]} > 0)); then
    if _dr_tomllib_unparsable "${vscode_toml[@]}"; then
      toml_checked=${#vscode_toml[@]}
    else
      toml+=("${vscode_toml[@]}")
    fi
  fi
  if ((${#toml[@]} + ${#yaml[@]} > 0)); then
    if _dr_mikefarah_yq; then
      yq=$REPLY
      if ((${#toml[@]} > 0)); then
        _dr_yq_unparsable "$yq" toml "${toml[@]}"
        toml_checked=$((toml_checked + ${#toml[@]}))
      fi
    elif ((${#toml[@]} == 0)); then
      _dr_skip "merge-hook YAML fragments unchecked" "mikefarah yq not installed"
    elif ((${#yaml[@]} == 0)); then
      _dr_skip "merge-hook TOML fragments unchecked" "mikefarah yq not installed"
    else
      _dr_skip "merge-hook TOML and YAML fragments unchecked" "mikefarah yq not installed"
    fi
  fi
  ((toml_checked > 0)) && summary+="${summary:+, }$toml_checked TOML"
  if [[ -n $yq ]] && ((${#yaml[@]} > 0)); then
    _dr_yq_unparsable "$yq" yaml "${yaml[@]}"
    summary+="${summary:+, }${#yaml[@]} YAML"
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
    "dot update skips them, or the whole config they feed, until fixed: check each with 'jq empty <file>' or 'yq <file>', and vscode extension manifests with 'python3 -c \"import sys, tomllib; tomllib.load(sys.stdin.buffer)\" < <file>'" \
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
      "they are in $(_dr_tilde "$dir"): check each with 'bash -n <file>' and make sure it defines prepare()"
  fi
}

_dr_check_managed_config() {
  _dr_section "Managed configuration"
  _dr_check_fragments
  _dr_check_pre_sync_extensions
  _dr_check_base_config_temporaries
}
