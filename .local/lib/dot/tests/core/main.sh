# shellcheck shell=bash
# main.sh - main shard UI and helper coverage.

dot_core_test_main() {
  echo ""
  echo "=== Update UI helpers ==="

  # _ui_cell (fixed-width: truncates) vs _ui_pad (min-width: never truncates),
  # both via the shared _ui_fit. Length-based asserts avoid trailing-space nits.
  local _ui_r
  _ui_r=$(_ui_cell "abcdef" 3)
  _assert_eq "ui_cell: truncates over-width" "abc" "$_ui_r"
  _ui_r=$(_ui_cell "ab" 5)
  _assert_eq "ui_cell: pads under-width to width" "5" "${#_ui_r}"
  _ui_r=$(_ui_cell "abc" 3)
  _assert_eq "ui_cell: exact width unchanged" "abc" "$_ui_r"
  _ui_r=$(_ui_pad "abcdef" 3)
  _assert_eq "ui_pad: never truncates over-width" "abcdef" "$_ui_r"
  _ui_r=$(_ui_pad "ab" 5)
  _assert_eq "ui_pad: pads under-width to width" "5" "${#_ui_r}"

  echo "=== Gum capability detection ==="

  local _gum_probe_bin
  _gum_probe_bin=$(_mock_bin)
  cat >"$_gum_probe_bin/gum" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "broken gum" >&2
exit 80
MOCK
  chmod +x "$_gum_probe_bin/gum"
  if PATH="$_gum_probe_bin:$PATH" _dot_ui_has_gum; then
    _fail "ui gum probe: rejects an unusable executable"
  else
    _pass "ui gum probe: rejects an unusable executable"
  fi
  cat >"$_gum_probe_bin/gum" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == style && "$2" == --help ]]
