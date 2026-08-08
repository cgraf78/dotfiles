# shellcheck shell=bash
# Shared environment for dot and dotbootstrap.
# Sources all dot modules in dependency order, then bootstraps shdeps.

_dir="${BASH_SOURCE[0]%/*}"
. "$_dir/xdg.sh"
. "$_dir/constants.sh"
. "$_dir/log.sh"
. "$_dir/progress-ui.sh"
. "$_dir/resources.sh"
. "$_dir/run.sh"
. "$_dir/temp.sh"
. "$_dir/platform.sh"
. "$_dir/overlays.sh"
. "$_dir/shdeps-ui.sh"
. "$_dir/shdeps-assets.sh"
. "$_dir/merge-block.sh"
. "$_dir/families.sh"
. "$_dir/merge-hooks.sh"
. "$_dir/repos/api.sh"
. "$_dir/merges.sh"
. "$_dir/update-lock.sh"
. "$_dir/update.sh"
. "$_dir/doctor.sh"

# ---------------------------------------------------------------------------
# shdeps bootstrap — find or install shdeps, configure for dotfiles
# ---------------------------------------------------------------------------

# Locate install.sh: env override → dev clone → installed tree → curl install.
# Sets REPLY to the path on success, returns 1 if not found. SHDEPS_LIB is
# exported only for explicit/dev paths where dotfiles really intends to pin a
# concrete library. Installed trees source their own bootstrap script; shdeps
# owns any source/release migration or self-update needed from there.

_shdeps_default_install_url() {
  printf '%s' "https://raw.githubusercontent.com/cgraf78/shdeps/main/install.sh"
}

_dot_load_github_pat_token() {
  local token_file="$HOME/.config/gh/github-pat" token=""
  if [[ -n "${GH_TOKEN:-}" ]]; then
    export GH_TOKEN
    export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
    export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
    return 0
  fi
  [[ -r "$token_file" ]] || return 0
  chmod 600 "$token_file" 2>/dev/null || true
  IFS= read -r token <"$token_file" || true
  [[ -n "$token" ]] || return 0
  export GH_TOKEN="$token"
  export GITHUB_PERSONAL_ACCESS_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
  export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-$GH_TOKEN}"
}

_find_shdeps_installer() {
  # REAL_HOME is set by test framework when HOME is mocked
  local real_home="${REAL_HOME:-$HOME}"
  local dev_dir="${SHDEPS_GIT_DEV_DIR:-$real_home/git}"
  # Tests and unusual bootstrap environments can intentionally point shdeps at
  # a release tree outside HOME. Respect that explicit install root here; the
  # normal user path still comes from HOME when SHDEPS_DIR is unset.
  local installed_dir="${SHDEPS_DIR:-$real_home/.local/share/shdeps}"

  if [[ -n "${SHDEPS_LIB:-}" && -f "${SHDEPS_LIB%/*}/install.sh" ]]; then
    REPLY="${SHDEPS_LIB%/*}/install.sh"
    return 0
  fi
  if [[ -f "$dev_dir/shdeps/shdeps.sh" && -f "$dev_dir/shdeps/install.sh" ]]; then
    export SHDEPS_LIB="$dev_dir/shdeps/shdeps.sh"
    REPLY="$dev_dir/shdeps/install.sh"
    return 0
  fi
  if [[ -f "$installed_dir/shdeps.sh" && -f "$installed_dir/install.sh" ]]; then
    REPLY="$installed_dir/install.sh"
    return 0
  fi

  # Not installed — install first
  _log "  shdeps not found, installing..."
  local _install_url
  _install_url="$(_shdeps_default_install_url)"
  if [[ "${DOT_QUIET:-0}" -eq 1 ]]; then
    (
      set -o pipefail
      curl -fsSL "$_install_url" | bash
    ) &>/dev/null || return 1
  else
    # A fresh install is the one bootstrap path with no local implementation
    # to fall back to. Preserve its diagnostics so network, platform, and
    # artifact failures are actionable instead of collapsing into the generic
    # warning emitted by `_bootstrap_shdeps`.
    (
      set -o pipefail
      curl -fsSL "$_install_url" | bash
    ) || return 1
  fi

  REPLY="$installed_dir/install.sh"
  return 0
}

