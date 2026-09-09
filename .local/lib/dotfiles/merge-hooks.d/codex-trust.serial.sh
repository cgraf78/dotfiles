# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Prune stale Codex project-trust stanzas from ~/.codex/config.toml.
#
# Codex accumulates [projects.*] trust entries for throwaway locations (/tmp
# scratch dirs, deleted checkouts) and absolute paths from other machines.
# The Python helper removes only entries that can never be legitimate local
# trust; $HOME, the current user's home directories on every platform layout,
# and explicit non-trusted stanzas are always preserved.
#
# This is a serial barrier on purpose: the dev-owned `codex` hook sorts
# immediately before this identity and rewrites the same file, so this prune
# must run after that merge completes instead of racing it in a parallel
# batch. See merge-hooks.d/README.md.

merge() {
  _dot_tool_present codex-trust || return 0
  local dst="$HOME/.codex/config.toml"
  [[ -s "$dst" ]] || return 0

  # Pruning is hygiene, not config convergence: warn and skip on minimal
  # systems without Python rather than failing the whole update.
  command -v python3 >/dev/null 2>&1 || {
    dot_hook_warn "    warning: python3 not found; skipping Codex trust prune"
    return 0
  }

  local hook_dir helper pruned
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  helper="$hook_dir/lib/codex-trust/prune-projects.py"
  if [[ ! -f "$helper" ]]; then
    dot_hook_warn "    warning: Codex trust helper not found; skipping"
    return 1
  fi

  pruned=$(python3 "$helper" "$dst") || {
    dot_hook_warn "    warning: Codex trust prune failed; preserving $dst"
    return 1
  }
  [[ -n "$pruned" ]] || return 0

  dot_hook_log "  Codex trust"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    dot_hook_log "    pruned $path"
  done <<<"$pruned"
}