MOCK
  chmod +x "$_gum_probe_bin/gum"
  if PATH="$_gum_probe_bin:$PATH" _dot_ui_has_gum; then
    _pass "ui gum probe: accepts a usable executable"
  else
    _fail "ui gum probe: accepts a usable executable"
  fi

  _saved_dot_verbose="${DOT_VERBOSE:-0}"
  _saved_dot_quiet="${DOT_QUIET:-0}"
  _saved_dot_ui_total="${DOT_UI_TOTAL:-0}"
  _saved_dot_ui_index="${DOT_UI_INDEX:-0}"

  _define_shdeps_update_fixture() {
    # shellcheck disable=SC2329  # _run_shdeps_update_ui invokes this fixture by name.
    shdeps_update() {
      printf '%s\n' \
        '{"event":"phase","group":"packages","phase":"packages","label":"Packages","status":"running","detail":"checking package deps","done":0,"total":2}' \
        '{"event":"item","group":"packages","status":"ok","name":"alpha","detail":"installed"}' \
        '{"event":"phase","group":"packages","phase":"packages","label":"Packages","status":"running","detail":"checking package deps","done":1,"total":2}' \
        '{"event":"phase","group":"github-releases","phase":"github-release-metadata","label":"GitHub","status":"running","detail":"fetching GitHub release metadata","done":0,"total":1}' \
        '{"event":"item","group":"github-releases","status":"changed","name":"beta","detail":"2.0.0"}' \
        '{"event":"item","group":"github-repos","status":"ok","name":"delta","detail":"local clone"}' \
        '{"event":"item","group":"cargo","status":"ok","name":"ripgrep","detail":"installed"}' \
        '{"event":"item","group":"custom","status":"ok","name":"epsilon","detail":"custom current"}' \
        '{"event":"phase","group":"packages","phase":"packages","label":"Packages","status":"running","detail":"checking package deps","done":2,"total":2}' \
        '{"event":"item","group":"packages","status":"ok","name":"gamma","detail":"installed"}' \
        '{"event":"group_summary","group":"packages","label":"Packages","status":"ok","changed":0,"current":2,"skipped":0,"failed":0,"elapsed_ms":6100}' \
        '{"event":"group_summary","group":"github-releases","label":"GitHub","status":"changed","changed":1,"current":0,"skipped":0,"failed":0,"elapsed_ms":2400}' \
        '{"event":"group_summary","group":"github-repos","label":"GitHub","status":"ok","changed":0,"current":1,"skipped":0,"failed":0,"elapsed_ms":1200}' \
        '{"event":"group_summary","group":"cargo","label":"Cargo","status":"ok","changed":0,"current":1,"skipped":0,"failed":0,"elapsed_ms":700}' \
        '{"event":"group_summary","group":"custom","label":"Custom","status":"ok","changed":0,"current":1,"skipped":0,"failed":0,"elapsed_ms":900}' \
        '{"event":"summary","status":"changed","changed":1,"current":5,"skipped":0,"failed":0}'
    }
  }
  _define_shdeps_update_fixture

  _saved_dot_update_jobs="${DOT_UPDATE_JOBS-__dot_unset__}"
  _saved_dot_merge_jobs="${DOT_MERGE_JOBS-__dot_unset__}"
  _saved_shdeps_jobs="${SHDEPS_JOBS-__dot_unset__}"

  export DOT_UPDATE_JOBS=3
  unset DOT_MERGE_JOBS
  _assert_eq "update jobs: merge hooks inherit DOT_UPDATE_JOBS" \
    "3" "$(_merge_parallel_jobs)"
  export DOT_MERGE_JOBS=2
  _assert_eq "update jobs: DOT_MERGE_JOBS overrides DOT_UPDATE_JOBS" \
    "2" "$(_merge_parallel_jobs)"

  export DOT_UPDATE_JOBS=5
  unset SHDEPS_JOBS
  _dot_update_prepare_shdeps_jobs
  _assert_eq "update jobs: shdeps inherits DOT_UPDATE_JOBS when unset" \
    "5" "$SHDEPS_JOBS"
  export SHDEPS_JOBS=9
  _dot_update_prepare_shdeps_jobs
  _assert_eq "update jobs: existing SHDEPS_JOBS wins" "9" "$SHDEPS_JOBS"

  if [[ "$_saved_dot_update_jobs" == "__dot_unset__" ]]; then
    unset DOT_UPDATE_JOBS
  else
    export DOT_UPDATE_JOBS="$_saved_dot_update_jobs"
  fi
  if [[ "$_saved_dot_merge_jobs" == "__dot_unset__" ]]; then
    unset DOT_MERGE_JOBS
  else
    export DOT_MERGE_JOBS="$_saved_dot_merge_jobs"
  fi
  if [[ "$_saved_shdeps_jobs" == "__dot_unset__" ]]; then
    unset SHDEPS_JOBS
  else
    export SHDEPS_JOBS="$_saved_shdeps_jobs"
  fi

  _run_forward_gh_case() {
    local initial="$1" dot_quiet="$2" shdeps_quiet="$3" tty_status="$4"
    unset DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN
    if [[ "$initial" == "__unset__" ]]; then
      unset SHDEPS_ALLOW_GH_AUTH_TOKEN
    else
      export SHDEPS_ALLOW_GH_AUTH_TOKEN="$initial"
    fi
    DOT_QUIET="$dot_quiet"
    export SHDEPS_QUIET="$shdeps_quiet"
    _dot_test_stdio_is_tty="$tty_status"
    _dot_forward_gh_interactivity
    printf '%s/%s' "${DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN:-unset}" "${SHDEPS_ALLOW_GH_AUTH_TOKEN:-unset}"
  }

  _saved_dot_stdio_is_tty="$(declare -f _dot_stdio_is_tty)"
  # shellcheck disable=SC2329  # _dot_forward_gh_interactivity invokes this test seam.
  _dot_stdio_is_tty() {
    return "$_dot_test_stdio_is_tty"
  }

  result=$(_run_forward_gh_case "__unset__" 0 0 0)
  _assert_eq "gh interactivity: interactive run records the opt-in" "1/unset" "$result"

  result=$(_run_forward_gh_case "__unset__" 0 0 1)
  _assert_eq "gh interactivity: headless run leaves the knob unset" "unset/unset" "$result"

  result=$(_run_forward_gh_case 0 0 0 0)
  _assert_eq "gh interactivity: explicit setting is never overridden" "unset/0" "$result"

  result=$(_run_forward_gh_case "__unset__" 1 0 0)
  _assert_eq "gh interactivity: quiet run stays keyring-safe even with a tty" "unset/unset" "$result"

  result=$(_run_forward_gh_case "__unset__" 0 1 0)
  _assert_eq "gh interactivity: prescan quiet stays keyring-safe" "unset/unset" "$result"
  eval "$_saved_dot_stdio_is_tty"
  unset _saved_dot_stdio_is_tty _dot_test_stdio_is_tty

  # shellcheck disable=SC2329  # _run_shdeps_update_command invokes this fixture by name.
  shdeps_update() {
    printf '%s/%s/%s' \
      "${SHDEPS_ALLOW_GH_AUTH_TOKEN:-unset}" \
      "${SHDEPS_NESTED:-unset}" \
      "${SHDEPS_PROGRESS:-unset}"
  }

  unset SHDEPS_ALLOW_GH_AUTH_TOKEN SHDEPS_NESTED SHDEPS_PROGRESS
  DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN=1
  result=$(_run_shdeps_update_command jsonl)
  _assert_eq "gh interactivity: update UI scopes implicit opt-in to shdeps" \
    "1/1/jsonl" "$result"
  _assert_eq "gh interactivity: scoped opt-in does not persist after shdeps" \
    "unset" "${SHDEPS_ALLOW_GH_AUTH_TOKEN:-unset}"

  export SHDEPS_ALLOW_GH_AUTH_TOKEN=0
  unset SHDEPS_NESTED SHDEPS_PROGRESS
  DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN=1
  result=$(_run_shdeps_update_command)
  _assert_eq "gh interactivity: explicit shdeps setting still wins at invocation" \
    "0/1/unset" "$result"
  unset SHDEPS_ALLOW_GH_AUTH_TOKEN DOT_SHDEPS_ALLOW_GH_AUTH_TOKEN
  _define_shdeps_update_fixture

  DOT_VERBOSE=0
  DOT_QUIET=0
  export DOT_UPDATE_SUBPHASE_THRESHOLD_MS=0
  _ui_begin 5
  _ui_stage_start "Tools" "checking configured dependencies" >/dev/null
  result=$(_run_shdeps_update_ui 2>&1)
  _assert_not_contains "shdeps UI: non-verbose defers package summary until stage finish" \
    "Packages: 2 current" "$result"
  _assert_not_contains "shdeps UI: non-verbose defers release summary until stage finish" \
    "GitHub: 1 current" "$result"
  _assert_not_contains "shdeps UI: non-verbose hides per-item rows" \
    "alpha: installed" "$result"

  _ui_begin 5
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _run_shdeps_update_ui
    _ui_stage_finish "${DOT_UI_SHDEPS_STATUS:-ok}" "${DOT_UI_SHDEPS_SUMMARY:-dependencies checked}"
    _shdeps_print_group_summaries
  )
  _tools_line=$(grep -n '^\[1/5\] Tools      changed  1 changed, 5 current' <<<"$result" | head -n1 | cut -d: -f1)
  _summary_line=$(grep -n '^  ok       Packages: 2 current' <<<"$result" | head -n1 | cut -d: -f1)
  if [[ -n "$_tools_line" && -n "$_summary_line" && "$_summary_line" -gt "$_tools_line" ]]; then
    _pass "shdeps UI: explicit threshold renders subphase summaries below final Tools row"
  else
    _fail "shdeps UI: explicit threshold renders subphase summaries below final Tools row"
  fi
  _assert_contains "shdeps UI: non-verbose renders changed item details" \
    "changed  beta                         2.0.0" "$result"

  unset DOT_UPDATE_SUBPHASE_THRESHOLD_MS
  _ui_begin 5
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _run_shdeps_update_ui
    _ui_stage_finish "${DOT_UI_SHDEPS_STATUS:-ok}" "${DOT_UI_SHDEPS_SUMMARY:-dependencies checked}"
    _shdeps_print_group_summaries
  )
  _assert_not_contains "shdeps UI: hides successful slow subphase summaries by default" \
    "Packages: 2 current" "$result"

  _shdeps_ui_reset
  _shdeps_record_group_summary github-repos "GitHub" changed 1 12 0 0 2200
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: shows changed subphase summaries by default" \
    "GitHub: 1 changed, 12 current" "$result"

  _shdeps_ui_reset
  _shdeps_record_group_summary cargo "Cargo" skipped 0 0 2 0 800
  result=$(_shdeps_print_group_summaries)
  _assert_not_contains "shdeps UI: hides skipped subphase summaries by default" \
    "Cargo: 0 current, 2 skipped" "$result"

  _shdeps_ui_reset
  _shdeps_record_group_summary custom "Custom" failed 0 0 0 1 1200
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: still surfaces failed subphase summaries" \
    "failed   Custom: 1 failed, 1.2s" "$result"

  _shdeps_ui_reset
  _shdeps_record_group_summary github-releases "GitHub" failed 0 15 0 1 2000
  _shdeps_record_item github-releases failed cgraf78/grafhome-ca "GitHub API rate limit exceeded; retry after the window resets or set GH_TOKEN"
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: failed subphases list the failing items" \
    "failed   cgraf78/grafhome-ca" "$result"
  _assert_contains "shdeps UI: failed items carry their detail" \
    "GitHub API rate limit exceeded" "$result"

  _shdeps_ui_reset
  _handle_shdeps_event '{"event":"item","group":"github-repos","status":"warning","name":"cgraf78/cmdblocks","detail":"pull failed (no fast-forward; local clone)"}'
  _handle_shdeps_event '{"event":"group_summary","group":"github-repos","label":"GitHub","status":"warning","changed":0,"warnings":1,"current":4,"skipped":0,"failed":0,"elapsed_ms":900}'
  _handle_shdeps_event '{"event":"summary","status":"warning","changed":0,"warnings":1,"current":4,"skipped":0,"failed":0}'
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: warning summaries retain the warning count" \
    "GitHub: 1 warning, 4 current" "$result"
  _assert_contains "shdeps UI: warning summaries name the affected dependency" \
    "warning  cgraf78/cmdblocks" "$result"
  _assert_contains "shdeps UI: warning items retain their actionable detail" \
    "pull failed (no fast-forward; local clone)" "$result"
  _assert_eq "shdeps UI: aggregate warning summary retains the warning count" \
    "1 warning, 4 current" "$DOT_UI_SHDEPS_SUMMARY"

  DOT_UPDATE_SUBPHASE_THRESHOLD_MS=1000
  _shdeps_ui_reset
  _shdeps_record_group_summary github-releases "GitHub" failed 0 15 0 1 2000
  _shdeps_record_item github-releases failed cgraf78/grafhome-ca "release metadata fetch failed"
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: threshold branch also lists failed items" \
    "failed   cgraf78/grafhome-ca" "$result"
  unset DOT_UPDATE_SUBPHASE_THRESHOLD_MS

  _shdeps_ui_reset
  _shdeps_record_group_summary github-repos "GitHub" changed 1 12 0 0 500
  _shdeps_record_item github-repos changed cgraf78/checkrun "updated"
  _shdeps_record_item github-repos ok cgraf78/ds "commit 797ea5a"
  result=$(_shdeps_print_group_summaries)
  _assert_not_contains "shdeps UI: current items still hidden in non-verbose" \
    "cgraf78/ds" "$result"

  _shdeps_ui_reset
  _shdeps_record_group_summary experimental-tools "" failed 0 0 0 1 1200
  result=$(_shdeps_print_group_summaries)
  _assert_contains "shdeps UI: unknown group fallback preserves group key" \
    "failed   experimental-tools: 1 failed, 1.2s" "$result"

  DOT_VERBOSE=1
  _ui_begin 5
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _run_shdeps_update_ui
  )
  _tools_start_line=$(grep -n '^\[1/5\] Tools      running  checking configured dependencies' <<<"$result" | head -n1 | cut -d: -f1)
  _packages_line=$(grep -n '^  Packages$' <<<"$result" | head -n1 | cut -d: -f1)
  if [[ -n "$_tools_start_line" && -n "$_packages_line" && "$_packages_line" -gt "$_tools_start_line" ]]; then
    _pass "shdeps UI verbose: stage header appears before grouped details"
  else
    _fail "shdeps UI verbose: stage header appears before grouped details"
  fi
  _packages_heading_count=$(grep -c '^  Packages$' <<<"$result" || true)
  _assert_eq "shdeps UI verbose: package section heading appears once" \
    "1" "$_packages_heading_count"
  _assert_not_contains "shdeps UI verbose: group headings are not status rows" \
    "detail   Packages" "$result"
  _assert_contains "shdeps UI verbose: package items are grouped with detail columns" \
    "alpha                        installed" "$result"
  _assert_contains "shdeps UI verbose: release items are grouped with detail columns" \
    "beta                         2.0.0" "$result"
  _assert_not_contains "shdeps UI verbose: hides raw phase spam" \
    "checking package deps 1/2" "$result"
  _github_heading_count=$(grep -c '^  GitHub$' <<<"$result" || true)
  _assert_eq "shdeps UI verbose: github groups share one label heading" \
    "1" "$_github_heading_count"
  _assert_contains "shdeps UI verbose: repo items are grouped under GitHub" \
    "delta                        local clone" "$result"
  _assert_not_contains "shdeps UI verbose: hides github-repos implementation heading" \
    "  GitHub repos" "$result"
  _assert_contains "shdeps UI verbose: cargo items use Cargo heading" \
    "  Cargo" "$result"
  _assert_contains "shdeps UI verbose: cargo items are grouped before Custom" \
    "ripgrep                      installed" "$result"
  _cargo_heading_line=$(grep -n '^  Cargo$' <<<"$result" | head -n1 | cut -d: -f1)
  _custom_heading_line=$(grep -n '^  Custom$' <<<"$result" | head -n1 | cut -d: -f1)
  if [[ -n "$_cargo_heading_line" && -n "$_custom_heading_line" && "$_cargo_heading_line" -lt "$_custom_heading_line" ]]; then
    _pass "shdeps UI verbose: language method groups precede custom"
  else
    _fail "shdeps UI verbose: language method groups precede custom"
  fi
  _assert_contains "shdeps UI verbose: custom items use Custom heading" \
    "  Custom" "$result"
  _assert_not_contains "shdeps UI verbose: hides old hooks heading" \
    "  Hooks" "$result"

  DOT_VERBOSE=0
  export DOT_UI_FORCE_LIVE=1
  export DOT_UI_ASCII=1
  _ui_begin 1
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _handle_shdeps_event '{"event":"phase","group":"github-methods","phase":"github-methods","label":"Resolve sources","status":"running","detail":"resolving GitHub methods","done":1,"total":2}'
  )
  _assert_contains "shdeps UI phase: uses JSONL label for progress text" \
    "Resolve sources" "$result"
  _assert_not_contains "shdeps UI phase: ignores raw detail for progress text" \
    "resolving GitHub methods" "$result"
  _assert_not_contains "shdeps UI phase: does not remap detail to legacy label" \
    "GitHub methods" "$result"

  if command -v jq >/dev/null 2>&1; then
    _shdeps_jq_log="$(_tmpdir)/jq.log"
    _shdeps_jq_sed_log="$(_tmpdir)/jq-sed.log"
    _shdeps_real_jq=$(type -P jq)
    _shdeps_real_sed=$(type -P sed)
    : >"$_shdeps_jq_sed_log"
    # shellcheck disable=SC2329  # _handle_shdeps_event invokes this test seam.
    jq() {
      printf 'jq\n' >>"$_shdeps_jq_log"
      "$_shdeps_real_jq" "$@"
    }
    # shellcheck disable=SC2329  # legacy JSON fallback invokes this test seam.
    sed() {
      printf 'sed\n' >>"$_shdeps_jq_sed_log"
      "$_shdeps_real_sed" "$@"
    }
    _shdeps_ui_reset
    _handle_shdeps_event \
      '{"event":"item","group":"custom","status":"ok","name":"one","detail":"current"}'
    unset -f jq sed
    _assert_eq "shdeps UI event parsing: decodes each event once" \
      "1" "$(wc -l <"$_shdeps_jq_log" | tr -d ' ')"
    _assert_eq "shdeps UI event parsing: successful decode skips legacy parsing" \
      "0" "$(wc -l <"$_shdeps_jq_sed_log" | tr -d ' ')"
  fi

  _shdeps_sed_log="$(_tmpdir)/sed.log"
  _shdeps_real_sed=$(type -P sed)
  : >"$_shdeps_sed_log"
  # shellcheck disable=SC2329  # JSON fallback invokes these test seams.
  command() {
    if [[ "$1" == -v && "${2:-}" == jq ]]; then
      return 1
    fi
    builtin command "$@"
  }
  # shellcheck disable=SC2329  # _json_get invokes this test seam.
  sed() {
    printf 'sed\n' >>"$_shdeps_sed_log"
    "$_shdeps_real_sed" "$@"
  }
  _shdeps_ui_reset
  _handle_shdeps_event \
    '{"event":"item","group":"custom","status":"ok","name":"one","detail":"current"}'
  unset -f command sed
  _assert_eq "shdeps UI fallback parsing: item reads only fields it uses" \
    "5" "$(wc -l <"$_shdeps_sed_log" | tr -d ' ')"

  result=$(
    printf '[sudo] password for chris:'
    _handle_shdeps_event '{"event":"prompt","status":"running","detail":"waiting for sudo authentication"}'
  )
  _assert_not_contains "shdeps UI prompt: does not clear possible sudo prompt" \
    $'[sudo] password for chris:\r\033[K' "$result"

  _shdeps_finish_dir=$(_tmpdir)
  _shdeps_finish_status="$_shdeps_finish_dir/status"
  printf '0' >"$_shdeps_finish_status"
  # shellcheck disable=SC2329  # _shdeps_update_finished invokes this test seam.
  kill() { return 0; }
  # shellcheck disable=SC2329  # _shdeps_update_finished invokes this test seam.
  ps() { printf 'S\n'; }
  _shdeps_finish_rc=0
  _shdeps_update_finished 12345 "$_shdeps_finish_status" ||
    _shdeps_finish_rc=$?
  _assert_eq "shdeps UI completion: status wins while child still appears alive" \
    "0" "$_shdeps_finish_rc"

  : >"$_shdeps_finish_status"
  # A completed child can remain visible to kill(2) until its parent reaps it.
  # shellcheck disable=SC2329  # _shdeps_update_finished invokes this test seam.
  ps() { printf 'Z\n'; }
  _shdeps_finish_rc=0
  DOT_PROC_ROOT="$_shdeps_finish_dir/missing-proc" \
    _shdeps_update_finished 12345 "$_shdeps_finish_status" || _shdeps_finish_rc=$?
  unset -f kill ps
  _assert_eq "shdeps UI completion: zombie child is finished" "0" "$_shdeps_finish_rc"

  _shdeps_proc_root="$(_tmpdir)/proc"
  mkdir -p "$_shdeps_proc_root/42"
  printf '%s\n' '42 (worker) name) Z 0 0 0' >"$_shdeps_proc_root/42/stat"
  _assert_eq "shdeps UI completion: procfs parser handles a closing parenthesis in comm" \
    "Z" "$(DOT_PROC_ROOT="$_shdeps_proc_root" _shdeps_proc_state 42)"

  mkdir -p "$_shdeps_proc_root/43"
  printf '%s\n' '43 malformed stat record' >"$_shdeps_proc_root/43/stat"
  _shdeps_malformed_ps_log="$(_tmpdir)/malformed-ps.log"
  : >"$_shdeps_malformed_ps_log"
  # shellcheck disable=SC2329  # _shdeps_update_finished invokes these test seams.
  kill() { return 0; }
  # shellcheck disable=SC2329  # _shdeps_update_finished invokes these test seams.
  ps() {
    printf 'ps\n' >>"$_shdeps_malformed_ps_log"
    printf 'Z\n'
  }
  _shdeps_finish_rc=0
  DOT_PROC_ROOT="$_shdeps_proc_root" \
    _shdeps_update_finished 43 "$_shdeps_finish_status" || _shdeps_finish_rc=$?
  unset -f kill ps
  _assert_eq "shdeps UI completion: malformed procfs falls back to ps" \
    "0" "$_shdeps_finish_rc"
  _assert_eq "shdeps UI completion: malformed procfs invokes ps once" \
    "1" "$(wc -l <"$_shdeps_malformed_ps_log" | tr -d ' ')"

  if [[ -r "/proc/$$/stat" ]]; then
    _shdeps_ps_log="$(_tmpdir)/ps.log"
    _shdeps_live_status="$(_tmpdir)/status"
    : >"$_shdeps_ps_log"
    : >"$_shdeps_live_status"
    sleep 10 &
    _shdeps_live_pid=$!
    # shellcheck disable=SC2329  # _shdeps_update_finished invokes this test seam.
    ps() {
      printf 'ps\n' >>"$_shdeps_ps_log"
      return 1
    }
    _shdeps_finish_rc=0
    _shdeps_update_finished "$_shdeps_live_pid" "$_shdeps_live_status" ||
      _shdeps_finish_rc=$?
    unset -f ps
    kill "$_shdeps_live_pid" 2>/dev/null || true
    wait "$_shdeps_live_pid" 2>/dev/null || true
    _assert_eq "shdeps UI completion: live procfs child is unfinished" \
      "1" "$_shdeps_finish_rc"
    _assert_eq "shdeps UI completion: readable procfs avoids ps" \
      "0" "$(wc -l <"$_shdeps_ps_log" | tr -d ' ')"
  fi

  # shellcheck disable=SC2329  # _run_shdeps_update_ui invokes this fixture by name.
  shdeps_update() {
    printf '%s\n' '{"event":"prompt","status":"running","detail":"waiting for sudo authentication"}'
    sleep 0.05
    printf '%s\n' '{"event":"summary","status":"ok","changed":0,"current":0,"skipped":0,"failed":0}'
  }
  export DOT_UI_TICK_SECONDS=0.01
  _shdeps_ui_reset
  _ui_begin 1
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _run_shdeps_update_ui
  )
  _assert_not_contains "shdeps UI prompt: pauses live redraw while child waits" \
    "waiting for sudo authentication" "$result"

  _ui_begin 1
  result=$(
    _ui_stage_start "Tools" "checking configured dependencies"
    _ui_stage_update "fetching metadata"
    _ui_stage_finish ok "3 current"
  )
  _assert_contains "stage UI live: rewrites the active line" $'\r\033[K' "$result"
  _assert_contains "stage UI live: shows activity glyph" "/" "$result"

  progress_a=$(_ui_progress_detail_with_label "GitHub" 4 13)
  progress_b=$(_ui_progress_detail_with_label "Custom" 10 13)
  _progress_a_prefix="${progress_a%%\[*}"
  _progress_b_prefix="${progress_b%%\[*}"
  _assert_eq "progress detail: bar anchor is stable across phases" \
    "${#_progress_a_prefix}" "${#_progress_b_prefix}"
  _assert_contains "progress detail: count is right-aligned" \
    "[##------]  4/13" "$progress_a"
  _assert_contains "progress detail: two-digit count keeps same width" \
    "[######--] 10/13" "$progress_b"
  app_progress_a=$(_merge_progress_detail 4 22 "codex")
  app_progress_b=$(_merge_progress_detail 14 22 "agent rules")
  _tool_progress=$(_ui_progress_detail_with_label "GitHub" 4 22)
  _app_progress_a_prefix="${app_progress_a%%\[*}"
  _app_progress_b_prefix="${app_progress_b%%\[*}"
  _tool_progress_prefix="${_tool_progress%%\[*}"
  _assert_eq "progress detail: app bar anchor is stable" \
    "${#_app_progress_a_prefix}" "${#_app_progress_b_prefix}"
  _assert_eq "progress detail: app bar anchor matches tool phases" \
    "${#_tool_progress_prefix}" "${#_app_progress_a_prefix}"
  _assert_contains "progress detail: app label leads the bar" \
    "codex              [#-------]  4/22" "$app_progress_a"
  _assert_not_contains "progress detail: app label does not trail the counter" \
    "4/22 codex" "$app_progress_a"
  ctype_progress=$(LC_ALL='' LC_CTYPE=C LANG=en_US.UTF-8 DOT_UI_ASCII='' _ui_progress_bar 1 2)
  _assert_contains "progress detail: C character locale falls back to ASCII" \
    "[####----] 1/2" "$ctype_progress"
  unset DOT_UI_ASCII

  _ui_begin 1
  result=$(
    _ui_stage_start "Repos" "pulling repositories"
    _ui_status running "dotfiles: pulling"
  )
  _assert_contains "status rows: clear active live row before printing" \
    $'0s\r\033[K  running  dotfiles: pulling' "$result"

  result=$(_ui_item ok "editorconfig-checker/editorconfig-checker" "fresh")
  _assert_contains "item UI: keeps long names intact" \
    "editorconfig-checker/editorconfig-checker" "$result"

  DOT_VERBOSE=1
  export DOT_UI_FORCE_LIVE=1
  _ui_begin 1
  result=$(
    _ui_stage_start "Repos" "pulling repositories"
    _ui_status running "dotfiles: pulling"
  )
  _repos_start_line=$(grep -n '^\[1/1\] Repos      running  pulling repositories' <<<"$result" | head -n1 | cut -d: -f1)
  _repos_detail_line=$(grep -n 'dotfiles: pulling' <<<"$result" | head -n1 | cut -d: -f1)
  if [[ -n "$_repos_start_line" && -n "$_repos_detail_line" && "$_repos_detail_line" -gt "$_repos_start_line" ]]; then
    _pass "stage UI verbose live: keeps persistent stage header above details"
  else
    _fail "stage UI verbose live: keeps persistent stage header above details"
  fi
  DOT_VERBOSE=0

  # shellcheck disable=SC2329  # _run_quiet_logged invokes this fixture by name.
  quiet_tick_command() {
    sleep 0.05
  }

  export DOT_UI_TICK_SECONDS=0.01
  _ui_begin 1
  result=$(
    _ui_stage_start "Configs" "running config hooks"
    _run_quiet_logged merge "merge failed" quiet_tick_command
    _ui_stage_finish ok "1 config merged"
  )
  _assert_contains "quiet logged command: ticks while child is silent" \
    $'\r\033[K' "$result"
  unset -f quiet_tick_command

  # shellcheck disable=SC2016 # expanded inside the child shell under test.
  _done_hint_script=$(
    printf '%s' \
      '. "$HOME/.local/lib/dot/core/constants.sh"; ' \
      '. "$HOME/.local/lib/dot/core/log.sh"; ' \
      '. "$HOME/.local/lib/dot/core/progress-ui.sh"; ' \
      '_ui_begin 1; _ui_done'
  )
  result=$(SHELL=/bin/zsh bash -c "$_done_hint_script")
  _assert_contains "done UI: bash parent gets bash reload hint over SHELL" \
    "Reload your shell: source ~/.bashrc" "$result"
  if command -v zsh >/dev/null 2>&1; then
    # Keep zsh from tail-execing the child bash so the parent-shell probe sees
    # the same process shape as interactive `zsh` running `dot update`.
    result=$(SHELL=/bin/bash DOT_TEST_DONE_SCRIPT="$_done_hint_script" zsh -fc 'SHELL=/bin/bash bash -c "$DOT_TEST_DONE_SCRIPT"; true')
    _assert_contains "done UI: zsh parent gets zsh reload hint over SHELL" \
      "Reload your shell: source ~/.zshrc" "$result"
  else
    echo "  SKIP: zsh parent reload hint"
  fi
  export DOT_UPDATE_RELOADS_SHELL=1
  SHELL=/bin/zsh result=$(
    _ui_begin 1
    _ui_done
  )
  _assert_not_contains "done UI: dotu suppresses redundant reload hint" \
    "Reload your shell" "$result"
  result=$(
    _ui_begin 1
    _ui_done 0
  )
  _assert_contains "done UI: successful update keeps success message" \
    "Done in" "$result"
  result=$(
    _ui_begin 1
    _ui_done 1
  )
  _assert_contains "done UI: failed update reports completed errors" \
    "Done with errors in" "$result"

  unset -f shdeps_update _define_shdeps_update_fixture
  unset DOT_UPDATE_RELOADS_SHELL DOT_UPDATE_SUBPHASE_THRESHOLD_MS DOT_UI_FORCE_LIVE DOT_UI_TICK_SECONDS
  DOT_VERBOSE="$_saved_dot_verbose"
  DOT_QUIET="$_saved_dot_quiet"
  DOT_UI_TOTAL="$_saved_dot_ui_total"
  DOT_UI_INDEX="$_saved_dot_ui_index"
  # shellcheck disable=SC2034  # reset shared UI state for later sourced-helper tests.
  DOT_UI_LIVE_ACTIVE=0

  _shdeps_fb_home=$(_tmpdir)
  _shdeps_fb_bin="$_shdeps_fb_home/bin"
  _shdeps_fb_log="$_shdeps_fb_home/git.log"
  mkdir -p "$_shdeps_fb_bin"
  cat >"$_shdeps_fb_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'curl: bootstrap probe failed' >&2