_shdeps_install_needs_repair() {
  local dir="$1" version=""

  [[ -d "$dir" ]] || return 1
  if [[ -d "$dir/.git" ]]; then
    # Older shdeps installations were source checkouts whose installer did not
    # understand --bootstrap. Let the current installer validate and migrate
    # that recognizable tree using its own dirty-tree and origin safeguards.
    [[ -f "$dir/install.sh" && -f "$dir/shdeps.sh" ]] && return 0
    return 1
  fi
  grep -q '"method"[[:space:]]*:[[:space:]]*"release"' \
    "$dir/.shdeps-install.json" 2>/dev/null || return 1
  [[ -x "$dir/shdeps" ]] || return 0
  version=$("$dir/shdeps" __api version 2>/dev/null) || return 0
  [[ "$version" != "abi:1" ]]
}

_repair_shdeps_install() {
  local dir="$1" installer url

  installer=$(mktemp "${TMPDIR:-/tmp}/dot-shdeps-install.XXXXXX" 2>/dev/null) || return 1
  url="$(_shdeps_default_install_url)"
  if ! curl -fsSL "$url" -o "$installer"; then
    rm -f "$installer"
    return 1
  fi

  # The installed bootstrap may predate the platform it is now running on. In
  # particular, the pre-Android installer maps Termux to Linux musl and would
  # replace one incompatible archive with another. Run the current installer
  # as a separate process so its platform selection updates the managed bundle;
  # the caller sources that newly installed bundle afterward.
  if ! SHDEPS_FORCE=1 SHDEPS_DIR="$dir" bash "$installer"; then
    rm -f "$installer"
    return 1
  fi
  rm -f "$installer"
}

_dot_stdio_is_tty() {
  [[ -t 0 && -t 1 ]]
}

# shdeps gates its `gh auth token` fallback on stdin+stdout being terminals
# (shdeps PR #19: headless gh can autostart orphan D-Bus and keyring daemons on
# long-lived hosts). Dot's update UI pipes shdeps stdout into a fifo for JSONL
# progress, which hides the caller's real interactivity and silently downgrades
# interactive updates to unauthenticated GitHub API calls.
#
# Safety contract:
#   - an explicit caller setting always wins, including "0"
#   - quiet/cron runs never opt in, even if a scheduler attaches a pty
#   - this records dot's intent without exporting shdeps' knob process-wide;
#     shdeps-ui scopes the actual opt-in to the shdeps_update invocation
_dot_forward_gh_interactivity() {
  [[ -z "${SHDEPS_ALLOW_GH_AUTH_TOKEN+x}" ]] || return 0
  [[ "${DOT_QUIET:-0}" -eq 0 && "${SHDEPS_QUIET:-0}" != 1 ]] || return 0
  _dot_stdio_is_tty || return 0
  # shellcheck disable=SC2034  # consumed later by shdeps-ui.sh in the same shell.
  DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN=1
}

