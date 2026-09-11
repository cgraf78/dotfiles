# shellcheck shell=bash
# Thin adapter for sourceable assets owned by shdeps-managed dependencies.
#
# Dotfiles should not know where dependencies are installed. shdeps owns that
# contract, including local dev-clone precedence, install roots, and dependency
# filters. These helpers only make the `shdeps dep-*` API convenient from
# shell startup files, hooks, and small launchers that need to source a file.
#
# Hot-path helpers return values via REPLY instead of stdout so callers avoid
# command-substitution forks; only `dot_shdeps_dep_file` itself prints.

# Directory holding shdeps configuration (dependency lists and install hooks).
_dot_shdeps_conf_dir() {
  REPLY="$HOME/.config/shdeps"
}

# Cache directory for `dep-file` resolutions. One small file per dependency
# asset, validated against every resolution input (conf tree, install ledger,
# binary, roots, filter identity) with fork-free file tests, the same
# refresh-on-change contract as `_tool_init`.
_dot_shdeps_dep_cache_dir() {
  case "${XDG_CACHE_HOME:-}" in
    /*) REPLY="$XDG_CACHE_HOME/shdeps/dep-files" ;;
    *)
      if [ -n "${HOME:-}" ]; then
        REPLY="$HOME/.cache/shdeps/dep-files"
      else
        REPLY=""
        return 1
      fi
      ;;
  esac
}

# Resolve the shdeps CLI without running it. Sets REPLY to the invocation to
# use: the token `PATH` when the PATH lookup wins (executed via
# `command shdeps` so shell-function shadowing behaves exactly as before),
# otherwise an absolute binary path. Returns 127 when no shdeps is available.
_dot_shdeps_bin() {
  if command -v shdeps >/dev/null 2>&1; then
    REPLY=PATH
    return 0
  fi

  # Fallback for minimal hook environments that have not loaded PATH yet. Treat
  # env-specific hints as candidates rather than hard requirements; test and
  # hook harnesses often carry a temporary SHDEPS_BIN_DIR while the real shdeps
  # CLI still lives at the normal dotfiles install path.
  local shdeps_bin="${SHDEPS_BIN:-}"
  if [ -n "$shdeps_bin" ] && [ -x "$shdeps_bin" ]; then
    REPLY="$shdeps_bin"
    return 0
  fi

  if [ -n "${SHDEPS_BIN_DIR:-}" ] && [ -x "$SHDEPS_BIN_DIR/shdeps" ]; then
    REPLY="$SHDEPS_BIN_DIR/shdeps"
    return 0
  fi

  if [ -x "$HOME/.local/bin/shdeps" ]; then
    REPLY="$HOME/.local/bin/shdeps"
    return 0
  fi

  return 127
}

# First PATH hit for the shdeps binary, for cache fingerprinting only.
# Execution keeps using `command shdeps`; this only tracks which external
# binary a PATH resolution would reach so reorders and upgrades invalidate.
_dot_shdeps_path_scan() {
  # Manual PATH split: unquoted expansion does not word-split under zsh, and
  # zsh-only split flags would break bash parsing, so strip segments lexically.
  local dir rest
  rest="${PATH:-/usr/local/bin:/usr/bin:/bin}:"
  while [ -n "$rest" ]; do
    dir="${rest%%:*}"
    rest="${rest#*:}"
    [ -n "$dir" ] || dir="."
    if [ -x "$dir/shdeps" ] && [ ! -d "$dir/shdeps" ]; then
      REPLY="$dir/shdeps"
      return 0
    fi
  done
  return 1
}

# Rewrite dep coordinates to a safe cache filename. Any two coordinates that
# sanitize identically share a file but never a hit: the stored coordinates
# are compared on read, so collisions only cost a re-resolution. The
# argument count joins the key so a future shdeps that interprets extra
# CLI args (ignored today) cannot collide with a two-arg resolution.
_dot_shdeps_cache_key() {
  local text="${1:-}@${2:-}@${3:-0}"
  REPLY="${text//[^A-Za-z0-9_.@-]/_}"
}

# Resolution roots shdeps derives from the environment (state ledger,
# development checkouts, installs). Sets REPLY_state/REPLY_dev/REPLY_install
# without forking so the cache hot path stays in-process.
_dot_shdeps_dep_roots() {
  if [ -n "${SHDEPS_STATE_DIR:-}" ]; then
    REPLY_state="$SHDEPS_STATE_DIR"
  elif [ -n "${XDG_STATE_HOME:-}" ]; then
    REPLY_state="$XDG_STATE_HOME/shdeps"
  else
    REPLY_state="${HOME:-}/.local/state/shdeps"
  fi
  REPLY_dev="${SHDEPS_GIT_DEV_DIR:-${HOME:-}/git}"
  REPLY_install="${SHDEPS_INSTALL_DIR:-${HOME:-}/.local/share}"
}

# Validate a cache entry against the live resolution inputs. Sets REPLY to
# the cached asset on a hit; returns 1 on any mismatch, staleness, or
# unreadable input so the caller re-resolves.
# Known limitation: `mgr:`-filtered deps resolve the package manager from
# PATH, whose identity is unkeyed — if two managers ever disagreed on one
# spec, a PATH reorder could serve the other manager's answer. Current
# specs agree under any detected manager, so no live divergence; consider
# fingerprinting detected-manager identity if that changes.
_dot_shdeps_dep_cache_read() {
  local cache="$1" name="$2" rel="$3" conf_dir="$4" bin="$5"
  local cached_name="" cached_rel="" cached_asset=""
  local fp_conf="" fp_bin="" fp_state="" fp_dev="" fp_install=""
  local fp_testplat="" fp_testhost="" fp_host="" fp_ostype="" fp_home=""
  local fp_scan=""
  local path_scan="" conf_file conf_fresh=0 parent=""
  [ -r "$cache" ] || return 1
  {
    IFS= read -r cached_name || return 1
    IFS= read -r cached_rel || return 1
    IFS= read -r cached_asset || return 1
    IFS= read -r fp_conf || return 1
    IFS= read -r fp_bin || return 1
    IFS= read -r fp_state || return 1
    IFS= read -r fp_dev || return 1
    IFS= read -r fp_install || return 1
    IFS= read -r fp_testplat || return 1
    IFS= read -r fp_testhost || return 1
    IFS= read -r fp_host || return 1
    IFS= read -r fp_ostype || return 1
    IFS= read -r fp_home || return 1
    IFS= read -r fp_scan || return 1
  } <"$cache"
  [ "$cached_name" = "$name" ] || return 1
  [ "$cached_rel" = "$rel" ] || return 1
  [ -n "$cached_asset" ] || return 1
  _dot_shdeps_dep_roots
  [ "$fp_conf" = "$conf_dir" ] || return 1
  [ "$fp_bin" = "$bin" ] || return 1
  [ "$fp_state" = "$REPLY_state" ] || return 1
  [ "$fp_dev" = "$REPLY_dev" ] || return 1
  [ "$fp_install" = "$REPLY_install" ] || return 1
  [ "$fp_testplat" = "${SHDEPS_TEST_PLATFORM:-}" ] || return 1
  [ "$fp_testhost" = "${SHDEPS_TEST_HOST:-}" ] || return 1
  [ "$fp_host" = "${HOSTNAME:-}" ] || return 1
  [ "$fp_ostype" = "${OSTYPE:-}" ] || return 1
  [ "$fp_home" = "${HOME:-}" ] || return 1

  # A missing conf tree cannot validate anything; re-resolve instead of
  # trusting a cache whose inputs are unreadable.
  [ -d "$conf_dir" ] || return 1
  # Any input newer than the cache invalidates it. The conf glob covers file
  # edits; the directory tests cover entries appearing or disappearing (new
  # conf files, dev checkouts, installs, manifest ledger updates).
  local _ng_prev=0
  if [ -n "${ZSH_VERSION:-}" ]; then
    [[ -o nullglob ]] && _ng_prev=1
    setopt nullglob
  fi
  for conf_file in "$conf_dir"/*.conf; do
    if [ "$conf_file" -nt "$cache" ]; then
      conf_fresh=1
      break
    fi
  done
  if [ -n "${ZSH_VERSION:-}" ] && [ "$_ng_prev" -eq 0 ]; then
    unsetopt nullglob
  fi
  [ "$conf_fresh" -eq 0 ] || return 1
  [ ! "$conf_dir" -nt "$cache" ] || return 1

  if [ "$bin" = PATH ]; then
    _dot_shdeps_path_scan || return 1
    path_scan="$REPLY"
    # Identity first, then mtime: a PATH reorder serves a different binary
    # whose answer must not reuse this entry even when nothing is newer.
    [ "$fp_scan" = "$path_scan" ] || return 1
    [ ! "$path_scan" -nt "$cache" ] || return 1
  else
    [ -x "$bin" ] || return 1
    [ ! "$bin" -nt "$cache" ] || return 1
  fi

  [ ! "$REPLY_state" -nt "$cache" ] || return 1
  [ ! "$REPLY_state/manifest" -nt "$cache" ] || return 1
  [ ! "$REPLY_dev" -nt "$cache" ] || return 1
  [ ! "$REPLY_install" -nt "$cache" ] || return 1
  # Walk every install parent so leaf add/remove under deep dep paths
  # (install/a/b/...) invalidates; a first-component-only check misses it.
  parent="$name"
  while [ "$parent" != "${parent%/*}" ]; do
    parent="${parent%/*}"
    if [ -e "$REPLY_install/$parent" ]; then
      [ ! "$REPLY_install/$parent" -nt "$cache" ] || return 1
    fi
  done

  [ -f "$cached_asset" ] && [ -r "$cached_asset" ] || return 1
  REPLY="$cached_asset"
}

_dot_shdeps_dep_cache_write() {
  local cache="$1" name="$2" rel="$3" asset="$4" conf_dir="$5" bin="$6"
  local dir tmp scan=""
  [ -n "$asset" ] || return 0
  dir="${cache%/*}"
  mkdir -p -- "$dir" 2>/dev/null || return 0
  tmp=$(mktemp "${cache}.XXXXXX" 2>/dev/null) || return 0
  _dot_shdeps_dep_roots
  # Record which binary a PATH resolution reaches so a reorder across two
  # shdeps binaries invalidates on read. Empty for absolute binaries (the
  # stored path itself is the identity) and function-shadowed shdeps (whose
  # scan fails on read too, forcing a re-resolution as before).
  if [ "$bin" = PATH ]; then
    _dot_shdeps_path_scan && scan="$REPLY" || scan=""
  fi
  {
    printf '%s\n' "$name" "$rel" "$asset"
    printf '%s\n' "$conf_dir" "$bin" "$REPLY_state" "$REPLY_dev" \
      "$REPLY_install" "${SHDEPS_TEST_PLATFORM:-}" "${SHDEPS_TEST_HOST:-}" \
      "${HOSTNAME:-}" "${OSTYPE:-}" "${HOME:-}" "$scan"
  } >"$tmp" 2>/dev/null || {
    rm -f -- "$tmp"
    return 0
  }
  mv -f -- "$tmp" "$cache" 2>/dev/null || rm -f -- "$tmp"
}

dot_shdeps_dep_file() {
  local conf_dir bin cache_dir cache key out rc=0
  _dot_shdeps_conf_dir
  conf_dir="$REPLY"
  _dot_shdeps_bin || return 127
  bin="$REPLY"

  if _dot_shdeps_dep_cache_dir; then
    cache_dir="$REPLY"
    _dot_shdeps_cache_key "${1:-}" "${2:-}" "$#"
    key="$REPLY"
    cache="$cache_dir/$key"
    if _dot_shdeps_dep_cache_read \
      "$cache" "${1:-}" "${2:-}" "$conf_dir" "$bin"; then
      printf '%s\n' "$REPLY"
      return 0
    fi
  else
    cache=""
  fi

  if [ "$bin" = PATH ]; then
    out=$(SHDEPS_CONF_DIR="$conf_dir" command shdeps dep-file "$@") || rc=$?
  else
    out=$(SHDEPS_CONF_DIR="$conf_dir" "$bin" dep-file "$@") || rc=$?
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  [ "$rc" -eq 0 ] || return "$rc"
  [ -n "$out" ] || return 0
  if [ -n "$cache" ]; then
    _dot_shdeps_dep_cache_write "$cache" "${1:-}" "${2:-}" "$out" \
      "$conf_dir" "$bin"
  fi
  return 0
}

dot_shdeps_dep_source() {
  local asset
  asset=$(dot_shdeps_dep_file "$@") || return
  [ -n "$asset" ] || return 1
  # shellcheck disable=SC1090 # dependency asset path is resolved by shdeps.
  . "$asset"
}

# Resolve one of AgentGuard's native agent-integration assets.
#
# Keep the repository and provider layout behind this single boundary. Merge
# hooks should know only which runtime they activate and which native file type
# that runtime consumes; AgentGuard owns the event vocabulary, matchers,
# commands, and adapter implementation under the resolved directory. Besides
# keeping dotfiles thin, this makes normal shdeps rules (development-clone
# precedence, install roots, filters, and fleet updates) apply uniformly to
# every supported agent.
#
# Args: $1 = agent directory name, $2 = asset filename
# Prints: resolved dependency path on stdout
dot_agentguard_integration_file() {
  local agent="$1" asset="$2"
  dot_shdeps_dep_file \
    cgraf78/agentguard \
    "share/agentguard/integrations/$agent/$asset"
}

# Print the provider-owned first-line marker for AgentGuard's OpenCode adapter.
# The installer and doctor share this cross-repository identity rather than
# duplicating its literal at each consumer boundary.
dot_agentguard_opencode_marker() {
  printf '%s\n' '// agentguard-managed:opencode-plugin'
}