exit 22
SH
  cat >"$_shdeps_fb_bin/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SHDEPS_FALLBACK_LOG"
exit 1
SH
  chmod +x "$_shdeps_fb_bin/curl" "$_shdeps_fb_bin/git"
  _shdeps_fb_result=$(
    unset SHDEPS_LIB SHDEPS_REPO
    HOME="$_shdeps_fb_home" \
      REAL_HOME="$_shdeps_fb_home" \
      SHDEPS_DIR="$_shdeps_fb_home/.local/share/shdeps" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_fb_home/git" \
      SHDEPS_FALLBACK_LOG="$_shdeps_fb_log" \
      PATH="$_shdeps_fb_bin:/usr/bin:/bin" \
      _find_shdeps_installer 2>&1 >/dev/null
    printf 'rc=%s\n' "$?"
    printf 'reply=%s\n' "${REPLY:-}"
    printf 'lib=%s\n' "${SHDEPS_LIB:-}"
  )
  _assert_eq "shdeps bootstrap: failed fresh install does not clone fallback" \
    "" "$(cat "$_shdeps_fb_log" 2>/dev/null || true)"
  _assert_contains "shdeps bootstrap: failed fresh install reports not found" \
    "rc=1" "$_shdeps_fb_result"
  _assert_contains "shdeps bootstrap: failed fresh install preserves diagnostics" \
    "curl: bootstrap probe failed" "$_shdeps_fb_result"
  _assert_contains "shdeps bootstrap: failed fresh install leaves SHDEPS_LIB unset" \
    "lib=" "$_shdeps_fb_result"

  _shdeps_dev_home=$(_tmpdir)
  _shdeps_dev_dir="$_shdeps_dev_home/git/shdeps"
  mkdir -p "$_shdeps_dev_dir"
  printf '%s\n' '# dev installer fixture' >"$_shdeps_dev_dir/install.sh"
  printf '%s\n' '# dev shdeps fixture' >"$_shdeps_dev_dir/shdeps.sh"
  _shdeps_dev_result=$(
    unset SHDEPS_LIB SHDEPS_DIR
    HOME="$_shdeps_dev_home" \
      REAL_HOME="$_shdeps_dev_home" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_dev_home/git" \
      _find_shdeps_installer >/dev/null
    printf 'reply=%s\n' "$REPLY"
    printf 'lib=%s\n' "${SHDEPS_LIB:-}"
  )
  _assert_contains "shdeps bootstrap: dev checkout supplies installer" \
    "reply=$_shdeps_dev_dir/install.sh" "$_shdeps_dev_result"
  _assert_contains "shdeps bootstrap: dev checkout pins SHDEPS_LIB" \
    "lib=$_shdeps_dev_dir/shdeps.sh" "$_shdeps_dev_result"

  _shdeps_explicit_home=$(_tmpdir)
  _shdeps_explicit_dir=$(_tmpdir)
  mkdir -p "$_shdeps_explicit_dir"
  printf '%s\n' '# explicit installer fixture' >"$_shdeps_explicit_dir/install.sh"
  printf '%s\n' '# explicit shdeps fixture' >"$_shdeps_explicit_dir/shdeps.sh"
  _shdeps_explicit_result=$(
    unset SHDEPS_LIB
    HOME="$_shdeps_explicit_home" \
      REAL_HOME="$_shdeps_explicit_home" \
      SHDEPS_DIR="$_shdeps_explicit_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_explicit_home/git" \
      _find_shdeps_installer >/dev/null
    printf 'reply=%s\n' "$REPLY"
    printf 'lib=%s\n' "${SHDEPS_LIB:-}"
  )
  _assert_contains "shdeps bootstrap: explicit SHDEPS_DIR supplies installer" \
    "reply=$_shdeps_explicit_dir/install.sh" "$_shdeps_explicit_result"
  _assert_contains "shdeps bootstrap: explicit SHDEPS_DIR does not pin SHDEPS_LIB" \
    "lib=" "$_shdeps_explicit_result"

  _shdeps_installed_home=$(_tmpdir)
  _shdeps_installed_dir="$_shdeps_installed_home/.local/share/shdeps"
  mkdir -p "$_shdeps_installed_dir"
  printf '%s\n' '# installed installer fixture' >"$_shdeps_installed_dir/install.sh"
  printf '%s\n' '# installed shdeps fixture' >"$_shdeps_installed_dir/shdeps.sh"
  _shdeps_installed_result=$(
    unset SHDEPS_LIB SHDEPS_REPO SHDEPS_DIR
    HOME="$_shdeps_installed_home" \
      REAL_HOME="$_shdeps_installed_home" \
      SHDEPS_LIB='' \
      SHDEPS_DIR='' \
      SHDEPS_GIT_DEV_DIR="$_shdeps_installed_home/git" \
      _find_shdeps_installer >/dev/null
    printf 'reply=%s\n' "$REPLY"
    printf 'lib=%s\n' "${SHDEPS_LIB:-}"
  )
  _assert_contains "shdeps bootstrap: installed tree supplies its own installer" \
    "reply=$_shdeps_installed_dir/install.sh" "$_shdeps_installed_result"
  _assert_contains "shdeps bootstrap: installed tree does not pin SHDEPS_LIB" \
    "lib=" "$_shdeps_installed_result"

  _shdeps_token_home=$(_tmpdir)
  _shdeps_token_dir="$_shdeps_token_home/.local/share/shdeps"
  _shdeps_token_log="$_shdeps_token_home/token.log"
  mkdir -p "$_shdeps_token_home/.config/gh" "$_shdeps_token_dir"
  printf '%s\n' 'bootstrap-token' >"$_shdeps_token_home/.config/gh/github-pat"
  chmod 600 "$_shdeps_token_home/.config/gh/github-pat"
  printf '%s\n' '# installed shdeps fixture' >"$_shdeps_token_dir/shdeps.sh"
  cat >"$_shdeps_token_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap)
    printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-}" >"$SHDEPS_TOKEN_LOG"
    shdeps_update() { :; }
    ;;