_bootstrap_shdeps() {
  # Map dotfiles env vars to shdeps config (must be set before --bootstrap
  # sources shdeps.sh, since it reads these at source time)
  _dot_load_github_pat_token
  SHDEPS_CONF_DIR="$(_dot_shdeps_conf_dir)"
  export SHDEPS_CONF_DIR
  export SHDEPS_HOOKS_DIR="$SHDEPS_CONF_DIR/hooks.d"
  # Enable EPEL on RHEL-family dnf distros (CentOS Stream, Rocky, Alma,
  # RHEL) — many dotfiles deps live only in EPEL there. Skip on Fedora:
  # its base repos already ship those tools, and epel-release is not
  # published for Fedora so the install would fail and abort `dot update`.
  # User can override with SHDEPS_AUTO_EPEL=1 or =0 in their environment.
  local _epel_default=1
  if [[ -r /etc/os-release ]] && grep -q '^ID=fedora' /etc/os-release 2>/dev/null; then
    _epel_default=0
  fi
  export SHDEPS_AUTO_EPEL="${SHDEPS_AUTO_EPEL:-$_epel_default}"
  [[ "${DOT_FORCE:-0}" -eq 1 ]] && export SHDEPS_FORCE=1
  [[ "${DOT_QUIET:-0}" -eq 1 ]] && export SHDEPS_QUIET=1
  _dot_forward_gh_interactivity

  if _find_shdeps_installer; then
    # A forced check must refresh the bootstrap resolver first so a cached
    # pre-fix installer cannot validate dependencies with obsolete logic. Keep
    # ordinary interactive and cron updates cache-local; `dot update -f` and
    # an explicit SHDEPS_FORCE=1 both opt into the network refresh.
    if [[ -z "${SHDEPS_LIB:-}" && "${SHDEPS_FORCE:-0}" == 1 ]]; then
      if [[ "${DOT_QUIET:-0}" -eq 1 ]]; then
        _repair_shdeps_install "${REPLY%/*}" >/dev/null 2>&1 || return 1
      else
        _repair_shdeps_install "${REPLY%/*}" || return 1
      fi
      REPLY="${REPLY%/*}/install.sh"
    fi

    # A managed release can survive a platform transition, and an older source
    # checkout can predate the sourceable installer's --bootstrap interface.
    # Repair either recognized installed-tree shape with the current installer
    # before sourcing any installed wrapper or installer.
    if [[ -z "${SHDEPS_LIB:-}" ]] && _shdeps_install_needs_repair "${REPLY%/*}"; then
      if [[ "${DOT_QUIET:-0}" -eq 1 ]]; then
        _repair_shdeps_install "${REPLY%/*}" >/dev/null 2>&1 || return 1
      else
        _repair_shdeps_install "${REPLY%/*}" || return 1
      fi
    fi

    # shellcheck source=/dev/null
    if [[ "${DOT_QUIET:-0}" -eq 1 ]]; then
      # Cron and quiet updates deliberately have an empty success contract.
      # shdeps usually honors SHDEPS_QUIET after it is bootstrapped, but the
      # sourceable installer can emit curl/git diagnostics before its own quiet
      # handling is active. Keep that bootstrap boundary quiet without changing
      # interactive update diagnostics.
      . "$REPLY" --bootstrap >/dev/null 2>&1 && return 0
    else
      . "$REPLY" --bootstrap && return 0
    fi
  fi

  _warn "  warning: failed to install shdeps — skipping dependency install"
  return 1
}

_dot_shdeps_preserves_release_launchers() {
  local binary="${_SHDEPSW_BIN:-}"
  [[ -n "$binary" && -x "$binary" ]] || return 1
  command "$binary" __api capability \
    release-archive-launcher-preservation-v1 >/dev/null 2>&1
}

_dot_shdeps_adopt_active_binary() {
  local binary="" version=""
  # A source-checkout update can leave the wrapper's original target/debug
  # path intact while activating a newly built sibling. Re-run the wrapper's
  # own resolver, then update its dispatch variable before probing. This makes
  # the capability check and the later shdeps_update call execute the exact
  # same path. Release installs normally resolve to the same stable pathname,
  # whose inode was atomically replaced by self-update.
  if declare -f _shdepsw_resolve_binary >/dev/null 2>&1; then
    binary=$(_shdepsw_resolve_binary 2>/dev/null) || binary=""
  fi
  [[ -n "$binary" ]] || binary="${_SHDEPSW_BIN:-}"
  [[ -n "$binary" && -x "$binary" ]] || return 1
  # Bootstrap validated the previously selected binary. A self-update may
  # activate a different path, so validate the sourceable wrapper contract
  # again before making old wrapper functions dispatch through it.
  version=$(command "$binary" __api version 2>/dev/null) || return 1
  [[ "$version" == abi:1 ]] || return 1
  _SHDEPSW_BIN="$binary"
}

