# shellcheck shell=bash
# dot doctor: inputs and leftovers of managed configuration.
#
# Merge hooks layer JSON fragments into application configs and skip a layer
# that does not parse with only a warning in the update log, so a broken
# fragment silently stops applying. Pre-sync extensions run before every
# repository sync, and one that cannot load aborts the sync. Atomic config
# writes leave a `<file>.tmp.XXXXXX` sibling behind when an update is
# interrupted. Each check is a handful of processes over small, fixed trees.

# Agent config locations whose files merge hooks rewrite through sibling
# temporaries: directories, plus `~/.claude.json` beside them in HOME.
_DR_MANAGED_AGENT_DIRS=(.claude .codex .config/muse .gemini .grok .config/opencode)
_DR_MANAGED_AGENT_FILES=(.claude.json)

# Leftover temporaries younger than this many minutes may belong to an
# update that is still running.
_DR_MANAGED_TMP_MINUTES=10

# Validate every JSON fragment the merge hooks read, one jq call per file:
# jq reads several files as one stream, so a combined call can join a
# truncated file with the next one and pass. JSONC fragments (comments
# allowed) are not JSON and are skipped, and so is the vscode family, whose
# hook strips comments from its `.json` fragments before merging.
_dr_check_json_fragments() {
  local root=$HOME/.config/dot/merge-hooks.d file sample=''
  local -a files=() bad=()

  [[ -d $root ]] || return 0
  if ! command -v jq >/dev/null 2>&1; then
    _dr_skip "merge-hook JSON fragments unchecked" "jq not installed"
    return 0
  fi
  # -L follows the overlay symlinks that carry most fragments.
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find -L "$root" -path "$root/vscode" -prune -o -type f -name '*.json' -print0 2>/dev/null)
  ((${#files[@]} > 0)) || return 0

  for file in "${files[@]}"; do
    jq empty "$file" >/dev/null 2>&1 || bad+=("$file")
  done
  if ((${#bad[@]} == 0)); then
    _dr_ok "merge-hook JSON fragments parse" "${#files[@]} file(s)"
    return 0
  fi
  for file in "${bad[@]:0:3}"; do
    sample+=${sample:+; }$(_dr_tilde "$file")
  done
  if ((${#bad[@]} > 3)); then
    sample+="; and $((${#bad[@]} - 3)) more"
  fi
  _dr_warn "${#bad[@]} merge-hook JSON fragment(s) do not parse" \
    "$sample; those layers are skipped until fixed (try 'jq empty <file>')"
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
    _dr_fail "pre-sync extensions are broken: $list" \
      "dot update aborts repository sync until they are fixed (try 'bash -n <file>')"
  fi
}

# Report temporaries an interrupted atomic write left next to managed agent
# configs. Only files past the in-flight window count, and nothing is
# deleted: whether a leftover still matters is the owner's call.
_dr_check_config_temporaries() {
  local dir file sample=''
  local -a candidates=() stale=()

  for dir in "${_DR_MANAGED_AGENT_DIRS[@]}"; do
    for file in "$HOME/$dir"/*.tmp.??????; do
      [[ -f $file && ! -L $file ]] && candidates+=("$file")
    done
  done
  for dir in "${_DR_MANAGED_AGENT_FILES[@]}"; do
    for file in "$HOME/$dir".tmp.??????; do
      [[ -f $file && ! -L $file ]] && candidates+=("$file")
    done
  done
  ((${#candidates[@]} > 0)) || return 0
  while IFS= read -r file; do
    [[ -n $file ]] && stale+=("$file")
  done < <(find "${candidates[@]}" -maxdepth 0 -mmin +"$_DR_MANAGED_TMP_MINUTES" 2>/dev/null)
  ((${#stale[@]} > 0)) || return 0
  for file in "${stale[@]:0:3}"; do
    sample+=${sample:+; }$(_dr_tilde "$file")
  done
  if ((${#stale[@]} > 3)); then
    sample+="; and $((${#stale[@]} - 3)) more"
  fi
  _dr_warn "${#stale[@]} leftover config temporary file(s)" \
    "$sample; left by an interrupted update: delete them once no 'dot update' is running"
}

_dr_check_managed_config() {
  _dr_section "Managed configuration"
  _dr_check_json_fragments
  _dr_check_pre_sync_extensions
  _dr_check_config_temporaries
}
