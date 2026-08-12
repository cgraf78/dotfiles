# shellcheck shell=bash
# Initialize Hive Memory store state and verify managed config still loads.
#
# Dotfiles owns bootstrap and the static guidance selected from
# ~/.config/agent-rules/rules.d; the standalone agent-rules-sync provider owns
# publishing that selection. `hm hook` separately owns dynamic, project-aware
# memory context. Do not install generated include markers into agent rule
# targets: adapter-specific include blocks would make the shared generated body
# noisy and ambiguous. Hooks are the runtime context path.

if ! declare -F _dot_xdg_path >/dev/null 2>&1; then
  _dot_hive_memory_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../xdg.sh disable=SC1091
  . "$_dot_hive_memory_hook_dir/../xdg.sh"
fi

_hive_memory_config() {
  # Match Hive's public config precedence. An explicitly set override keeps its
  # existing semantics, including an empty or relative value; only XDG base
  # directories require an absolute path.
  if [[ "${HIVE_MEMORY_CONFIG+x}" == x ]]; then
    REPLY="$HIVE_MEMORY_CONFIG"
  else
    _dot_xdg_path config "hive-memory/config.toml" || return
  fi
}

_hive_memory_warn() {
  _warn "    warning: Hive Memory $1"
}

_hive_memory_remove_legacy_core() {
  [[ -n "${HOME:-}" ]] || return 0

  local legacy_dir="$HOME/.local/share/hive-memory/bin"
  local legacy_core="$legacy_dir/hm-core"
  local stable_core="$HOME/.local/share/cgraf78/hive-memory/hm"
  local launcher="$HOME/.local/bin/hm"
  local launcher_marker
  local expected_marker="# Dotfiles-owned front door for the generic \`hm\` binary."

  # This migration must be a no-op forever after it succeeds. Returning before
  # even probing the replacement also avoids removing an independently created
  # empty namespace on every future `dot update`.
  [[ -e "$legacy_core" || -L "$legacy_core" ]] || return 0

  # A failed capability preflight skips dependency convergence but still runs
  # merge hooks so unrelated configuration can repair itself. Keep the legacy
  # core in that case: the stable payload may work now, but an older Shdeps is
  # still capable of replacing the tracked launcher on a later run. The update
  # orchestrator exports this proof only after probing the active binary.
  [[ "${DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION:-0}" == 1 ]] || return 0

  # Older dotfiles copied every Hive release into a second private path so a
  # generated ~/.local/bin/hm symlink could point at the launcher. The launcher
  # is now tracked directly and delegates to Shdeps' fixed archive payload, so
  # that copy becomes unreachable duplicate storage only after the replacement
  # is demonstrably usable. Merge hooks still run when the earlier dependency
  # phase fails, so deleting first could turn a transient network failure into
  # a missing `hm` command. Exercise the tracked launcher's normal fixed-path
  # delegation before removing only the old dotfiles-owned filename.
  # Do not trust an old generated symlink, an unrelated user command, or a
  # partially written replacement to authorize deletion. The new front door is
  # a tracked regular file with a stable ownership marker; verify that shape
  # before exercising its normal fixed-path delegation.
  [[ -f "$launcher" && ! -L "$launcher" ]] || return 0
  {
    IFS= read -r _
    IFS= read -r launcher_marker
  } <"$launcher" || return 0
  [[ "$launcher_marker" == "$expected_marker" ]] || return 0

  if [[ ! -f "$stable_core" || -L "$stable_core" || ! -x "$stable_core" ||
    ! -x "$launcher" ]] ||
    ! "$launcher" --version >/dev/null 2>&1; then
    return 0
  fi
  if ! rm -f -- "$legacy_core"; then
    _hive_memory_warn "could not remove obsolete core copy: $legacy_core"
    return 0
  fi
  rmdir "$legacy_dir" "${legacy_dir%/*}" 2>/dev/null || true
}

_hive_memory_default_store_spec() {
  local config="$1"

  python3 - "$config" <<'PY'
import os
import sys
import tomllib

config_path = sys.argv[1]
with open(config_path, "rb") as f:
    config = tomllib.load(f)

store_name = config.get("default_store", "")
store = config.get("stores", {}).get(store_name, {})
root = store.get("root", "")

if not store_name or not root:
    raise SystemExit(1)

print(
    "\n".join(
        [
            store_name,
            os.path.expandvars(root),
            store.get("description", ""),
            store.get("sensitivity", ""),
            "__DOT_HIVE_MEMORY_SPEC_END__",
        ]
    )
)
PY
}

_hive_memory_cloud_root_for() {
  local root="$1" gdrive

  # Cloud-root policy is HOME-relative. An absolute XDG config remains usable
  # without HOME, but there is no personal cloud root to classify in that
  # environment.
  [[ -n "${HOME:-}" ]] || return 1
  gdrive="$HOME/gdrive"

  case "$root" in
    "$gdrive" | "$gdrive"/*)
      printf '%s\n' "$gdrive"
      return 0
      ;;
  esac

  return 1
}

_hive_memory_init_default_store() {
  local config="$1"
  local spec store root description sensitivity line
  local -a fields=()

  if ! spec=$(_hive_memory_default_store_spec "$config" 2>/dev/null); then
    _hive_memory_warn "default store config is incomplete"
    return 0
  fi

  # Preserve intentionally empty optional fields. Bash's whitespace splitting
  # would collapse a missing description and shift sensitivity into the wrong
  # flag, so the Python side emits one field per line plus a sentinel that keeps
  # command substitution from trimming meaningful trailing empties.
  while IFS= read -r line; do
    [[ "$line" == "__DOT_HIVE_MEMORY_SPEC_END__" ]] && break
    fields+=("$line")
  done <<<"$spec"

  store="${fields[0]:-}"
  root="${fields[1]:-}"
  description="${fields[2]:-}"
  sensitivity="${fields[3]:-}"
  [[ -n "$store" && -n "$root" ]] || return 0

  [[ -f "$root/manifest.toml" ]] && return 0

  # Do not create a cloud-drive mount itself. Configs under ~/gdrive are personal
  # overlay policy; if that sync root is absent, warn and leave recovery to the
  # user. Non-cloud roots can be initialized normally so future base or overlay
  # configs are not forced into the same storage shape.
  local cloud_root
  if cloud_root=$(_hive_memory_cloud_root_for "$root") && [[ ! -d "$cloud_root" ]]; then
    _hive_memory_warn "cloud root not available: $cloud_root"
    return 0
  fi

  local -a init_args=(stores init "$store" --root "$root")
  [[ -n "$description" ]] && init_args+=(--description "$description")
  [[ -n "$sensitivity" ]] && init_args+=(--sensitivity "$sensitivity")

  if ! hm "${init_args[@]}" >/dev/null 2>&1; then
    _hive_memory_warn "store initialization failed"
  fi
}

_hive_memory_check_config() {
  local config="$1"

  # `dot update` is the convergence path, not the diagnostic path. Keep this
  # check to config parsing and store alias loading; broader store/cache scans
  # belong in `dot doctor` or explicit `hm doctor` runs.
  if ! hm --config "$config" stores list --json >/dev/null 2>&1; then
    _hive_memory_warn "config check reported issues"
  fi
}

merge() {
  local config
  _hive_memory_remove_legacy_core
  _hive_memory_config || return 0
  config="$REPLY"

  command -v hm >/dev/null 2>&1 || return 0
  [[ -f "$config" ]] || return 0

  _log "  Hive Memory"

  _hive_memory_init_default_store "$config"
  _hive_memory_check_config "$config"
}
