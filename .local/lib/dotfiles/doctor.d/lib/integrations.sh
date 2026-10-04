# shellcheck shell=bash
# dot doctor: always-active shell integration checks.
#
# The termnav verdict probes the provider asset directly: resolve
# `cgraf78/termnav share/termnav/shell.sh` through the shdeps adapter
# and source only it in a minimal shell. A full interactive boot costs
# two shells and ~750ms, yet the verdict depends solely on whether the
# asset loads -- no other interactive file sets or clears the marker --
# so the narrow probe reports identical verdicts. The bash and zsh probes
# run in parallel, each with a private cache and under a deadline, so an
# asset that hangs cannot hold the doctor run.
# Known exotic-setup edge: the old probe inherited env.d-built PATH
# (~/bin, mise shims, homebrew...); the narrow probe sees ambient PATH
# plus the adapter fallbacks, so a shdeps reachable only via an
# env-added dir would flip ok to warn. Standard installs resolve via
# the ~/.local/bin fallback.

# Seconds each probe may take before it is reported as timed out.
_DR_TERMNAV_DEADLINE=10

# Probe the termnav asset in shell $1 with the private directory $2 as its
# cache; stdout and the exit status land in $2/out and $2/status. Runs as a
# background job of the worker, so a failing probe must not trip errexit
# before its status is recorded.
_dr_termnav_probe() {
  local shell_name=$1 base=$2 rc=0
  # shellcheck disable=SC2016 # The child shells expand their own variables.
  if [[ $shell_name == bash ]]; then
    XDG_CACHE_HOME="$base" _dr_run_bounded "$_DR_TERMNAV_DEADLINE" \
      bash --noprofile --norc -c '
        . "$HOME/.local/lib/dotfiles/shdeps-assets.sh"
        dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh
        printf "termnav=%s\n" "${TERMNAV_SHELL_LOADED:-0}"
      ' </dev/null >"$base/out" 2>/dev/null || rc=$?
  else
    XDG_CACHE_HOME="$base" _dr_run_bounded "$_DR_TERMNAV_DEADLINE" \
      zsh -f -c '
        . "$HOME/.local/lib/dotfiles/shdeps-assets.sh"
        dot_shdeps_dep_source cgraf78/termnav share/termnav/shell.sh
        print -r -- "termnav=${TERMNAV_SHELL_LOADED:-0}"
      ' </dev/null >"$base/out" 2>/dev/null || rc=$?
  fi
  printf '%s\n' "$rc" >"$base/status"
}

# Render one probe's verdict. A probe whose deadline could not be set up
# (125) did not run. Otherwise only the marker decides: a nonzero exit
# from a shell that printed it still loaded the asset.
_dr_termnav_report() {
  local shell_name=$1 base=$2 status=1 output=''
  IFS= read -r status 2>/dev/null <"$base/status" || status=1
  IFS= read -r -d '' output 2>/dev/null <"$base/out" || true
  case $status in
    124 | 137)
      _dr_hint_row warn "termnav $shell_name integration timed out" \
        "sourcing the termnav shell asset in $shell_name took over ${_DR_TERMNAV_DEADLINE}s, so interactive $shell_name startup stalls too" \
        "run 'dot update' to reinstall it"
      ;;
    125)
      # The builtin watchdog could not create its private FIFO.
      _dr_hint_row warn "termnav $shell_name integration unchecked" \
        "could not set up the probe's deadline" "$_DR_TMPDIR_HINT"
      ;;
    *)
      if [[ $output == *"termnav=1"* ]]; then
        _dr_ok "termnav $shell_name integration"
      else
        _dr_hint_row warn "termnav $shell_name integration unavailable" \
          "sourcing the termnav shell asset in $shell_name did not load it" "run 'dot update'"
      fi
      ;;
  esac
}

_dr_check_shell_integrations() {
  _dr_section "Shell integrations"

  local tmp shell_name base i
  local -a shells=(bash) bases=() pids=()
  command -v zsh >/dev/null 2>&1 && shells+=(zsh)
  # Resolve the deadline runner once, before the probes fork.
  _dr_timeout_resolve
  if ! tmp=$(mktemp -d "${TMPDIR:-/tmp}/dot-doctor-termnav.XXXXXX" 2>/dev/null); then
    for shell_name in "${shells[@]}"; do
      _dr_hint_row warn "termnav $shell_name integration unchecked" \
        "could not create a temporary directory" "$_DR_TMPDIR_HINT"
    done
  else
    for shell_name in "${shells[@]}"; do
      # mktemp rather than mkdir: the probes need nothing else on PATH.
      if base=$(mktemp -d "$tmp/$shell_name.XXXXXX" 2>/dev/null); then
        _dr_termnav_probe "$shell_name" "$base" &
        pids+=("$!")
      else
        base=
        pids+=('')
      fi
      bases+=("$base")
    done
    for i in "${!shells[@]}"; do
      if [[ -z ${bases[i]} ]]; then
        _dr_hint_row warn "termnav ${shells[i]} integration unchecked" \
          "could not create a temporary directory" "$_DR_TMPDIR_HINT"
        continue
      fi
      wait "${pids[i]}" || true
      _dr_termnav_report "${shells[i]}" "${bases[i]}"
    done
    rm -rf "$tmp"
  fi
  if ((${#shells[@]} == 1)); then
    _dr_skip "termnav zsh integration" "zsh not installed"
  fi
}
