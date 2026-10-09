# shellcheck shell=bash
# static.sh - base repository policy and portability coverage.

dot_core_test_static() {
  local root workflow actions_sha tracked_file output
  local -a git_cmd

  echo "=== Base static policy ==="

  root=$REAL_HOME
  git_cmd=(git -C "$root" --git-dir="$root/.dotfiles")
  if ! "${git_cmd[@]}" rev-parse HEAD >/dev/null 2>&1; then
    root=$(cd -P -- "$BIN_DIR/../.." && pwd -P)
    git_cmd=(git -C "$root")
  fi

  _assert_eq "Dot config: declares one Shdeps update policy" 1 \
    "$(awk -F= '$1 == "shdeps_update_policy" { count++ } END { print count + 0 }' \
      "$root/.config/dot/config")"
  _assert_eq "Dot config: follows the latest Shdeps release policy" latest \
    "$(awk -F= '$1 == "shdeps_update_policy" { print $2 }' \
      "$root/.config/dot/config")"
  _assert_eq "Dot config: keeps the built-in base fallback implicit" 0 \
    "$(awk -F= '$1 == "default_profile" { count++ } END { print count + 0 }' \
      "$root/.config/dot/config")"
  _assert_eq "profile selectors: root-global default preserves dev" \
    $'version=1\nprofile=dev' \
    "$(<"$root/.config/dot/profile-selectors.d/00-default.conf")"

  actions_sha=$(<"$root/.github/cgraf78-actions.lock")
  if [[ $actions_sha =~ ^[0-9a-f]{40}$ ]]; then
    _pass "CI workflow: actions dependency is locked to a full commit"
  else
    _fail "CI workflow: actions dependency is locked to a full commit"
  fi
  workflow=$(<"$root/.github/workflows/test.yml")
  _assert_contains "CI workflow: uses the locked shared workflow" \
    "shell-ci.yml@$actions_sha" "$workflow"
  _assert_contains "CI workflow: does not bootstrap capability payloads" \
    "setup: none" "$workflow"
  _assert_not_contains "CI workflow: avoids moving Dot setup" \
    "setup: dotfiles" "$workflow"
  # shellcheck disable=SC2016 # Match the literal resolver call shape.
  _assert_contains "CI workflow: resolves the latest Dot release per job" \
    'dot_release_tag="$(_dot_release_latest_tag' "$workflow"
  # shellcheck disable=SC2016 # Match the literal export shape.
  _assert_contains "CI workflow: exports the frozen Dot release tag" \
    'export DOT_STACK_DOT_RELEASE_TAG=$dot_release_tag' "$workflow"
  _assert_contains "CI workflow: sources the Dot release resolver" \
    '. .local/lib/dotfiles/tests/dot-runtime-resolve.sh' "$workflow"
  latest_fn=$(sed -n '/^_dot_release_latest_tag/,/^}/p' \
    "$root/.local/lib/dotfiles/tests/dot-runtime-resolve.sh")
  _assert_contains "Dot resolver: retries the latest-release lookup" \
    "--retry-all-errors" "$latest_fn"
  _assert_contains "CI workflow: floats single-shot Dot runtimes to latest" \
    "DOT_STACK_DOT_RELEASE_TAG='latest'" "$workflow"
  if grep -Eq "DOT_STACK_DOT_RELEASE_TAG[[:space:]]*[:=][[:space:]]*['\"]?[0-9]{8}-[0-9]{6}-[0-9a-f]{8}" \
    "$root/.github/workflows/test.yml"; then
    _fail "CI workflow: pins a concrete Dot release instead of floating to latest"
  else
    _pass "CI workflow: floats the Dot release instead of pinning a tag"
  fi
  live_test=$(<"$root/.local/lib/dotfiles/tests/dot-release-live-test")
  # shellcheck disable=SC2016 # Match the literal resolver call shape.
  _assert_contains "Live release suite: resolves the latest Dot tag per run" \
    'LIVE_TAG="$(_dot_release_latest_tag' "$live_test"
  _assert_contains "CI workflow: runs only the literal top-level inventory" \
    ".local/lib/dotfiles/tests/run-ci" "$workflow"
  # shellcheck disable=SC2016 # Match the literal GitHub Actions expression.
  _assert_contains "CI workflow: selects the event's exact PR head" \
    '${{ github.event.pull_request.head.sha || github.sha }}' "$workflow"
  _assert_contains "CI workflow: detaches conventional jobs to that head" \
    '.local/lib/dotfiles/tests/checkout-ci-candidate' "$workflow"
  _assert_contains "CI workflow: prepares the exact Termux candidate head" \
    'termux-host-command:' "$workflow"
  _assert_contains "CI workflow: every Dot invocation enters the resolved wrapper" \
    "stack-dot-runtime control-plane-run-ci" "$workflow"
  _assert_contains "CI workflow: cold bootstrap uses the resolved wrapper" \
    "stack-dot-runtime reproducible-cold-bootstrap" "$workflow"
  # shellcheck disable=SC2016 # Match literal variables in the workflow shell.
  _assert_contains "CI workflow: cold bootstrap isolates the resolved Dot public API" \
    'export DOT_TEST_HOST_HOME=$launcher_home' \
    "$workflow"
  _assert_contains "CI workflow: cold bootstrap restores installed API validation" \
    'unset DOT_TEST_HOST_HOME' \
    "$workflow"
  # shellcheck disable=SC2016 # Match literal variables in the workflow shell.
  _assert_contains "CI workflow: cold bootstrap drops the stacked Dot before doctor" \
    'PATH=${PATH#"${DOT_STACK_DOT_BIN%/*}:"}' \
    "$workflow"
  # shellcheck disable=SC2016 # Match literal variables in the workflow shell.
  _assert_contains "CI workflow: cold bootstrap diagnoses through the managed Dot" \
    '"$public_dot" -ef "$HOME/.local/share/cgraf78/dot/dot"' \
    "$workflow"
  # Order is checked inside the cold-bootstrap job only, so a matching line
  # in another job can neither satisfy nor mask it. Each step must appear in
  # this order: update, drop the stacked Dot, prove the managed public
  # command, then diagnose.
  cold_job=$(awk '
    /^  cold-bootstrap:$/ { inside = 1; print; next }
    inside && /^  [A-Za-z0-9_-]+:$/ { exit }
    inside { print }
  ' "$root/.github/workflows/test.yml")
  # shellcheck disable=SC2016 # Match the literal workflow shell.
  cold_order=(
    '          dot update'
    '          unset DOT_TEST_HOST_HOME'
    '          PATH=${PATH#"${DOT_STACK_DOT_BIN%/*}:"}'
    '          public_dot=$(command -v dot)'
    '          test "$public_dot" = "$HOME/.local/bin/dot"'
    '          test "$public_dot" -ef "$HOME/.local/share/cgraf78/dot/dot"'
    '          dot doctor'
  )
  cold_previous=0
  cold_ordered=1
  for cold_step in "${cold_order[@]}"; do
    cold_line=$(grep -nxF -- "$cold_step" <<<"$cold_job" | head -1 | cut -d: -f1)
    if [[ -z $cold_line || $cold_line -le $cold_previous ]]; then
      cold_ordered=0
      break
    fi
    cold_previous=$cold_line
  done
  if [[ $cold_ordered == 1 ]]; then
    _pass "CI workflow: cold bootstrap switches Dot only after update"
  else
    _fail "CI workflow: cold bootstrap switches Dot only after update"
  fi
  # The installed-profile job lives in a reusable workflow so the overlay
  # repositories can run it against their own pull request revisions.
  installed_workflow_file=$root/.github/workflows/installed-profiles.yml
  installed_workflow=$(<"$installed_workflow_file")
  _assert_contains "CI workflow: runs the installed-profile composition gate" \
    "uses: ./.github/workflows/installed-profiles.yml" "$workflow"
  # shellcheck disable=SC2016 # Match the literal workflow expression.
  _assert_contains "CI workflow: tests the candidate base revision" \
    'dotfiles-ref: ${{ github.event.pull_request.head.sha || github.sha }}' "$workflow"
  _assert_contains "installed profiles: callable by overlay repositories" \
    "workflow_call:" "$installed_workflow"
  _assert_contains "installed profiles: checks out the base repository explicitly" \
    "repository: cgraf78/dotfiles" "$installed_workflow"
  # shellcheck disable=SC2016 # Match the literal workflow expressions.
  _assert_contains "installed profiles: installs the requested nvim revision" \
    'DOT_STACK_NVIM_REVISION: ${{ inputs.nvim-revision }}' "$installed_workflow"
  # shellcheck disable=SC2016 # Match the literal workflow expressions.
  _assert_contains "installed profiles: installs the requested dev revision" \
    'DOT_STACK_DEV_REVISION: ${{ inputs.dev-revision }}' "$installed_workflow"
  _assert_contains "CI workflow: executes unfiltered installed profile tests" \
    "group=installed-profile-dot-test" "$installed_workflow"
  # Each profile and the footprint pass run as parallel legs; overlay
  # callers narrow the legs, base CI keeps every profile and the budgets.
  # shellcheck disable=SC2016 # Match the literal workflow shell.
  _assert_contains "installed profiles: one installed home per leg" \
    'export DOT_STACK_PROFILES=$LEG_PROFILE' "$installed_workflow"
  # shellcheck disable=SC2016 # Match the literal workflow expression.
  _assert_contains "installed profiles: legs run in parallel" \
    'leg: ${{ fromJSON(needs.plan.outputs.legs) }}' "$installed_workflow"
  _assert_contains "installed profiles: one leg failure does not cancel the rest" \
    "fail-fast: false" "$installed_workflow"
  _assert_contains "installed profiles: one stable result check" \
    "name: Result" "$installed_workflow"
  _assert_not_contains "CI workflow: base runs every installed profile" \
    "profiles: dev" "$workflow"
  _assert_not_contains "CI workflow: base keeps the footprint budgets" \
    "footprint: false" "$workflow"
  # Base's shell job already runs the lifecycle, doctor, and stack checks on
  # every Linux platform; only overlay callers add those legs.
  _assert_not_contains "CI workflow: base does not repeat the lifecycle legs" \
    "lifecycle: true" "$workflow"
  _assert_not_contains "CI workflow: base does not repeat the stack leg" \
    "stack: true" "$workflow"
  _assert_contains "installed profiles: stack leg runs only the CI-only set" \
    "run-ci --ci-only" "$installed_workflow"
  _assert_contains "installed profile gate rejects a profile subset in chained modes" \
    "DOT_STACK_PROFILES only applies to test and doctor modes" \
    "$(<"$root/.local/lib/dotfiles/tests/profile-fixture-integration")"
  _assert_contains "CI workflow: pins the installed-profile Neovim release" \
    "neovim/releases/download/v0.12.2/nvim-linux-x86_64.tar.gz" "$installed_workflow"
  _assert_contains "CI workflow: verifies the installed-profile Neovim binary" \
    "fe333ad1dddfeb4b15169859287369207443477288737d4b94c07df7647ae21e" "$installed_workflow"
  _assert_contains "CI workflow: verifies the installed-profile Neovim archive" \
    "31cf85945cb600d96cdf69f88bc68bec814acbff50863c5546adef3a1bcef260" "$installed_workflow"
  # shellcheck disable=SC2016 # Match the literal workflow shell.
  nvim_archive_verify_line=$(grep -nF '            "$archive" | sha256sum --check --strict' \
    "$installed_workflow_file" | head -1 | cut -d: -f1)
  # shellcheck disable=SC2016 # Match the literal workflow shell.
  nvim_extract_line=$(grep -nF '          tar -xzf "$archive"' \
    "$installed_workflow_file" | cut -d: -f1)
  if [[ -n $nvim_archive_verify_line && -n $nvim_extract_line &&
    $nvim_archive_verify_line -lt $nvim_extract_line ]]; then
    _pass "CI workflow: verifies the Neovim archive before extraction"
  else
    _fail "CI workflow: verifies the Neovim archive before extraction"
  fi
  _assert_contains "CI workflow: passes the audited Neovim runtime explicitly" \
    "DOT_STACK_NVIM_BIN:" "$installed_workflow"
  _assert_contains "CI workflow: pins the installed-profile yq release" \
    "mikefarah/yq/releases/download/v4.53.6/yq_linux_amd64" "$installed_workflow"
  _assert_contains "CI workflow: verifies the installed-profile yq binary" \
    "c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385" "$installed_workflow"
  _assert_contains "CI workflow: passes the audited yq runtime explicitly" \
    "DOT_STACK_YQ_BIN:" "$installed_workflow"
  _assert_contains "installed profile gate rejects Neovim suite skips" \
    "installed dot test has no Neovim coverage skip" \
    "$(<"$root/.local/lib/dotfiles/tests/profile-fixture-integration")"
  _assert_contains "installed profile gate publishes owner-suite execution logs" \
    "installed-profile-suite-log" \
    "$(<"$root/.local/lib/dotfiles/tests/profile-fixture-integration")"
  _assert_contains "CI workflow: retains full platform coverage" \
    "matrix-set: full" "$workflow"
  _assert_not_contains "CI workflow: forwards no repository secrets" \
    "secrets: inherit" "$workflow"
  _assert_not_contains "installed profiles: forwards no repository secrets" \
    "secrets: inherit" "$installed_workflow"

  _assert_file_exists "client docs: main guide is present" \
    "$root/.local/share/doc/dotfiles/dotfiles.md"
  _assert_file_exists "client docs: test guide is present" \
    "$root/.local/lib/dotfiles/tests/README.md"
  _assert_contains "Karabiner docs: cross-layer policy points to its public owner" \
    "https://github.com/cgraf78/dotfiles-dev/blob/main/home/.config/dot/merge-hooks.d/vscode/keybindings/README.md#macos-physical-key-ownership" \
    "$(<"$root/.config/dot/merge-hooks.d/karabiner/README.md")"

  echo ""
  echo "=== Profile and ignore policy ==="

  if "${git_cmd[@]}" --work-tree="$root" \
    -c core.excludesFile="$root/.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns.gitignore" \
    check-ignore --no-index -q \
    .config/dot/profile-selectors.local.d/90-local.conf; then
    _pass "profile selectors: machine-local directory is ignored"
  else
    _fail "profile selectors: machine-local directory is ignored"
  fi
  if "${git_cmd[@]}" --work-tree="$root" \
    -c core.excludesFile="$root/.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns.gitignore" \
    check-ignore --no-index -q \
    .config/dot/profiles.d/base.conf; then
    _fail "profile selectors: tracked profile definitions remain visible"
  else
    _pass "profile selectors: tracked profile definitions remain visible"
  fi

  for tracked_file in \
    .ssh/id_ed25519 \
    .ssh/dotfiles-deploy \
    .ssh/dotfiles-personal-deploy \
    .ssh/dotfiles-work-deploy \
    .config/gh/hosts.yml \
    .config/gh/github-pat; do
    if "${git_cmd[@]}" --work-tree="$root" \
      -c core.excludesFile="$root/.config/dot/merge-hooks.d/ignore/ignore.d/10-patterns.gitignore" \
      check-ignore --no-index -q \
      "$tracked_file"; then
      _pass "ignore policy protects $tracked_file"
    else
      _fail "ignore policy protects $tracked_file"
    fi
  done

  echo ""
  echo "=== Shell portability ==="

  _assert_contains "shellcheck: typed inventory includes the CI entry point" \
    $'program\t.local/lib/dotfiles/tests/run-ci' \
    "$(<"$root/.github/shellcheck-files.txt")"

  output=$(
    python3 - "$root" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
blocked = (
    "/mnt/c/Users/chris",
    "/mnt/c/Users/Chris",
    "/mnt/c/Users/cgraf",
    "C:\\Users\\chris",
    "C:\\Users\\Chris",
    "C:\\Users\\cgraf",
    "/home/chris",
    "/home/cgraf",
)
for rel in (".bashrc", ".bash_profile", ".profile", ".zshenv", ".zshrc"):
    path = root / rel
    if not path.is_file():
        continue
    for number, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        for literal in blocked:
            if literal in line:
                print(f"{rel}:{number}:{literal}")
PY
  )
  _assert_eq "account portability: shell entry points avoid local usernames" \
    '' "$output"

  if command -v zsh >/dev/null 2>&1; then
    if zsh -n "$root/.zshenv" "$root/.zprofile" "$root/.zshrc"; then
      _pass "zsh syntax: base entry points parse"
    else
      _fail "zsh syntax: base entry points parse"
    fi
  else
    _pass "zsh syntax: zsh unavailable, skipped"
  fi

  _assert_contains "shell loader: base environment directory is stable" \
    '/.config/shell/env.d' "$(<"$root/.local/lib/dotfiles/shell-loader.sh")"
  _assert_contains "bash entry point: base interactive directory is stable" \
    '/.config/shell/interactive.d' "$(<"$root/.bashrc")"
  _assert_contains "zsh entry point: base interactive directory is stable" \
    '/.config/shell/interactive.d' "$(<"$root/.zshrc")"
}
