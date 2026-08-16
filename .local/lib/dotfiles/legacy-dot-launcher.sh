#!/usr/bin/env bash
# Smart dotfiles manager.
#
# One base bare repo at ~/.dotfiles, plus overlay repos discovered
# from config files in ~/.config/dot/overlays.d/*.conf.
#
# Commands:
#   dot update [-v] [-f]       Sync everything (-v: verbose, -f: force)
#   dot pull                   Same as update
#   dot fetch/push/status/diff Operates on base + all active overlays
#   dot cron                   Show installed cron entries

set -euo pipefail

# Pre-scan flags that affect shdeps before sourcing init.sh. `dot update`
# bootstraps shdeps before the full command parser runs, so bootstrap-visible
# env like force and quiet has to be exported here as well as in the normal
# parser below.
case "${1:-}" in
  update | pull)
    for _arg in "$@"; do
      case "$_arg" in
        -f | --force)
          export SHDEPS_FORCE=1
          ;;
        --cron | --quiet)
          export DOT_QUIET=1
          export SHDEPS_QUIET=1
          ;;
      esac
    done
    unset _arg
    ;;
esac

# shellcheck source=../dot/core/init.sh
. "$HOME/.local/lib/dot/core/init.sh"

# Read-only commands skip shdeps bootstrap — non-matching overlay dirs simply
# won't exist, so unfiltered discovery is harmless. Updates acquire their
# process-wide lock before bootstrapping dependencies and then discover after
# shdeps supplies the configured platform/host filters.
case "${1:-}" in
  update | pull | "" | -h | --help | help) ;;
  doctor)
    # Doctor reports malformed descriptors as a health failure instead of
    # exiting before it can render an actionable section.
    _discover_overlays || true
    ;;
  *)
    _discover_overlays || exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Global flags
# ---------------------------------------------------------------------------

: "${DOT_QUIET:=0}"
: "${DOT_VERBOSE:=0}"

# ---------------------------------------------------------------------------
# Commands that work without the bare repo
# ---------------------------------------------------------------------------

case "${1:-}" in
  update)
    shift
    _dot_update_lock_rc=0
    _dot_update_lock_acquire "$@" || _dot_update_lock_rc=$?
    if [[ "$_dot_update_lock_rc" -ne 0 ]]; then
      [[ "$_dot_update_lock_rc" -eq 75 && "${DOT_UPDATE_LOCK_CRON_MODE:-0}" -eq 1 ]] && exit 0
      exit "$_dot_update_lock_rc"
    fi
    _ensure_shdeps
    _discover_overlays || exit 1
    _preflight_local_overlays || exit 1
    _dot_update_rc=0
    _dot_update "$@" || _dot_update_rc=$?
    exit "$_dot_update_rc"
    ;;
  pull)
    shift
    exec "$0" update "$@"
    ;;
  cron)
    crontab -l 2>/dev/null || echo "  no crontab installed"
    exit 0
    ;;
  doctor)
    # Scope every diagnostic and child-tool tempfile beneath one registered
    # operation root. This covers future plain mktemp sites as well as today's
    # files and cache directories without duplicating registration at each use.
    _dot_cleanup_install_owner_traps
    if ! _dot_cleanup_mktemp -d \
      "${TMPDIR:-/tmp}/dot-doctor.XXXXXX" 2>/dev/null; then
      _warn "  error: unable to create private dot doctor scratch"
      exit 1
    fi
    TMPDIR=$REPLY
    export TMPDIR
    _dot_doctor
    exit $?
    ;;
  "" | -h | --help | help)
    cat <<EOF
usage: dot <command> [<args>]

Repository commands use the base repo plus Git-managed overlays:
  update           Pull repos, apply all overlays, merge configs, update deps
  pull             Same as update
  fetch            Fetch base + all active overlays
  push             Push base + all active overlays
  status           Show status of base + all active overlays
  diff             Show diff of base + all active overlays
  cron             Show installed cron entries
  doctor           Run health checks on the installation

Flags (update only):
  -v, --verbose   Show every dep and merge hook individually
  -f, --force     Bypass TTL caches and force reinstalls
  --cron          Quiet mode for cron: skip pull if worktree dirty, suppress output
  --quiet         Suppress normal output without cron dirty-worktree behavior

Overlays are configured in ~/.config/dot/overlays.d/*.conf.
'update' installs tracked cron entries from ~/.config/dot/merge-hooks.d/cron/cron.d
and machine-local cron.local entries into the user crontab.
EOF
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Commands below require the bare repo
# ---------------------------------------------------------------------------

if [[ ! -d "$DOTFILES" ]]; then
  cat >&2 <<EOF
error: bare repo not found at $DOTFILES

Clone it first:
  git clone --bare git@github.com:cgraf78/dotfiles.git $DOTFILES
  curl -fsSL https://raw.githubusercontent.com/cgraf78/dot/main/install.sh | bash -s -- --init git@github.com:cgraf78/dotfiles.git
EOF
  exit 1
fi

case "${1:-}" in
  fetch)
    shift
    _repo_fetch_all "$@"
    ;;
  push)
    shift
    _repo_push_all "$@"
    ;;
  diff)
    shift
    _repo_diff_all "$@"
    ;;
  status)
    shift
    _repo_status_all "$@"
    ;;
  *)
    printf 'dot: unknown command: %s\n' "$1" >&2
    if [[ "$1" == "git" ]]; then
      printf 'tip: use the PATH-visible "git" launcher for raw base-repo operations\n' >&2
    else
      printf 'tip: use "git %s" for raw base-repo operations\n' "$1" >&2
    fi
    exit 1
    ;;
esac