esac
SH
  _shdeps_token_result=$(
    unset GH_TOKEN GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN CODEX_GITHUB_PERSONAL_ACCESS_TOKEN SHDEPS_LIB
    HOME="$_shdeps_token_home" \
      REAL_HOME="$_shdeps_token_home" \
      SHDEPS_DIR="$_shdeps_token_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_token_home/git" \
      SHDEPS_TOKEN_LOG="$_shdeps_token_log" \
      _bootstrap_shdeps >/dev/null
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: loads github-pat into GH_TOKEN without shell env" \
    "rc=0" "$_shdeps_token_result"
  _assert_file_content "shdeps bootstrap: GH_TOKEN comes from github-pat" \
    "GH_TOKEN=bootstrap-token" "$_shdeps_token_log"
  _shdeps_token_result=$(
    unset GITHUB_TOKEN GITHUB_PERSONAL_ACCESS_TOKEN CODEX_GITHUB_PERSONAL_ACCESS_TOKEN SHDEPS_LIB
    export GH_TOKEN=explicit-token
    HOME="$_shdeps_token_home" \
      REAL_HOME="$_shdeps_token_home" \
      SHDEPS_DIR="$_shdeps_token_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_token_home/git" \
      SHDEPS_TOKEN_LOG="$_shdeps_token_log" \
      _bootstrap_shdeps >/dev/null
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: keeps explicit GH_TOKEN" \
    "rc=0" "$_shdeps_token_result"
  _assert_file_content "shdeps bootstrap: explicit GH_TOKEN beats github-pat" \
    "GH_TOKEN=explicit-token" "$_shdeps_token_log"

  _shdeps_repair_home=$(_tmpdir)
  _shdeps_repair_dir="$_shdeps_repair_home/.local/share/shdeps"
  _shdeps_repair_bin="$_shdeps_repair_home/fake-bin"
  _shdeps_repair_remote="$_shdeps_repair_home/current-install.sh"
  _shdeps_repair_marker="$_shdeps_repair_home/remote-installer-ran"
  mkdir -p "$_shdeps_repair_dir" "$_shdeps_repair_bin"
  cat >"$_shdeps_repair_dir/.shdeps-install.json" <<'JSON'
{"schema":1,"method":"release","artifact_platform":"linux-aarch64-musl"}
JSON
  cat >"$_shdeps_repair_dir/shdeps" <<'SH'
#!/usr/bin/env bash
exit 126
SH
  chmod +x "$_shdeps_repair_dir/shdeps"
  printf '%s\n' '# installed shdeps fixture' >"$_shdeps_repair_dir/shdeps.sh"
  cat >"$_shdeps_repair_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap)
    printf '%s\n' 'stale installer must not be sourced' >&2
    return 1
    ;;
esac
SH
  cat >"$_shdeps_repair_remote" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' 'ran' >"$SHDEPS_REPAIR_MARKER"
cat >"$SHDEPS_DIR/shdeps" <<'BIN'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
  __api:version) printf '%s\n' 'abi:1' ;;
esac
BIN
chmod +x "$SHDEPS_DIR/shdeps"
cat >"$SHDEPS_DIR/install.sh" <<'INSTALL'
case "${1:-}" in
  --bootstrap) shdeps_update() { :; } ;;