_dot_shdeps_adopt_hive_archive_launcher() {
  local binary="${_SHDEPSW_BIN:-}" launcher="$HOME/.local/bin/hm"
  local launcher_marker=""
  local expected_marker="# Dotfiles-owned front door for the generic \`hm\` binary."

  # Only the tracked front door can supply the explicit intent Shdeps needs to
  # disambiguate a legacy bin-link ledger. The same on-disk shape can otherwise
  # be left by an interrupted archive-to-raw conversion, so neither repository
  # should infer ownership from the ledger alone. Fresh installs and customized
  # hm commands have nothing for this one-time migration to authorize.
  [[ -n "$binary" && -x "$binary" ]] || return 1
  [[ -f "$launcher" && ! -L "$launcher" && -x "$launcher" ]] || return 0
  {
    IFS= read -r _
    IFS= read -r launcher_marker
  } <"$launcher" || return 0
  [[ "$launcher_marker" == "$expected_marker" ]] || return 0

  if [[ "${DOT_QUIET:-0}" -eq 1 || "${SHDEPS_QUIET:-0}" == 1 ]]; then
    command "$binary" __api adopt-release-archive-launcher \
      cgraf78/hive-memory hm >/dev/null 2>&1
  else
    command "$binary" __api adopt-release-archive-launcher \
      cgraf78/hive-memory hm >/dev/null
  fi
}

_dot_shdeps_enable_release_launcher_preservation() {
  if ! _dot_shdeps_adopt_hive_archive_launcher; then
    if [[ "${DOT_QUIET:-0}" -ne 1 && "${SHDEPS_QUIET:-0}" != 1 ]]; then
      _warn "  warning: shdeps could not adopt the legacy Hive Memory archive — skipping dependency install"
    fi
    return 1
  fi
  export DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION=1
}

_dot_shdeps_require_release_launcher_preservation() {
  local self_update_status=0
  unset DOT_SHDEPS_RELEASE_LAUNCHER_PRESERVATION
  if _dot_shdeps_preserves_release_launchers; then
    _dot_shdeps_enable_release_launcher_preservation
    return
  fi

  # The old process can replace its binary during self-update, but it keeps
  # executing the old dependency installer afterward. That installer would
  # overwrite a tracked ~/.local/bin launcher in the same `dot update`. Run
  # self-update as a separate phase, then execute the capability probe through
  # the stable path again before allowing any dependency install to start.
  # This one-time gate protects every fleet machine independently; release
  # ordering or a successful update on this host cannot protect another host's
  # first convergence.
  if ! declare -f shdeps_self_update >/dev/null 2>&1; then
    if [[ "${DOT_QUIET:-0}" -ne 1 && "${SHDEPS_QUIET:-0}" != 1 ]]; then
      _warn "  warning: shdeps cannot verify tracked launcher preservation — skipping dependency install"
    fi
    return 1
  fi
  if [[ "${DOT_QUIET:-0}" -eq 1 || "${SHDEPS_QUIET:-0}" == 1 ]]; then
    shdeps_self_update >/dev/null 2>&1 || self_update_status=$?
  else
    shdeps_self_update || self_update_status=$?
  fi
  if [[ "$self_update_status" -ne 0 ]]; then
    if [[ "${DOT_QUIET:-0}" -ne 1 && "${SHDEPS_QUIET:-0}" != 1 ]]; then
      _warn "  warning: shdeps self-update failed before tracked launcher migration — skipping dependency install"
    fi
    return 1
  fi
  if ! _dot_shdeps_adopt_active_binary ||
    ! _dot_shdeps_preserves_release_launchers; then
    if [[ "${DOT_QUIET:-0}" -ne 1 && "${SHDEPS_QUIET:-0}" != 1 ]]; then
      _warn "  warning: updated shdeps cannot preserve tracked launchers — skipping dependency install"
    fi
    return 1
  fi
  _dot_shdeps_enable_release_launcher_preservation
}

# Defer shdeps bootstrap until needed — commands like status, diff, push,
# and fetch don't use shdeps and shouldn't pay the startup cost.
_ensure_shdeps() {
  declare -f shdeps_update &>/dev/null && return 0
  _bootstrap_shdeps
}
