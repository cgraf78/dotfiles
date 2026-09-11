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
#
# The ~80ms Python prune is skipped when the prune verdict cannot have
# changed: the stamp records the config path, its checksum, and every
# project entry's existence bit, and Python runs unless the config is
# older than the stamp with a matching fingerprint. Only a successful
# prune writes the stamp. Anything the conservative header scan cannot
# prove (escapes, dotted keys, odd tables) fails closed into a prune,
# so merged output is identical with or without the skip.

_codex_trust_stamp_file() {
  local base=${XDG_CACHE_HOME:-}
  case $base in
    /*) ;;
    *) base=$HOME/.cache ;;
  esac
  printf '%s\n' "$base/dot/merge-codex-trust.stamp"
}

# Print the prune fingerprint (config path, config checksum, one
# existence line per project header), or fail. Mirrors the helper's
# lexical normalization (trailing slashes stripped, root kept) and its
# existence test (`-e` follows symlinks like `os.path.exists`). Exists
# bits make filesystem-only changes (a deleted checkout) re-run the
# prune even when the config bytes are untouched. Any header the scan
# cannot prove -- escapes, literal-quote content, bare keys, dotted
# keys, array tables, or any other `projects` mention -- fails closed
# into a prune.
_codex_trust_fingerprint() {
  local dst=$1 sum fp line inner path bare=0
  local sq="'" dq='"'
  command -v cksum >/dev/null 2>&1 || return 1
  sum=$(cksum <"$dst" 2>/dev/null) || return 1
  fp="path=$dst"$'\n'"$sum"
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      '[projects]')
        # Bare parent table, as the helper itself renders: only blank
        # lines may follow until the next header, since any other
        # content may be a dotted entry this scan cannot prove.
        bare=1
        continue
        ;;
      '[projects.'*']')
        inner=${line#'[projects.'}
        inner=${inner%']'}
        case $inner in
          "$dq"*"$dq")
            path=${inner#"$dq"}
            path=${path%"$dq"}
            case $path in *"$dq"* | *\\*) return 1 ;; esac
            ;;
          "$sq"*"$sq")
            path=${inner#"$sq"}
            path=${path%"$sq"}
            case $path in *"$sq"*) return 1 ;; esac
            ;;
          *) return 1 ;;
        esac
        [[ $path == /* ]] || return 1
        while [[ $path != / && $path == */ ]]; do
          path=${path%/}
        done
        if [[ -e $path ]]; then
          fp+=$'\n'"1 $path"
        else
          fp+=$'\n'"0 $path"
        fi
        bare=0
        ;;
      '['*)
        bare=0
        case $line in *projects*) return 1 ;; esac
        ;;
      *)
        if ((bare == 1)); then
          [[ -z $line ]] || return 1
        else
          case $line in *projects*) return 1 ;; esac
        fi
        ;;
    esac
  done <"$dst" 2>/dev/null || return 1
  printf '%s\n' "$fp"
}

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

  local hook_dir helper pruned stamp fp fresh stored tmp
  hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return 1
  helper="$hook_dir/lib/codex-trust/prune-projects.py"
  if [[ ! -f "$helper" ]]; then
    dot_hook_warn "    warning: Codex trust helper not found; skipping"
    return 1
  fi

  stamp=$(_codex_trust_stamp_file)
  if [[ -f $stamp && -r $stamp && $dst -ot $stamp ]] &&
    fp=$(_codex_trust_fingerprint "$dst") 2>/dev/null &&
    stored=$(<"$stamp") 2>/dev/null &&
    [[ $fp == "$stored" ]]; then
    return 0
  fi

  pruned=$(python3 "$helper" "$dst") || {
    dot_hook_warn "    warning: Codex trust prune failed; preserving $dst"
    return 1
  }
  fresh=$(_codex_trust_fingerprint "$dst") 2>/dev/null || fresh=
  if [[ -n $fresh ]] && mkdir -p "${stamp%/*}" 2>/dev/null &&
    tmp=$(mktemp "${stamp}.tmp.XXXXXX" 2>/dev/null) &&
    printf '%s\n' "$fresh" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$stamp" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
  [[ -n "$pruned" ]] || return 0

  dot_hook_log "  Codex trust"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    dot_hook_log "    pruned $path"
  done <<<"$pruned"
}