esac
INSTALL
SH
  cat >"$_shdeps_repair_bin/curl" <<'SH'
#!/usr/bin/env bash
set -u
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$SHDEPS_REPAIR_REMOTE" "$out"
SH
  chmod +x "$_shdeps_repair_bin/curl"
  _shdeps_repair_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_repair_home" \
      REAL_HOME="$_shdeps_repair_home" \
      SHDEPS_DIR="$_shdeps_repair_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_repair_home/git" \
      SHDEPS_REPAIR_REMOTE="$_shdeps_repair_remote" \
      SHDEPS_REPAIR_MARKER="$_shdeps_repair_marker" \
      PATH="$_shdeps_repair_bin:$PATH" \
      _bootstrap_shdeps >/dev/null
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: incompatible managed release recovers" \
    "rc=0" "$_shdeps_repair_result"
  _assert_eq "shdeps bootstrap: incompatible managed release uses current installer" \
    "ran" "$(cat "$_shdeps_repair_marker")"
  _assert_eq "shdeps bootstrap: repaired binary exposes wrapper ABI" \
    "abi:1" "$("$_shdeps_repair_dir/shdeps" __api version)"

  # A forced update must replace the cached resolver before dependency update
  # loads it. Otherwise a release that fixed resolver behavior cannot repair
  # the very dependency that exposed the old behavior.
  _shdeps_refresh_home=$(_tmpdir)
  _shdeps_refresh_dir="$_shdeps_refresh_home/.local/share/shdeps"
  _shdeps_refresh_bin="$_shdeps_refresh_home/fake-bin"
  _shdeps_refresh_remote="$_shdeps_refresh_home/current-install.sh"
  _shdeps_refresh_marker="$_shdeps_refresh_home/remote-installer-ran"
  _shdeps_refresh_stale_marker="$_shdeps_refresh_home/stale-installer-sourced"
  mkdir -p "$_shdeps_refresh_dir" "$_shdeps_refresh_bin"
  printf '%s\n' '{"schema":1,"method":"release","artifact_platform":"linux-x86_64-musl"}' \
    >"$_shdeps_refresh_dir/.shdeps-install.json"
  cat >"$_shdeps_refresh_dir/shdeps" <<'SH'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
  __api:version) printf '%s\n' 'abi:1' ;;
