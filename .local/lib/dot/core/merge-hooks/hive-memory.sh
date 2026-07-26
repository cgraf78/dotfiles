# shellcheck shell=bash
# Initialize Hive Memory store state and verify managed config still loads.
#
# Dotfiles owns bootstrap and the static agent guidance generated from
# merge-hooks.d/agent-rules/rules.d, while `hm hook` owns dynamic, project-aware
# memory context. Do not install generated include markers into agent rule
# targets: adapter-specific include blocks would make the generated rule body
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
  _hive_memory_config || return 0
  config="$REPLY"

  command -v hm >/dev/null 2>&1 || return 0
  [[ -f "$config" ]] || return 0

  _log "  Hive Memory"

  _hive_memory_init_default_store "$config"
  _hive_memory_check_config "$config"
}
