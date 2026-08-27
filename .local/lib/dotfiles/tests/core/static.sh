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
  _assert_eq "Dot config: remains readable by pre-profile clients" 0 \
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
  _assert_contains "CI workflow: runs only the literal top-level inventory" \
    ".local/lib/dotfiles/tests/run-ci" "$workflow"
  # shellcheck disable=SC2016 # Match the literal GitHub Actions expression.
  _assert_contains "CI workflow: selects the event's exact PR head" \
    '${{ github.event.pull_request.head.sha || github.sha }}' "$workflow"
  _assert_contains "CI workflow: detaches conventional jobs to that head" \
    '.local/lib/dotfiles/tests/checkout-ci-candidate' "$workflow"
  _assert_contains "CI workflow: prepares the exact Termux candidate head" \
    'termux-host-command:' "$workflow"
  _assert_contains "CI workflow: every Dot invocation enters the locked wrapper" \
    "stack-dot-runtime control-plane-run-ci" "$workflow"
  _assert_contains "CI workflow: cold bootstrap uses the locked wrapper" \
    "stack-dot-runtime reproducible-cold-bootstrap" "$workflow"
  _assert_contains "CI workflow: runs one Ubuntu installed-profile composition gate" \
    "name: Installed profile composition" "$workflow"
  _assert_contains "CI workflow: executes unfiltered installed profile tests" \
    "stack-dot-runtime installed-profile-dot-test" "$workflow"
  _assert_contains "CI workflow: pins the installed-profile Neovim release" \
    "neovim/releases/download/v0.12.2/nvim-linux-x86_64.tar.gz" "$workflow"
  _assert_contains "CI workflow: verifies the installed-profile Neovim binary" \
    "fe333ad1dddfeb4b15169859287369207443477288737d4b94c07df7647ae21e" "$workflow"
  _assert_contains "CI workflow: passes the audited Neovim runtime explicitly" \
    "DOT_STACK_NVIM_BIN:" "$workflow"
  _assert_contains "installed profile gate rejects Neovim suite skips" \
    "installed dot test has no Neovim coverage skip" \
    "$(<"$root/.local/lib/dotfiles/tests/profile-fixture-integration")"
  _assert_contains "CI workflow: retains full platform coverage" \
    "matrix-set: full" "$workflow"
  _assert_not_contains "CI workflow: forwards no repository secrets" \
    "secrets: inherit" "$workflow"

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