esac
SH
  chmod +x "$_shdeps_refresh_dir/shdeps"
  printf '%s\n' '# installed shdeps fixture' >"$_shdeps_refresh_dir/shdeps.sh"
  cat >"$_shdeps_refresh_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap)
    printf '%s\n' 'stale installer was sourced' >"$SHDEPS_REFRESH_STALE_MARKER"
    shdeps_update() { :; }
    ;;
esac
SH
  cat >"$_shdeps_refresh_remote" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' 'ran' >"$SHDEPS_REFRESH_MARKER"
cat >"$SHDEPS_DIR/shdeps" <<'BIN'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
  __api:version) printf '%s\n' 'abi:1' ;;
esac
BIN
chmod +x "$SHDEPS_DIR/shdeps"
cat >"$SHDEPS_DIR/install.sh" <<'INSTALL'
case "${1:-}" in
  --bootstrap) shdeps_update() { :; } ;;
esac
INSTALL
SH
  cat >"$_shdeps_refresh_bin/curl" <<'SH'
#!/usr/bin/env bash
set -u
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$SHDEPS_REFRESH_REMOTE" "$out"
SH
  chmod +x "$_shdeps_refresh_bin/curl"
  _shdeps_refresh_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_refresh_home" \
      REAL_HOME="$_shdeps_refresh_home" \
      SHDEPS_DIR="$_shdeps_refresh_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_refresh_home/git" \
      SHDEPS_REFRESH_REMOTE="$_shdeps_refresh_remote" \
      SHDEPS_REFRESH_MARKER="$_shdeps_refresh_marker" \
      SHDEPS_REFRESH_STALE_MARKER="$_shdeps_refresh_stale_marker" \
      SHDEPS_FORCE=1 \
      PATH="$_shdeps_refresh_bin:$PATH" \
      _bootstrap_shdeps >/dev/null
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: forced refresh succeeds" \
    "rc=0" "$_shdeps_refresh_result"
  _assert_eq "shdeps bootstrap: forced refresh uses current installer" \
    "ran" "$(cat "$_shdeps_refresh_marker" 2>/dev/null || true)"
  _assert_file_missing "shdeps bootstrap: forced refresh skips stale installer" \
    "$_shdeps_refresh_stale_marker"

  # Fleet machines can retain the source-checkout install shape from before
  # install.sh supported --bootstrap. That default installed tree is managed
  # state, not a dev checkout, and must migrate through the current installer.
  _shdeps_legacy_home=$(_tmpdir)
  _shdeps_legacy_dir="$_shdeps_legacy_home/.local/share/shdeps"
  _shdeps_legacy_bin="$_shdeps_legacy_home/fake-bin"
  _shdeps_legacy_remote="$_shdeps_legacy_home/current-install.sh"
  _shdeps_legacy_marker="$_shdeps_legacy_home/remote-installer-ran"
  mkdir -p "$_shdeps_legacy_dir/.git" "$_shdeps_legacy_bin"
  printf '%s\n' '# legacy shdeps fixture' >"$_shdeps_legacy_dir/shdeps.sh"
  cat >"$_shdeps_legacy_dir/install.sh" <<'SH'
case "${1:-}" in
  "" | --uninstall) ;;
  *)
    printf '%s\n' 'legacy installer does not support --bootstrap' >&2
    exit 2
    ;;
esac
SH
  cat >"$_shdeps_legacy_dir/shdeps" <<'SH'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
  __api:version) printf '%s\n' 'abi:1' ;;
esac
SH
  chmod +x "$_shdeps_legacy_dir/shdeps"
  cat >"$_shdeps_legacy_remote" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' 'ran' >"$SHDEPS_LEGACY_MARKER"
cat >"$SHDEPS_DIR/shdeps" <<'BIN'
#!/usr/bin/env bash
case "${1:-}:${2:-}" in
  __api:version) printf '%s\n' 'abi:1' ;;
esac
BIN
chmod +x "$SHDEPS_DIR/shdeps"
cat >"$SHDEPS_DIR/install.sh" <<'INSTALL'
case "${1:-}" in
  --bootstrap) shdeps_update() { :; } ;;
esac
INSTALL
SH
  cat >"$_shdeps_legacy_bin/curl" <<'SH'
#!/usr/bin/env bash
set -u
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$SHDEPS_LEGACY_REMOTE" "$out"
SH
  chmod +x "$_shdeps_legacy_bin/curl"
  _shdeps_legacy_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_legacy_home" \
      REAL_HOME="$_shdeps_legacy_home" \
      SHDEPS_DIR="$_shdeps_legacy_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_legacy_home/git" \
      SHDEPS_LEGACY_REMOTE="$_shdeps_legacy_remote" \
      SHDEPS_LEGACY_MARKER="$_shdeps_legacy_marker" \
      PATH="$_shdeps_legacy_bin:$PATH" \
      _bootstrap_shdeps >/dev/null 2>&1
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: legacy source checkout recovers" \
    "rc=0" "$_shdeps_legacy_result"
  _assert_eq "shdeps bootstrap: legacy source checkout uses current installer" \
    "ran" "$(cat "$_shdeps_legacy_marker" 2>/dev/null || true)"
  _assert_eq "shdeps bootstrap: migrated source exposes wrapper ABI" \
    "abi:1" "$("$_shdeps_legacy_dir/shdeps" __api version 2>/dev/null || true)"

  # A linked development worktree has a .git file, not the legacy installed
  # checkout's .git directory. It remains caller-owned and should be sourced
  # directly instead of being routed through managed-install migration.
  _shdeps_worktree_home=$(_tmpdir)
  _shdeps_worktree_dir="$_shdeps_worktree_home/linked-shdeps"
  _shdeps_worktree_bin="$_shdeps_worktree_home/fake-bin"
  _shdeps_worktree_marker="$_shdeps_worktree_home/migration-attempted"
  mkdir -p "$_shdeps_worktree_dir" "$_shdeps_worktree_bin"
  printf '%s\n' 'gitdir: /tmp/example-shdeps-gitdir' >"$_shdeps_worktree_dir/.git"
  printf '%s\n' '# linked worktree fixture' >"$_shdeps_worktree_dir/shdeps.sh"
  cat >"$_shdeps_worktree_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap) shdeps_update() { :; } ;;
esac
SH
  cat >"$_shdeps_worktree_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'attempted' >"$SHDEPS_WORKTREE_MARKER"
exit 1
SH
  chmod +x "$_shdeps_worktree_bin/curl"
  _shdeps_worktree_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_worktree_home" \
      REAL_HOME="$_shdeps_worktree_home" \
      SHDEPS_DIR="$_shdeps_worktree_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_worktree_home/git" \
      SHDEPS_WORKTREE_MARKER="$_shdeps_worktree_marker" \
      PATH="$_shdeps_worktree_bin:$PATH" \
      _bootstrap_shdeps >/dev/null 2>&1
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: linked worktree sources directly" \
    "rc=0" "$_shdeps_worktree_result"
  if [[ ! -e "$_shdeps_worktree_marker" ]]; then
    _pass "shdeps bootstrap: linked worktree skips managed migration"
  else
    _fail "shdeps bootstrap: linked worktree skips managed migration"
  fi

  # Dotfiles delegates ownership validation to the current shdeps installer.
  # If that installer rejects migration, dotfiles must leave existing files
  # intact and surface failure rather than source the incompatible installer.
  _shdeps_reject_home=$(_tmpdir)
  _shdeps_reject_dir="$_shdeps_reject_home/.local/share/shdeps"
  _shdeps_reject_bin="$_shdeps_reject_home/fake-bin"
  _shdeps_reject_remote="$_shdeps_reject_home/current-install.sh"
  _shdeps_reject_marker="$_shdeps_reject_home/repair-attempted"
  mkdir -p "$_shdeps_reject_dir/.git" "$_shdeps_reject_bin"
  printf '%s\n' 'preserve me' >"$_shdeps_reject_dir/local-change"
  printf '%s\n' '# legacy shdeps fixture' >"$_shdeps_reject_dir/shdeps.sh"
  cat >"$_shdeps_reject_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap) printf '%s\n' 'sourced' >"$SHDEPS_REJECT_SOURCE_MARKER" ;;
esac
SH
  _shdeps_reject_source_marker="$_shdeps_reject_home/stale-installer-sourced"
  cat >"$_shdeps_reject_remote" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'attempted' >"$SHDEPS_REJECT_MARKER"
exit 37
SH
  cat >"$_shdeps_reject_bin/curl" <<'SH'
#!/usr/bin/env bash
set -u
out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$SHDEPS_REJECT_REMOTE" "$out"
SH
  chmod +x "$_shdeps_reject_bin/curl"
  _shdeps_reject_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_reject_home" \
      REAL_HOME="$_shdeps_reject_home" \
      SHDEPS_DIR="$_shdeps_reject_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_reject_home/git" \
      SHDEPS_REJECT_REMOTE="$_shdeps_reject_remote" \
      SHDEPS_REJECT_MARKER="$_shdeps_reject_marker" \
      SHDEPS_REJECT_SOURCE_MARKER="$_shdeps_reject_source_marker" \
      PATH="$_shdeps_reject_bin:$PATH" \
      _bootstrap_shdeps >/dev/null 2>&1
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: rejected migration fails" \
    "rc=1" "$_shdeps_reject_result"
  _assert_eq "shdeps bootstrap: rejected migration used current installer" \
    "attempted" "$(cat "$_shdeps_reject_marker" 2>/dev/null || true)"
  _assert_file_content "shdeps bootstrap: rejected migration preserves existing files" \
    "preserve me" "$_shdeps_reject_dir/local-change"
  if [[ ! -e "$_shdeps_reject_source_marker" ]]; then
    _pass "shdeps bootstrap: rejected migration does not source stale installer"
  else
    _fail "shdeps bootstrap: rejected migration does not source stale installer"
  fi

  _shdeps_pin_home=$(_tmpdir)
  _shdeps_pin_dir=$(_tmpdir)
  _shdeps_pin_bin="$_shdeps_pin_home/fake-bin"
  _shdeps_pin_marker="$_shdeps_pin_home/curl-ran"
  mkdir -p "$_shdeps_pin_dir" "$_shdeps_pin_bin"
  cat >"$_shdeps_pin_dir/.shdeps-install.json" <<'JSON'
{"schema":1,"method":"release","artifact_platform":"linux-aarch64-musl"}
JSON
  cat >"$_shdeps_pin_dir/shdeps" <<'SH'
#!/usr/bin/env bash
exit 126
SH
  chmod +x "$_shdeps_pin_dir/shdeps"
  printf '%s\n' '# explicit shdeps fixture' >"$_shdeps_pin_dir/shdeps.sh"
  cat >"$_shdeps_pin_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap) shdeps_update() { :; } ;;
esac
SH
  cat >"$_shdeps_pin_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'ran' >"$SHDEPS_PIN_MARKER"
exit 1
SH
  chmod +x "$_shdeps_pin_bin/curl"
  _shdeps_pin_result=$(
    unset SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_pin_home" \
      REAL_HOME="$_shdeps_pin_home" \
      SHDEPS_LIB="$_shdeps_pin_dir/shdeps.sh" \
      SHDEPS_DIR="$_shdeps_pin_home/.local/share/shdeps" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_pin_home/git" \
      SHDEPS_PIN_MARKER="$_shdeps_pin_marker" \
      PATH="$_shdeps_pin_bin:$PATH" \
      _bootstrap_shdeps >/dev/null
    printf 'rc=%s\n' "$?"
  )
  _assert_contains "shdeps bootstrap: explicit library remains authoritative" \
    "rc=0" "$_shdeps_pin_result"
  _assert_file_missing "shdeps bootstrap: explicit library is not repaired" \
    "$_shdeps_pin_marker"

  _shdeps_quiet_home=$(_tmpdir)
  _shdeps_quiet_dir="$_shdeps_quiet_home/.local/share/shdeps"
  mkdir -p "$_shdeps_quiet_dir"
  cat >"$_shdeps_quiet_dir/install.sh" <<'SH'
case "${1:-}" in
  --bootstrap)
    printf '%s\n' 'curl: (22) The requested URL returned error: 504' >&2
    shdeps_update() { :; }
    ;;
esac
SH
  printf '%s\n' '# installed shdeps fixture' >"$_shdeps_quiet_dir/shdeps.sh"
  _shdeps_quiet_result=$(
    unset SHDEPS_LIB SHDEPS_FORCE DOT_FORCE
    HOME="$_shdeps_quiet_home" \
      REAL_HOME="$_shdeps_quiet_home" \
      SHDEPS_DIR="$_shdeps_quiet_dir" \
      SHDEPS_GIT_DEV_DIR="$_shdeps_quiet_home/git" \
      SHDEPS_REPO="fixture://quiet-bootstrap" \
      DOT_QUIET=1 \
      _bootstrap_shdeps 2>&1 >/dev/null
    printf 'rc=%s\n' "$?"
    if declare -f shdeps_update >/dev/null; then
      printf '%s\n' 'loaded=1'
    else
      printf '%s\n' 'loaded=0'
    fi
  )
  _assert_contains "shdeps bootstrap: quiet installer still loads shdeps" \
    "loaded=1" "$_shdeps_quiet_result"
  _assert_contains "shdeps bootstrap: quiet installer succeeds" \
    "rc=0" "$_shdeps_quiet_result"
  _assert_not_contains "shdeps bootstrap: quiet installer hides raw curl 504" \
    "curl: (22)" "$_shdeps_quiet_result"

  echo ""
  echo "=== shdeps JSONL field parsing ==="

  # _json_get / _json_num back the shdeps progress adapter. Detail strings can
  # contain commas and colons, and a key can be a substring of another key, so
  # the parser (jq-preferred) must not be confused by either.
  json_line='{"event":"item","group":"cargo","status":"ok","name":"rg","detail":"v1, built: ok","done":3,"done_total":9,"total":42}'
  _assert_eq "json_get: extracts plain string" "item" "$(_json_get event "$json_line")"
  _assert_eq "json_get: string with comma and colon intact" \
    "v1, built: ok" "$(_json_get detail "$json_line")"
  _assert_eq "json_num: extracts number" "42" "$(_json_num total "$json_line")"
  _assert_eq "json_num: key that is a prefix of another key" \
    "3" "$(_json_num "done" "$json_line")"
  _assert_eq "json_get: missing key is empty" "" "$(_json_get nosuchkey "$json_line")"
  _assert_eq "json_num: non-numeric value is empty" "" "$(_json_num name "$json_line")"

  echo ""
  echo "=== Helper primitives ==="

  helper_tmpfile=$(_tmpfile)
  _assert_file_exists "tmpfile: creates a regular file" "$helper_tmpfile"
  _assert_eq "tmpfile: stays inside the managed test root" \
    "$_DOT_TEST_TMP_ROOT" "${helper_tmpfile%/*}"

  _backup_dir
  backup_one="$REPLY"
  _backup_dir
  backup_two="$REPLY"
  if [[ -d "$backup_one" && -d "$backup_two" && "$backup_one" != "$backup_two" ]]; then
    _pass "backup_dir: creates unique directories"
  else
    _fail "backup_dir: creates unique directories"
  fi

  conflict_log=$(_tmpdir)/pull.log
  cat >"$conflict_log" <<'LOG'
error: The following untracked working tree files would be overwritten by checkout:
	.config/nvim/lazy-lock.json
	.config/example/tool.conf
Please move or remove them before you switch branches.
LOG
  result=$(_pull_conflicts_from_log "$conflict_log")
  _assert_contains "pull_conflicts: captures first file" ".config/nvim/lazy-lock.json" "$result"
  _assert_contains "pull_conflicts: captures second file" ".config/example/tool.conf" "$result"

  # _pull_cmd must force LC_ALL=C so git's progress/result messages stay English
  # for _pull_conflicts_from_log and the quiet-output filter, overriding even an
  # LC_ALL already set in the environment.
  # Probe echoes the effective locale and its received args so both the locale
  # override and the quiet-mode --quiet pass-through can be asserted.
  # shellcheck disable=SC2329  # invoked indirectly by _pull_cmd.
  _lc_probe() { printf 'LC_ALL=%s args=[%s]\n' "${LC_ALL:-unset}" "$*"; }
  # The whole subshell's stderr is dropped: a non-English LC_ALL the test box
  # lacks emits a harmless setlocale warning irrelevant to the asserted stdout.
  result=$(
    {
      LC_ALL=fr_FR.UTF-8 DOT_QUIET=0
      _pull_cmd _lc_probe up
    } 2>/dev/null
  )
  _assert_contains "pull_cmd: forces C locale" "LC_ALL=C" "$result"
  _assert_not_contains "pull_cmd: non-quiet omits --quiet" "--quiet" "$result"
  result=$(
    {
      LC_ALL=fr_FR.UTF-8 DOT_QUIET=1
      _pull_cmd _lc_probe up
    } 2>/dev/null
  )
  _assert_contains "pull_cmd: forces C locale in quiet mode" "LC_ALL=C" "$result"
  _assert_contains "pull_cmd: quiet mode appends --quiet" "--quiet" "$result"

  dot_raw_home=$(_tmpdir)
  dot_raw_repo="$dot_raw_home/repo.git"
  git init --bare -q "$dot_raw_repo"
  git --git-dir="$dot_raw_repo" config remote.origin.url \
    git@github.com:cgraf78/dotfiles.git
  git --git-dir="$dot_raw_repo" config remote.origin.pushurl \
    git@github.com:cgraf78/dotfiles.git
  git --git-dir="$dot_raw_repo" config url.https://github.com/.insteadOf \
    git@github.com:
  dot_raw_inode=$(stat -c '%i' "$dot_raw_repo/config" 2>/dev/null ||
    stat -f '%i' "$dot_raw_repo/config")
  (
    GIT="git --git-dir=$dot_raw_repo --work-tree=$dot_raw_home"
    _prefer_base_dotfiles_ssh_remote
  )
  _assert_eq "dotfiles remote: converged raw SSH config keeps its inode" \
    "$dot_raw_inode" \
    "$(stat -c '%i' "$dot_raw_repo/config" 2>/dev/null || stat -f '%i' "$dot_raw_repo/config")"
  _assert_eq "dotfiles remote: converged raw fetch URL remains SSH" \
    "git@github.com:cgraf78/dotfiles.git" \
    "$(git --git-dir="$dot_raw_repo" config --get remote.origin.url)"
  _assert_eq "dotfiles remote: converged raw push URL remains SSH" \
    "git@github.com:cgraf78/dotfiles.git" \
    "$(git --git-dir="$dot_raw_repo" config --get remote.origin.pushurl)"

  dot_fb_home=$(_tmpdir)
  dot_fb_bin="$dot_fb_home/bin"
  dot_fb_log="$dot_fb_home/git.log"
  dot_fb_remote="$dot_fb_home/remote.txt"
  dot_fb_push_remote="$dot_fb_home/push-remote.txt"
  mkdir -p "$dot_fb_bin" "$dot_fb_home/.dotfiles"
  printf '%s\n' 'https://github.com/cgraf78/dotfiles.git' >"$dot_fb_remote"
  printf '%s\n' 'https://github.com/cgraf78/dotfiles.git' >"$dot_fb_push_remote"
  cat >"$dot_fb_bin/git" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DOTFILES_REMOTE_LOG"
while [[ "$1" == --git-dir=* || "$1" == --work-tree=* ]]; do
  shift
done
if [[ "$1" = config && "$2" = --local && "$3" = --null && "$4" = --get-regexp ]]; then
  printf 'remote.origin.url\n%s\0' "$(cat "$DOTFILES_REMOTE_FILE")"
  printf 'remote.origin.pushurl\n%s\0' "$(cat "$DOTFILES_PUSH_REMOTE_FILE")"
  exit 0
fi
if [[ "$1" = remote && "$2" = set-url && "$3" = origin ]]; then
  printf '%s\n' "$4" >"$DOTFILES_REMOTE_FILE"
  exit 0
fi
if [[ "$1" = remote && "$2" = set-url && "$3" = --push && "$4" = origin ]]; then
  printf '%s\n' "$5" >"$DOTFILES_PUSH_REMOTE_FILE"
  exit 0
fi
if [[ "$1" = pull ]]; then
  [[ "$(cat "$DOTFILES_REMOTE_FILE")" = git@github.com:cgraf78/dotfiles.git ]]
  exit $?
fi
exit 1
SH
  chmod +x "$dot_fb_bin/git"
  _dotfiles_pull_fallback_fixture() {
    local DOTFILES="$dot_fb_home/.dotfiles"
    # shellcheck disable=SC2034  # _pull_base reads the scoped GIT value.
    local GIT="git --git-dir=$DOTFILES --work-tree=$dot_fb_home"
    local DOT_QUIET=0
    local DOTFILES_REMOTE_LOG="$dot_fb_log"
    local DOTFILES_REMOTE_FILE="$dot_fb_remote"
    local DOTFILES_PUSH_REMOTE_FILE="$dot_fb_push_remote"
    local PATH="$dot_fb_bin:/usr/bin:/bin"
    export DOTFILES_REMOTE_LOG DOTFILES_REMOTE_FILE DOTFILES_PUSH_REMOTE_FILE
    _pull_base >/dev/null 2>&1
    printf 'rc=%s\n' "$?"
  }
  dot_fb_result=$(_dotfiles_pull_fallback_fixture)
  unset -f _dotfiles_pull_fallback_fixture
  dot_fb_calls=$(cat "$dot_fb_log")
  _assert_contains "dotfiles pull: checks legacy HTTPS origin" \
    "config --local --null --get-regexp" "$dot_fb_calls"
  _assert_contains "dotfiles pull: switches legacy origin to SSH" \
    "remote set-url origin git@github.com:cgraf78/dotfiles.git" "$dot_fb_calls"
  _assert_contains "dotfiles pull: switches push URL to SSH" \
    "remote set-url --push origin git@github.com:cgraf78/dotfiles.git" "$dot_fb_calls"
  _assert_contains "dotfiles pull: succeeds after origin migration" "rc=0" "$dot_fb_result"
  _assert_eq "dotfiles pull: remote file updated" \
    "git@github.com:cgraf78/dotfiles.git" "$(cat "$dot_fb_remote")"
  _assert_eq "dotfiles pull: push remote file updated" \
    "git@github.com:cgraf78/dotfiles.git" "$(cat "$dot_fb_push_remote")"
}
