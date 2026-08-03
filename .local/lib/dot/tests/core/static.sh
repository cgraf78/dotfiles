# shellcheck shell=bash
# static.sh - static and platform coverage.

dot_core_test_static() {
  # ---------------------------------------------------------------------------
  # Tests: shared platform checks
  # ---------------------------------------------------------------------------

  echo "=== Platform checks ==="

  _libc_probe_path=$(_mock_bin)
  cat >"$_libc_probe_path/uname" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == "-s" ]]; then
  echo Linux
  exit 0
fi
exec /usr/bin/env uname "$@"
MOCK
  cat >"$_libc_probe_path/ldd" <<'MOCK'
#!/usr/bin/env bash
echo "ldd (GNU libc) 2.40"
yes "copyright filler" | head -n 10000
MOCK
  chmod +x "$_libc_probe_path/uname" "$_libc_probe_path/ldd"

  if PATH="$_libc_probe_path:$PATH" _has_compatible_libc; then
    _pass "compatible libc: handles verbose glibc ldd output under pipefail"
  else
    _fail "compatible libc: handles verbose glibc ldd output under pipefail"
  fi

  # ---------------------------------------------------------------------------
  # Tests: static analysis (shellcheck, JSON sorting)
  # ---------------------------------------------------------------------------

  # Determine repo root and git command.
  # Bare dotfiles repo when available; regular checkout (CI) as fallback.
  # Use --git-dir only (no --work-tree) for old bare checkouts. Add
  # `ls-tree --full-tree` below so discovery is not scoped by the caller's CWD
  # when the test is launched from inside another repo under $HOME.
  _lint_root="$REAL_HOME"
  _lint_git=(git --git-dir="${REAL_HOME}/.dotfiles")
  if ! "${_lint_git[@]}" rev-parse HEAD >/dev/null 2>&1; then
    _lint_root="$(cd "${BIN_DIR}/../.." && pwd)"
    _lint_git=(git -C "${_lint_root}")
  fi

  _ci_workflow=$(cat "$_lint_root/.github/workflows/test.yml")
  _ci_has_public_pin=0
  _ci_forwards_secrets=0
  _ci_in_jobs=0
  _ci_in_shell_job=0
  _ci_in_shell_with=0
  _ci_forces_dotfiles_update=0
  _ci_uses_full_matrix=0
  _ci_line_number=0
  _ci_termux_strict_line=0
  _ci_termux_update_line=0
  _ci_termux_smoke_line=0
  _ci_termux_uses_base_profile=0
  while IFS= read -r _ci_line; do
    _ci_line_number=$((_ci_line_number + 1))
    _ci_code=${_ci_line%%#*}
    if [[ "$_ci_code" =~ ^jobs:[[:space:]]*$ ]]; then
      _ci_in_jobs=1
    elif ((_ci_in_jobs)) && [[ "$_ci_code" =~ ^[^[:space:]] ]]; then
      _ci_in_jobs=0
      _ci_in_shell_job=0
      _ci_in_shell_with=0
    elif ((_ci_in_jobs)) && [[ "$_ci_code" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
      if [[ "${BASH_REMATCH[1]}" == "shell" ]]; then
        _ci_in_shell_job=1
      else
        _ci_in_shell_job=0
      fi
      _ci_in_shell_with=0
    elif ((_ci_in_shell_job)) && [[ "$_ci_code" =~ ^[[:space:]]{4}with:[[:space:]]*$ ]]; then
      _ci_in_shell_with=1
    elif ((_ci_in_shell_with)) && [[ "$_ci_code" =~ ^[[:space:]]{6}matrix-set:[[:space:]]+full[[:space:]]*$ ]]; then
      _ci_uses_full_matrix=1
    elif ((_ci_in_shell_with)) && [[ "$_ci_code" =~ ^[[:space:]]{6}force-dotfiles-update:[[:space:]]+true[[:space:]]*$ ]]; then
      _ci_forces_dotfiles_update=1
    elif ((_ci_in_shell_with)) && [[ -n "${_ci_code//[[:space:]]/}" ]] &&
      [[ ! "$_ci_code" =~ ^[[:space:]]{6} ]]; then
      _ci_in_shell_with=0
    fi
    if [[ "$_ci_code" =~ ^[[:space:]]*uses:[[:space:]]+cgraf78/actions/\.github/workflows/shell-ci\.yml@([0-9a-f]{40})[[:space:]]*$ ]]; then
      _ci_has_public_pin=1
    fi
    if ((_ci_in_shell_with)) &&
      [[ "$_ci_code" =~ ^[[:space:]]{8}set[[:space:]]+-euo[[:space:]]+pipefail[[:space:]]*$ ]]; then
      _ci_termux_strict_line=$_ci_line_number
    fi
    if ((_ci_in_shell_with)) &&
      [[ "$_ci_code" =~ ^[[:space:]]{8}HOME=\"\$PWD\"[[:space:]]+PATH=\"\$PWD/\.local/bin:\$PATH\"[[:space:]]+\.local/bin/dot[[:space:]]+update[[:space:]]+--skip-pull[[:space:]]*$ ]]; then
      _ci_termux_update_line=$_ci_line_number
    fi
    if ((_ci_in_shell_with)) &&
      [[ "$_ci_code" =~ ^[[:space:]]{8}HOME=\"\$PWD\"[[:space:]]+PATH=\"\$PWD/\.local/bin:\$PATH\"[[:space:]]+bash[[:space:]]+\.local/lib/dot/tests/android-ci-smoke[[:space:]]*$ ]]; then
      _ci_termux_smoke_line=$_ci_line_number
    fi
    if ((_ci_in_shell_with)) &&
      [[ "$_ci_code" =~ ^[[:space:]]{6}termux-profiles:[[:space:]]+base,neovim[[:space:]]*$ ]]; then
      _ci_termux_uses_base_profile=1
    fi
    if [[ "$_ci_code" =~ ^[[:space:]]*secrets: ]]; then
      _ci_forwards_secrets=1
    fi
  done <<<"$_ci_workflow"
  if ((_ci_has_public_pin)); then
    _pass "CI workflow: pins public dependency setup immutably"
  else
    _fail "CI workflow: pins public dependency setup immutably"
  fi
  _assert_contains "CI workflow: delegates the typed ShellCheck inventory" \
    "shellcheck-inventory-path: .github/shellcheck-files.txt" "$_ci_workflow"
  _assert_contains "CI workflow: scopes the dynamic-source exclusion" \
    "shellcheck-exclude-codes: SC1091" "$_ci_workflow"
  _assert_contains "CI workflow: skips only redundant platform ShellCheck" \
    "DOT_CORE_SKIP_SHELLCHECK=1 .local/bin/dot-test" "$_ci_workflow"
  if ((_ci_forces_dotfiles_update)); then
    _pass "CI workflow: refreshes shdeps before dependency resolution"
  else
    _fail "CI workflow: refreshes shdeps before dependency resolution"
  fi
  if ((_ci_uses_full_matrix)); then
    _pass "CI workflow: requests full platform matrix"
  else
    _fail "CI workflow: requests full platform matrix"
  fi
  if ((_ci_termux_smoke_line > 0)); then
    _pass "CI workflow: routes Android policy smoke through shell CI"
  else
    _fail "CI workflow: routes Android policy smoke through shell CI"
  fi
  if ((_ci_termux_update_line > 0 && _ci_termux_update_line < _ci_termux_smoke_line)); then
    _pass "CI workflow: runs dot update in Termux before policy smoke"
  else
    _fail "CI workflow: runs dot update in Termux before policy smoke"
  fi
  if ((_ci_termux_strict_line > 0 && _ci_termux_strict_line < _ci_termux_update_line)); then
    _pass "CI workflow: propagates Termux dot update failures"
  else
    _fail "CI workflow: propagates Termux dot update failures"
  fi
  if ((_ci_termux_uses_base_profile)); then
    _pass "CI workflow: provides Termux bootstrap prerequisites"
  else
    _fail "CI workflow: provides Termux bootstrap prerequisites"
  fi
  _ci_cold_bootstrap=$(awk '
    /^  cold-bootstrap:/ { capture = 1; job = $1 }
    capture && /^  [a-zA-Z0-9_-]+:/ && $1 != job { exit }
    capture { print }
  ' <<<"$_ci_workflow")
  _assert_contains "CI workflow: schedules an uncached cold bootstrap" \
    "cold-bootstrap:" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap is schedule or manual only" \
    "if: github.event_name == 'schedule' || github.event_name == 'workflow_dispatch'" \
    "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap uses a conventional user" \
    "useradd --create-home --shell /bin/bash dotfiles-ci" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap verifies its conventional HOME" \
    "test \"\$HOME\" = /home/dotfiles-ci" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap clears runner configuration roots" \
    "unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR" \
    "$_ci_cold_bootstrap"
  _ci_cold_home_line=$(grep -nF "          cd \"\$HOME\"" <<<"$_ci_cold_bootstrap" | cut -d: -f1)
  _ci_cold_init_line=$(grep -nF "            bash -s init <\"\$bootstrap\"" <<<"$_ci_cold_bootstrap" | cut -d: -f1)
  if [[ -n "$_ci_cold_home_line" && -n "$_ci_cold_init_line" &&
    "$_ci_cold_home_line" -lt "$_ci_cold_init_line" ]]; then
    _pass "CI workflow: cold bootstrap starts from the conventional HOME"
  else
    _fail "CI workflow: cold bootstrap starts from the conventional HOME"
  fi
  _assert_contains "CI workflow: cold bootstrap pins its exact commit to main" \
    "git push \"\$origin\" \"\$GITHUB_SHA:refs/heads/main\"" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap origin has complete history" \
    "fetch-depth: 0" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap uses the stdin install path" \
    "bash -s init <\"\$bootstrap\"" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap follows with a normal update" \
    "          retry dot update" "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap preserves terminal retry failures" \
    $'              else\n                rc=$?\n              fi' \
    "$_ci_cold_bootstrap"
  _assert_contains "CI workflow: cold bootstrap retries locked Mise downloads" \
    "retry mise install --locked" \
    "$_ci_cold_bootstrap"
  _ci_cold_sha_checks=$(grep -Fc \
    "git --git-dir=\"\$HOME/.dotfiles\" rev-parse HEAD)" \
    <<<"$_ci_cold_bootstrap")
  _assert_eq "CI workflow: cold bootstrap verifies SHA before and after update" \
    "2" "$_ci_cold_sha_checks"
  _assert_not_contains "CI workflow: cold bootstrap does not restore dependency caches" \
    "actions/cache" "$_ci_cold_bootstrap"
  _assert_not_contains "CI workflow: cold bootstrap does not skip pulling" \
    "--skip-pull" "$_ci_cold_bootstrap"
  _assert_not_contains "CI workflow: has no obsolete ds deploy key" \
    "DS_DEPLOY_KEY" "$_ci_workflow"
  if ((_ci_forwards_secrets)); then
    _fail "CI workflow: forwards no repository secrets"
  else
    _pass "CI workflow: forwards no repository secrets"
  fi

  echo "=== Git push policy ==="

  _git_config="$_lint_root/.config/git/config"
  _assert_eq "git push: mismatched upstream names fail closed" \
    "simple" "$(git config --file "$_git_config" --get push.default)"
  _assert_eq "git push: first publish records the remote branch" \
    "true" "$(git config --file "$_git_config" --get push.autoSetupRemote)"

  echo "=== ShellCheck ==="

  _sc_files=()
  while IFS= read -r _tracked; do
    _f="${_lint_root}/${_tracked}"
    [[ -f "$_f" && ! -L "$_f" ]] || continue
    case "$_tracked" in
      .bashrc | .bash_profile | .zprofile | *.sh | *.bash)
        _sc_files+=("$_f")
        continue
        ;;
    esac
    IFS= read -r _first <"$_f" || true
    case "$_first" in
      '#!/usr/bin/env bash' | '#!/bin/bash')
        _sc_files+=("$_f")
        ;;
    esac
  done < <("${_lint_git[@]}" ls-tree -r --full-tree --name-only HEAD)

  _core_shellcheck_jobs() {
    local jobs="${DOT_CORE_SHELLCHECK_JOBS:-8}"
    case "$jobs" in
      '' | *[!0-9]*) jobs=8 ;;
    esac
    [[ "$jobs" -lt 1 ]] && jobs=1
    [[ "$jobs" -gt 8 && -z "${DOT_CORE_SHELLCHECK_JOBS:-}" ]] && jobs=8
    [[ "$jobs" -gt "${#_sc_files[@]}" ]] && jobs=${#_sc_files[@]}
    printf '%s\n' "$jobs"
  }

  _run_shellcheck() {
    local jobs output_dir i status failed
    jobs=$(_core_shellcheck_jobs)

    if [[ "$jobs" -le 1 ]]; then
      shellcheck -x -P SCRIPTDIR -e SC1091 "${_sc_files[@]}"
      return $?
    fi

    output_dir=$(_tmpdir)
    for ((i = 0; i < jobs; i++)); do
      (
        chunk=()
        for ((j = i; j < ${#_sc_files[@]}; j += jobs)); do
          chunk+=("${_sc_files[$j]}")
        done

        if [[ "${#chunk[@]}" -eq 0 ]]; then
          printf '0\n' >"$output_dir/$i.status"
          exit 0
        fi

        if shellcheck -x -P SCRIPTDIR -e SC1091 "${chunk[@]}" >"$output_dir/$i.out" 2>&1; then
          printf '0\n' >"$output_dir/$i.status"
        else
          printf '1\n' >"$output_dir/$i.status"
        fi
      ) &
    done
    wait

    failed=0
    for ((i = 0; i < jobs; i++)); do
      status=$(cat "$output_dir/$i.status" 2>/dev/null || printf '1\n')
      if [[ "$status" -ne 0 ]]; then
        failed=1
      fi
      cat "$output_dir/$i.out" 2>/dev/null || true
    done

    [[ "$failed" -eq 0 ]]
  }

  if [[ "${DOT_CORE_SKIP_SHELLCHECK:-0}" == "1" ]]; then
    _pass "shellcheck: delegated to shared CI"
  elif [[ "${#_sc_files[@]}" -eq 0 ]]; then
    _fail "shellcheck: no files discovered"
    printf '    repo root: %s\n' "${_lint_root}" >&2
  elif _sc_output=$(_run_shellcheck 2>&1); then
    _pass "shellcheck: all files clean"
  else
    _fail "shellcheck: findings detected"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_sc_output"
  fi

  _mktemp_tracked=$(_tmpdir)/tracked-files
  "${_lint_git[@]}" ls-tree -r --full-tree --name-only HEAD >"$_mktemp_tracked"
  _mktemp_template_errors=$(
    python3 - "$_lint_root" "$_mktemp_tracked" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = Path(sys.argv[2])
template_re = re.compile(
    r"mktemp(?:\s+-[A-Za-z]+)*\s+(?P<quote>['\"]?)(?P<template>[^'\"\s)]*X{3,}[^'\"\s)]*)"
)

for rel in tracked.read_text().splitlines():
    rel = rel.strip()
    if not rel:
        continue
    path = root / rel
    if not path.is_file() or path.is_symlink():
        continue
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        if "mktemp" not in line or "XXX" not in line:
            continue
        for match in template_re.finditer(line):
            template = match.group("template")
            last_x = template.rfind("X")
            if last_x != -1 and last_x != len(template) - 1:
                print(f"{rel}:{lineno}: mktemp template must end in Xs: {template}")
PY
  )
  if [[ -z "$_mktemp_template_errors" ]]; then
    _pass "mktemp: explicit templates keep X suffix at end"
  else
    _fail "mktemp: explicit templates keep X suffix at end"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_mktemp_template_errors"
  fi

  _merge_hook_layout_errors=$(
    python3 - "$_lint_root" "$_mktemp_tracked" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = Path(sys.argv[2])
config_root = Path(".config/dot/merge-hooks.d")
legacy_script_root = root / ".local/lib/dot/core/merge-hooks.d"
script_root = root / ".local/lib/dot/core/merge-hooks"

if legacy_script_root.exists():
    print(f"{legacy_script_root.relative_to(root)}: merge hook implementations belong under .local/lib/dot/core/merge-hooks")

config_names = set()
config_scripts = []
for line in tracked.read_text().splitlines():
    rel = Path(line.strip())
    if not rel.parts or rel.parts[: len(config_root.parts)] != config_root.parts:
        continue
    remainder = rel.relative_to(config_root)
    if len(remainder.parts) == 1:
        if remainder.suffix == ".sh":
            config_scripts.append(rel)
        continue
    config_names.add(remainder.parts[0])

for rel in sorted(config_scripts):
    print(f"{rel}: merge hook scripts belong under .local/lib/dot/core/merge-hooks")

for name in sorted(config_names):
    path = config_root / name
    if len(name) >= 3 and name[:2].isdigit() and name[2] == "-":
        print(f"{path}: top-level hook instance dirs must be unprefixed")
    script = script_root / f"{name}.sh"
    if not script.is_file():
        print(f"{path}: missing matching script {script.relative_to(root)}")
PY
  )
  if [[ -z "$_merge_hook_layout_errors" ]]; then
    _pass "merge hook layout: config dirs match unprefixed core scripts"
  else
    _fail "merge hook layout: config dirs match unprefixed core scripts"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_merge_hook_layout_errors"
  fi

  _account_portability_errors=$(
    python3 - "$_lint_root" "$_mktemp_tracked" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = Path(sys.argv[2])
runtime_prefixes = (
    ".bash",
    ".config",
    ".local/bin",
    ".local/lib/dot",
)
blocked_literals = (
    "/mnt/c/Users/$USER",
    "/mnt/c/Users/${USER}",
    "/mnt/c/Users/chris",
    "/mnt/c/Users/Chris",
    "/mnt/c/Users/cgraf",
    "C:\\Users\\chris",
    "C:\\Users\\Chris",
    "C:\\Users\\cgraf",
    "/home/chris",
    "/home/cgraf",
)

for rel in tracked.read_text().splitlines():
    rel = rel.strip()
    if not rel or rel.startswith(".local/lib/dot/tests/"):
        continue
    if not rel.startswith(runtime_prefixes):
        continue
    path = root / rel
    if not path.is_file() or path.is_symlink():
        continue
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        for literal in blocked_literals:
            if literal not in line:
                continue
            print(
                f"{rel}:{lineno}: ask Windows for USERPROFILE; "
                f"do not hardcode local account path {literal!r}"
            )
            break
        if rel == ".config/hive-memory/config.toml" and line.strip() in {
            'user_id = "chris"',
            'user_id = "cgraf"',
            'user_id = "Chris"',
        }:
            print(f"{rel}:{lineno}: use auto or a machine-local override for user_id")
PY
  )
  if [[ -z "$_account_portability_errors" ]]; then
    _pass "account portability: runtime code avoids local username assumptions"
  else
    _fail "account portability: runtime code avoids local username assumptions"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_account_portability_errors"
  fi

  _predictable_temp_errors=$(
    python3 - "$_lint_root" "$_mktemp_tracked" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
tracked = Path(sys.argv[2])
temp_words = (
    "tmp",
    "cache",
    "manifest",
    "backup",
    "out",
    "state",
)


def shell_like(path, text):
    if path.suffix in {".sh", ".bash"}:
        return True
    first = text.splitlines()[0] if text.splitlines() else ""
    return first.startswith("#!/usr/bin/env bash") or first.startswith("#!/bin/bash")


def predictable_temp_line(line):
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or ".$$" not in line:
        return False
    if any(word in line.lower() for word in temp_words):
        return True
    return ">" in line or "mv " in line or "cp " in line

for rel in tracked.read_text().splitlines():
    rel = rel.strip()
    if not rel or rel.startswith(".local/lib/dot/tests/"):
        continue
    path = root / rel
    if not path.is_file() or path.is_symlink():
        continue
    try:
        text = path.read_text(errors="ignore")
    except OSError:
        continue
    if not shell_like(path, text):
        continue
    for lineno, line in enumerate(text.splitlines(), 1):
        if predictable_temp_line(line):
            print(f"{rel}:{lineno}: use mktemp or _dot_sibling_tmp_for instead of predictable PID-suffixed names")
PY
  )
  if [[ -z "$_predictable_temp_errors" ]]; then
    _pass "temp files: no predictable PID-suffixed names"
  else
    _fail "temp files: no predictable PID-suffixed names"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_predictable_temp_errors"
  fi

  echo ""
  echo "=== Shell config dir constants ==="

  # The shell-startup hot path (.bashrc, .zshrc, shell-loader.sh) keeps
  # env.d/interactive.d as literals so startup never sources constants.sh, while
  # the cold-path doctor validates those dirs via the DOT_SHELL_* constants.
  # Guard against the two drifting apart: read the canonical constants (in a
  # subshell with a sentinel HOME so nothing leaks) and assert each hot-path
  # owner still spells the same relative path. Either side changing alone — the
  # constant or the literal — fails this check.
  _shell_dir_probe=$(
    HOME=/probe-home
    # shellcheck source=/dev/null
    . "$_lint_root/.local/lib/dot/core/constants.sh"
    # shellcheck disable=SC2154  # DOT_SHELL_* come from the sourced constants.sh
    printf '%s\n%s\n' \
      "${DOT_SHELL_ENV_DIR#"$HOME/"}" "${DOT_SHELL_INTERACTIVE_DIR#"$HOME/"}"
  )
  _env_rel=$(sed -n 1p <<<"$_shell_dir_probe")
  _int_rel=$(sed -n 2p <<<"$_shell_dir_probe")

  for _pair in \
    "shell-loader.sh|.local/lib/dot/core/shell-loader.sh|$_env_rel" \
    ".bashrc|.bashrc|$_int_rel" \
    ".zshrc|.zshrc|$_int_rel"; do
    IFS='|' read -r _label _rel _needle <<<"$_pair"
    # Anchor the match so a superset rename (env.d.old, env.d2) can't satisfy a
    # bare substring check: escape the dots, then require a leading '/' and a
    # trailing quote or whitespace — how every hot-path owner spells the path
    # ("$HOME/.config/shell/env.d" or ~/.config/shell/interactive.d bash).
    _needle_re="/${_needle//./\\.}[\"[:space:]]"
    if grep -Eq "$_needle_re" "$_lint_root/$_rel" 2>/dev/null; then
      _pass "shell dir constant: $_label matches DOT_SHELL_* ($_needle)"
    else
      _fail "shell dir constant: $_label drifted from DOT_SHELL_* (expected $_needle)"
    fi
  done

  echo ""
  echo "=== Git ignore safety ==="

  _ignore_fixture=$(_tmpdir)
  git -C "$_ignore_fixture" init -q
  git -C "$_ignore_fixture" config core.excludesFile "$_lint_root/.config/git/ignore"

  _secret_paths=(
    ".ssh/id_ed25519"
    ".ssh/dotfiles-deploy"
    ".ssh/dotfiles-personal-deploy"
    ".ssh/dotfiles-work-deploy"
    ".config/gh/hosts.yml"
    ".config/gh/config.yml"
    ".config/gh/github-pat"
  )

  _ignore_ok=1
  for _secret_path in "${_secret_paths[@]}"; do
    mkdir -p "$_ignore_fixture/$(dirname "$_secret_path")"
    touch "$_ignore_fixture/$_secret_path"
    if ! git -C "$_ignore_fixture" check-ignore -q "$_secret_path"; then
      _fail "git ignore: protects $_secret_path"
      _ignore_ok=0
    fi
  done
  if [[ "$_ignore_ok" -eq 1 ]]; then
    _pass "git ignore: protects local auth and SSH material"
  fi

  echo ""
  echo "=== Checkrun policy ==="

  _checkrun_policy_dir="$_lint_root/.config/checkrun"
  _schema_payload_pattern='*/.local/share/checkrun/schemas/*.schema.json'
  if grep -Fxq "$_schema_payload_pattern" "$_checkrun_policy_dir/ignore"; then
    _fail "checkrun ignores: schema payloads do not use all-phase ignore"
  else
    _pass "checkrun ignores: schema payloads do not use all-phase ignore"
  fi
  if grep -Fxq "$_schema_payload_pattern" "$_checkrun_policy_dir/format-ignore" &&
    grep -Fxq "$_schema_payload_pattern" "$_checkrun_policy_dir/spell-ignore"; then
    _pass "checkrun ignores: schema payloads skip only format and spelling"
  else
    _fail "checkrun ignores: schema payloads skip only format and spelling"
  fi
  if grep -Fxq '*/.config/checkrun/*.json' "$_checkrun_policy_dir/format-ignore" &&
    grep -Fxq '*/.config/checkrun/*.json' "$_checkrun_policy_dir/tool-ignore" &&
    ! grep -Fxq '*/checkrun/*.json' "$_checkrun_policy_dir/format-ignore" &&
    ! grep -Fxq '*/checkrun/*.json' "$_checkrun_policy_dir/tool-ignore"; then
    _pass "checkrun ignores: JSON policy keeps schema validation available"
  else
    _fail "checkrun ignores: JSON policy keeps schema validation available"
  fi
  if grep -Fxq '*/.config/dot/merge-hooks.d/karabiner/profiles.d/*.json' \
    "$_checkrun_policy_dir/format-ignore"; then
    _pass "checkrun ignores: Karabiner profile sources preserve native formatting"
  else
    _fail "checkrun ignores: Karabiner profile sources preserve native formatting"
  fi
  if grep -Fxq '*/.config/nvim/checkrun-editor-metadata.json' \
    "$_checkrun_policy_dir/format-ignore"; then
    _pass "checkrun ignores: generated editor metadata preserves generator bytes"
  else
    _fail "checkrun ignores: generated editor metadata preserves generator bytes"
  fi

  echo ""
  echo "=== Claude settings schema conventions ==="

  _claude_perm_errors=$(
    python3 - "$_lint_root" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
pattern = re.compile(
    r"^((Agent|Bash|Edit|ExitPlanMode|Glob|Grep|KillShell|LSP|"
    r"Monitor|NotebookEdit|PowerShell|Read|Skill|TaskCreate|"
    r"TaskGet|TaskList|TaskOutput|TaskStop|TaskUpdate|TodoWrite|"
    r"ToolSearch|WebFetch|WebSearch|Write)(\((?=.*[^)*?])[^)]+\))?|mcp__.*)$"
)

for path in sorted(root.glob(".config/dot/merge-hooks.d/claude/settings.d/**/*.json")):
    with path.open() as f:
        data = json.load(f)
    for rule in data.get("permissions", {}).get("allow", []):
        if not pattern.match(rule):
            print(f"{path.relative_to(root)}: invalid permission rule: {rule}")
PY
  )
  if [[ -z "$_claude_perm_errors" ]]; then
    _pass "claude settings: permission allow rules match schema"
  else
    _fail "claude settings: permission allow rules match schema"
    while IFS= read -r _line; do
      printf '    %s\n' "$_line" >&2
    done <<<"$_claude_perm_errors"
  fi

  # ---------------------------------------------------------------------------
  # Tests: zsh compatibility
  # ---------------------------------------------------------------------------

  echo ""
  echo "=== Zsh compatibility ==="

  if command -v zsh >/dev/null 2>&1; then
    # 1. Syntax check: zsh -n on all .sh and .zsh files
    _zsh_files=()
    while IFS= read -r _tracked; do
      _f="${_lint_root}/${_tracked}"
      [[ -f "$_f" && ! -L "$_f" ]] || continue
      case "$_tracked" in
        .zshenv | .zshrc | .zprofile | *.sh | *.zsh) _zsh_files+=("$_f") ;;
      esac
    done < <("${_lint_git[@]}" ls-tree -r --full-tree --name-only HEAD)

    if [[ "${#_zsh_files[@]}" -eq 0 ]]; then
      # A discovery that finds nothing is a harness failure, not a clean pass:
      # without this guard the loop below is a no-op and falsely reports success.
      _fail "zsh -n: no files discovered"
      printf '    repo root: %s\n' "${_lint_root}" >&2
    else
      _zsh_syntax_ok=1
      for _f in "${_zsh_files[@]}"; do
        if ! _zsh_err=$(zsh -n "$_f" 2>&1); then
          _fail "zsh -n: $(basename "$_f")"
          printf '    %s\n' "$_zsh_err" >&2
          _zsh_syntax_ok=0
        fi
      done
      if [[ "$_zsh_syntax_ok" -eq 1 ]]; then
        _pass "zsh -n: all files pass syntax check (${#_zsh_files[@]} files)"
      fi
    fi

    # 2. Source shell config: verify .zshrc loads without errors
    # Uses a mock HOME with the repo's shell config. Skips files that
    # are symlinks from overlays (they may not exist in CI).
    _zsh_home=$(_tmpdir)
    # Copy shell entrypoints
    cp "${_lint_root}/.zshenv" "$_zsh_home/.zshenv"
    cp "${_lint_root}/.zshrc" "$_zsh_home/.zshrc"
    cp "${_lint_root}/.zprofile" "$_zsh_home/.zprofile"
    # Copy the shared loader body (sourced by .zshrc)
    mkdir -p "$_zsh_home/.config/shell" \
      "$_zsh_home/.local/bin" \
      "$_zsh_home/.local/lib/dot/core"
    cp "${_lint_root}/.local/lib/dot/core/shell-loader.sh" "$_zsh_home/.local/lib/dot/core/shell-loader.sh"
    cp "${_lint_root}/.local/lib/dot/core/windows.sh" "$_zsh_home/.local/lib/dot/core/windows.sh"
    cp "${_lint_root}/.config/shell/env-noninteractive.sh" \
      "$_zsh_home/.config/shell/env-noninteractive.sh"
    # Copy shell config dirs (only regular files from the repo)
    for _dir in env.d interactive.d; do
      mkdir -p "$_zsh_home/.config/shell/$_dir"
      # Use HEAD, not the bare repo index. These static fixtures should reflect
      # the committed dotfiles tree even if a previous amend/rebase left the
      # bare index stale while the work tree itself is clean.
      while IFS= read -r _tracked; do
        _f="${_lint_root}/${_tracked}"
        [[ -f "$_f" && ! -L "$_f" ]] || continue
        cp "$_f" "$_zsh_home/.config/shell/$_dir/"
      done < <("${_lint_git[@]}" ls-tree -r --full-tree --name-only HEAD -- ".config/shell/$_dir")
    done
    cat >"$_zsh_home/.config/shell/env.d/99-test-load-count.sh" <<'EOF'
SHELL_ENV_TEST_LOAD_COUNT=$((${SHELL_ENV_TEST_LOAD_COUNT:-0} + 1))
export SHELL_ENV_TEST_LOAD_COUNT
EOF
    cat >"$_zsh_home/.config/shell/env.d/99-test-bash-count.bash" <<'EOF'
SHELL_ENV_TEST_BASH_COUNT=$((${SHELL_ENV_TEST_BASH_COUNT:-0} + 1))
export SHELL_ENV_TEST_BASH_COUNT
EOF
    cat >"$_zsh_home/.config/shell/env.d/99-test-zsh-count.zsh" <<'EOF'
SHELL_ENV_TEST_ZSH_COUNT=$((${SHELL_ENV_TEST_ZSH_COUNT:-0} + 1))
export SHELL_ENV_TEST_ZSH_COUNT
EOF
    cat >"$_zsh_home/.local/bin/sley" <<'EOF'
#!/usr/bin/env bash
:
EOF
    cat >"$_zsh_home/.local/bin/git" <<'EOF'
#!/usr/bin/env bash
:
EOF
    chmod +x "$_zsh_home/.local/bin/sley" "$_zsh_home/.local/bin/git"
    mkdir -p "$_zsh_home/.config/gh"
    printf '%s\n' "shell-gh-token" >"$_zsh_home/.config/gh/github-pat"
    chmod 600 "$_zsh_home/.config/gh/github-pat"

    # Minimal PATH for zsh tests — avoids compinit scanning a huge
    # inherited PATH, which can take minutes on machines with many
    # plugin dirs. Include /usr/bin, /bin, and the repo's bin dirs.
    _zsh_path="/usr/local/bin:/usr/bin:/bin:$_zsh_home/.local/bin"

    # Non-interactive source: .zshrc returns early with a non-zero exit
    # from the `[[ -o interactive ]] || return` guard, so we check stderr
    # for actual errors rather than the exit code.
    _zsh_output=$(HOME="$_zsh_home" PATH="$_zsh_path" zsh -c 'source ~/.zshrc' 2>&1 || true)
    if [[ -z "$_zsh_output" ]]; then
      _pass "zsh source: env.d loads without errors"
    else
      _fail "zsh source: env.d loads without errors"
      while IFS= read -r _line; do
        printf '    %s\n' "$_line" >&2
      done <<<"$_zsh_output"
    fi

    _lg_probe_bin="$_zsh_home/.local/bin"
    _lg_probe_log="$(_tmpdir)/lazygit.log"
    cat >"$_lg_probe_bin/git" <<'EOF'
#!/bin/sh
if [ "$1" = "rev-parse" ] && [ "$2" = "--absolute-git-dir" ]; then
  printf '%s\n' "$GIT_MOCK_ABSOLUTE_DIR"
  exit 0
fi
exit 1
EOF
    cat >"$_lg_probe_bin/lazygit" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >"$LAZYGIT_LOG"
EOF
    chmod +x "$_lg_probe_bin/git" "$_lg_probe_bin/lazygit"
    env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh \
      PATH="$_lg_probe_bin:/usr/bin:/bin" \
      GIT_MOCK_ABSOLUTE_DIR="$_zsh_home/.dotfiles" \
      LAZYGIT_LOG="$_lg_probe_log" \
      zsh -ic 'lg log; exit' >/dev/null 2>&1
    _assert_eq "lazygit alias: dotfiles repo passes explicit context and args" \
      "--git-dir=$_zsh_home/.dotfiles --work-tree=$_zsh_home log" \
      "$(cat "$_lg_probe_log" 2>/dev/null || true)"
    env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh \
      PATH="$_lg_probe_bin:/usr/bin:/bin" \
      GIT_MOCK_ABSOLUTE_DIR="$_zsh_home/git/project/.git" \
      LAZYGIT_LOG="$_lg_probe_log" \
      zsh -ic 'lg log; exit' >/dev/null 2>&1
    _assert_eq "lazygit alias: normal repos stay plain" \
      "log" "$(cat "$_lg_probe_log" 2>/dev/null || true)"

    _alias_probe=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="$_zsh_path" \
        zsh -ic 'alias gl >/dev/null 2>&1; printf "gl=%s\n" "$?";
        alias dl >/dev/null 2>&1; printf "dl=%s\n" "$?";
        alias dll >/dev/null 2>&1; printf "dll=%s\n" "$?"; exit' 2>/dev/null
    )
    _assert_contains "aliases: gl remains the git log shortcut" "gl=0" "$_alias_probe"
    _assert_contains "aliases: dl is removed in favor of gl" "dl=1" "$_alias_probe"
    _assert_contains "aliases: dll is removed in favor of gll" "dll=1" "$_alias_probe"

    _wsl_profile_home="$_zsh_home/windows/Users/Actual Profile"
    _wsl_profile_win='C:\Users\Actual Profile'
    _wsl_probe_bin=$(_tmpdir)
    mkdir -p "$_wsl_profile_home" "$_wsl_probe_bin"
    cat >"$_wsl_probe_bin/cmd.exe" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "/D /C set USERPROFILE" ]]; then
  printf '%s\r\n' 'UNC paths are not supported. Defaulting to Windows directory.'
  printf '%s\r\n' 'USERPROFILE=$_wsl_profile_win'
  exit 0
fi
exit 1
EOF
    cat >"$_wsl_probe_bin/wslpath" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "$_wsl_profile_win") printf '%s\n' "$_wsl_profile_home" ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "$_wsl_probe_bin/cmd.exe" "$_wsl_probe_bin/wslpath"
    # shellcheck disable=SC2016 # inner zsh intentionally expands HOME/WINHOME.
    _wsl_alias_probe=$(
      env -i HOME="$_zsh_home" USER="wronglinux" SHELL=/bin/zsh \
        _UNAME=Linux WSL_DISTRO_NAME=Ubuntu DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_wsl_probe_bin/cmd.exe" PATH="$_wsl_probe_bin:$_zsh_path" \
        zsh -fc '. "$HOME/.config/shell/interactive.d/51-aliases-wsl.sh";
          printf "%s\n" "${WINHOME:-}"' 2>/dev/null
    )
    _assert_eq "aliases WSL: WINHOME comes from Windows USERPROFILE" \
      "$_wsl_profile_home" "$_wsl_alias_probe"

    _fake_cmd_probe_bin=$(_tmpdir)
    mkdir -p "$_fake_cmd_probe_bin"
    cat >"$_fake_cmd_probe_bin/cmd.exe" <<'EOF'
#!/usr/bin/env bash
printf '%s\r\n' 'USERPROFILE=C:\Users\Wrong'
EOF
    cat >"$_fake_cmd_probe_bin/wslpath" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  'C:\Windows\System32\cmd.exe') exit 1 ;;
  -w*) printf '%s\n' 'C:\Temp\cmd.exe' ;;
  *) exit 1 ;;
esac
EOF
    chmod +x "$_fake_cmd_probe_bin/cmd.exe" "$_fake_cmd_probe_bin/wslpath"
    # shellcheck disable=SC2016 # inner zsh intentionally expands HOME/REPLY.
    _fake_cmd_probe=$(
      env -i HOME="$_zsh_home" PATH="$_fake_cmd_probe_bin:/usr/bin:/bin" DOT_TEST=0 \
        zsh -fc '. "$HOME/.local/lib/dot/core/windows.sh";
          if dot_wsl_windows_home; then printf "resolved:%s\n" "$REPLY"; else printf "unresolved\n"; fi' 2>/dev/null
    )
    _assert_eq "windows helper: PATH cmd.exe is not trusted as profile authority" \
      "unresolved" "$_fake_cmd_probe"

    # dot_wsl_is_paired_windows_account guards writes into the single shared
    # native Windows profile: two Linux accounts on the same WSL distro (e.g.
    # chris + root) must not both think they own it, or their unlocked writes
    # race on the same file. Cover match, mismatch, and unresolvable cmd.exe.
    _paired_probe_bin=$(_tmpdir)
    mkdir -p "$_paired_probe_bin"
    cat >"$_paired_probe_bin/cmd.exe" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "/D /C set USERNAME" ]]; then
  printf '%s\r\n' 'USERNAME=Chris'
  exit 0
fi
exit 1
EOF
    chmod +x "$_paired_probe_bin/cmd.exe"
    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _paired_match_probe=$(
      env -i HOME="$_zsh_home" PATH="$_paired_probe_bin:/usr/bin:/bin" DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_paired_probe_bin/cmd.exe" bash -c '
          id() { printf "chris\n"; }
          . "$HOME/.local/lib/dot/core/windows.sh"
          if dot_wsl_is_paired_windows_account; then printf "paired\n"; else printf "unpaired\n"; fi'
    )
    _assert_eq "windows helper: paired account matches case-insensitively" \
      "paired" "$_paired_match_probe"

    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _paired_mismatch_probe=$(
      env -i HOME="$_zsh_home" PATH="$_paired_probe_bin:/usr/bin:/bin" DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_paired_probe_bin/cmd.exe" bash -c '
          id() { printf "root\n"; }
          . "$HOME/.local/lib/dot/core/windows.sh"
          if dot_wsl_is_paired_windows_account; then printf "paired\n"; else printf "unpaired\n"; fi'
    )
    _assert_eq "windows helper: second Linux account (e.g. root) is not paired" \
      "unpaired" "$_paired_mismatch_probe"

    # DOT_TEST_WINDOWS_CMD_EXE points at a nonexistent path so cmd.exe
    # resolution fails outright. Restricting PATH alone would not do this:
    # _dot_windows_cmd_exe also probes /mnt/c/Windows/System32/cmd.exe by
    # absolute path, which resolves for real on an actual WSL host regardless
    # of PATH.
    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _paired_unresolvable_probe=$(
      env -i HOME="$_zsh_home" PATH="/usr/bin:/bin" DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_paired_probe_bin/does-not-exist" bash -c '
          id() { printf "chris\n"; }
          . "$HOME/.local/lib/dot/core/windows.sh"
          if dot_wsl_is_paired_windows_account; then printf "paired\n"; else printf "unpaired\n"; fi'
    )
    _assert_eq "windows helper: unresolvable Windows account defaults to unpaired" \
      "unpaired" "$_paired_unresolvable_probe"

    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _paired_override_probe=$(
      env -i HOME="$_zsh_home" PATH="/usr/bin:/bin" DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
        . "$HOME/.local/lib/dot/core/windows.sh"
        if dot_wsl_is_paired_windows_account; then printf "paired\n"; else printf "unpaired\n"; fi'
    )
    _assert_eq "windows helper: DOT_TEST_WSL_PAIRED_ACCOUNT overrides resolution" \
      "paired" "$_paired_override_probe"

    # dot_wsl_writable_windows_home is the guaranteed choke point for hooks
    # that write dotfiles-managed config into the native Windows profile: it
    # must refuse whenever the account is unpaired, even though the
    # underlying dot_wsl_windows_home() would otherwise resolve a real path
    # (as it legitimately does for the read-only WINHOME shell aliases).
    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _writable_home_unpaired_probe=$(
      env -i HOME="$_zsh_home" PATH="$_paired_probe_bin:/usr/bin:/bin" DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_paired_probe_bin/cmd.exe" bash -c '
          id() { printf "root\n"; }
          . "$HOME/.local/lib/dot/core/windows.sh"
          if dot_wsl_writable_windows_home; then printf "resolved:%s\n" "$REPLY"; else printf "refused\n"; fi'
    )
    _assert_eq "windows helper: writable home is refused for an unpaired account" \
      "refused" "$_writable_home_unpaired_probe"

    # Reuses the _wsl_probe_bin/_wsl_profile_home fixture set up above (real
    # USERPROFILE resolution via a trusted DOT_TEST_WINDOWS_CMD_EXE stub) to
    # prove the wrapper returns the exact same path dot_wsl_windows_home()
    # would, once pairing is satisfied.
    # shellcheck disable=SC2016 # inner bash intentionally expands HOME/REPLY.
    _writable_home_paired_probe=$(
      env -i HOME="$_zsh_home" PATH="$_wsl_probe_bin:/usr/bin:/bin" DOT_TEST=0 \
        DOT_TEST_WINDOWS_CMD_EXE="$_wsl_probe_bin/cmd.exe" DOT_TEST_WSL_PAIRED_ACCOUNT=1 bash -c '
          . "$HOME/.local/lib/dot/core/windows.sh"
          if dot_wsl_writable_windows_home; then printf "resolved:%s\n" "$REPLY"; else printf "refused\n"; fi'
    )
    _assert_eq "windows helper: writable home matches dot_wsl_windows_home when paired" \
      "resolved:$_wsl_profile_home" "$_writable_home_paired_probe"

    # shellcheck disable=SC2016 # inner zsh intentionally expands these.
    _login_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        zsh -lc 'case ":$PATH:" in
        *":$HOME/.local/bin:"*) local_bin=yes ;;
        *) local_bin=no ;;
      esac
      printf "bash=%s\nbash_env=%s\ngit=%s\ngh_token=%s\nlocal_bin=%s\nload_count=%s\nzsh_count=%s\n" \
        "$(command -v bash)" "${BASH_ENV:-}" "$(command -v git)" "${GH_TOKEN:-}" \
        "$local_bin" "${SHELL_ENV_TEST_LOAD_COUNT:-0}" "${SHELL_ENV_TEST_ZSH_COUNT:-0}"'
    )
    if [[ -x /opt/homebrew/bin/bash ]]; then
      _assert_contains "zsh login: env.d puts Homebrew before system bash" \
        "bash=/opt/homebrew/bin/bash" "$_login_env"
    fi
    _assert_contains "zsh login: env.d exports BASH_ENV" \
      "bash_env=$_zsh_home/.config/shell/env-noninteractive.sh" "$_login_env"
    _assert_contains "zsh login: local git launcher has PATH priority" \
      "git=$_zsh_home/.local/bin/git" "$_login_env"
    _assert_contains "zsh login: github-pat exports GH_TOKEN" \
      "gh_token=shell-gh-token" "$_login_env"
    _assert_contains "zsh login: env.d prepends local bin" \
      "local_bin=yes" "$_login_env"
    _assert_contains "zsh login: env.d loads once" \
      "load_count=1" "$_login_env"
    _assert_contains "zsh login: zsh env.d files load once" \
      "zsh_count=1" "$_login_env"

    # Non-interactive shells should load the same env.d layer as interactive
    # shells, including PATH and BASH_ENV, so basic commands like `sley` resolve
    # consistently for scripts, editor tasks, hooks, and agent shells.
    # shellcheck disable=SC2016 # inner zsh intentionally expands these.
    _noninteractive_zsh_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        zsh -c 'case ":$PATH:" in
        *":$HOME/.local/bin:"*) local_bin=yes ;;
        *) local_bin=no ;;
      esac
      printf "bash_env=%s\ngit=%s\ngh_token=%s\nlocal_bin=%s\nload_count=%s\nzsh_count=%s\nsley=%s\n" \
        "${BASH_ENV:-}" "$(command -v git)" "${GH_TOKEN:-}" \
        "$local_bin" "${SHELL_ENV_TEST_LOAD_COUNT:-0}" "${SHELL_ENV_TEST_ZSH_COUNT:-0}" \
        "$(command -v sley 2>/dev/null || true)"'
    )
    _assert_contains "zsh noninteractive: env.d exports BASH_ENV" \
      "bash_env=$_zsh_home/.config/shell/env-noninteractive.sh" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: env.d prepends local bin" \
      "local_bin=yes" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: local git launcher has PATH priority" \
      "git=$_zsh_home/.local/bin/git" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: github-pat exports GH_TOKEN" \
      "gh_token=shell-gh-token" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: env.d loads once" \
      "load_count=1" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: zsh env.d files load once" \
      "zsh_count=1" "$_noninteractive_zsh_env"
    _assert_contains "zsh noninteractive: local bin exposes sley" \
      "sley=$_zsh_home/.local/bin/sley" "$_noninteractive_zsh_env"

    # shellcheck disable=SC2016 # inner shells intentionally expand test env.
    _nested_env_probe='printf "load_count=%s\nbash_count=%s\nzsh_count=%s\nsley=%s\n" "${SHELL_ENV_TEST_LOAD_COUNT:-0}" "${SHELL_ENV_TEST_BASH_COUNT:-0}" "${SHELL_ENV_TEST_ZSH_COUNT:-0}" "$(command -v sley 2>/dev/null || true)"'
    _nested_zsh_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        PROBE="$_nested_env_probe" zsh -c "zsh -c \"\$PROBE\""
    )
    _assert_contains "zsh noninteractive nested zsh: env.d stays single-loaded" \
      "load_count=1" "$_nested_zsh_env"
    _assert_contains "zsh noninteractive nested zsh: zsh env.d stays single-loaded" \
      "zsh_count=1" "$_nested_zsh_env"

    # shellcheck disable=SC2016 # inner bash intentionally expands these.
    _noninteractive_bash_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/bash PATH="/usr/bin:/bin" \
        BASH_ENV="$_zsh_home/.config/shell/env-noninteractive.sh" \
        bash -c 'case ":$PATH:" in
        *":$HOME/.local/bin:"*) local_bin=yes ;;
        *) local_bin=no ;;
      esac
      printf "bash_env=%s\ngit=%s\ngh_token=%s\nlocal_bin=%s\nload_count=%s\nbash_count=%s\nsley=%s\n" \
        "${BASH_ENV:-}" "$(command -v git)" "${GH_TOKEN:-}" \
        "$local_bin" "${SHELL_ENV_TEST_LOAD_COUNT:-0}" "${SHELL_ENV_TEST_BASH_COUNT:-0}" \
        "$(command -v sley 2>/dev/null || true)"'
    )
    _assert_contains "bash noninteractive: env.d exports BASH_ENV" \
      "bash_env=$_zsh_home/.config/shell/env-noninteractive.sh" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: env.d prepends local bin" \
      "local_bin=yes" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: local git launcher has PATH priority" \
      "git=$_zsh_home/.local/bin/git" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: github-pat exports GH_TOKEN" \
      "gh_token=shell-gh-token" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: env.d loads once" \
      "load_count=1" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: bash env.d files load once" \
      "bash_count=1" "$_noninteractive_bash_env"
    _assert_contains "bash noninteractive: local bin exposes sley" \
      "sley=$_zsh_home/.local/bin/sley" "$_noninteractive_bash_env"

    _path_dedupe_home=$(_tmpdir)
    _path_dup_a="$_path_dedupe_home/dup-a"
    _path_dup_b="$_path_dedupe_home/dup-b"
    mkdir -p "$_path_dedupe_home/.local/bin" "$_path_dedupe_home/bin" \
      "$_path_dup_a" "$_path_dup_b"
    _path_dedupe_result=$(
      env -i HOME="$_path_dedupe_home" \
        PATH="$_path_dedupe_home/bin:$_path_dup_a:$_path_dup_a:$_path_dedupe_home/.local/bin:$_path_dup_b:$_path_dup_a" \
        "${BASH:-/usr/bin/env bash}" -c ". \"\$1\"; printf \"%s\n\" \"\$PATH\"" \
        _ "$REAL_HOME/.config/shell/env.d/90-path.sh"
    )
    _assert_contains "env.d PATH: managed dirs keep priority" \
      "$_path_dedupe_home/.local/bin:$_path_dedupe_home/bin" "$_path_dedupe_result"
    _path_dup_a_count=$(
      printf '%s\n' "$_path_dedupe_result" |
        tr ':' '\n' |
        awk -v p="$_path_dup_a" '$0 == p { c++ } END { print c + 0 }'
    )
    _assert_eq "env.d PATH: unmanaged duplicates are removed" \
      "1" "$_path_dup_a_count"

    # Non-interactive shells run in editor jobs, hooks, and async prompts. They
    # inherit env.d for PATH, but must not touch terminal state: job-control can
    # stop background helpers before they reach their own script bodies.
    _stty_probe_bin=$(_tmpdir)
    _stty_probe_log="$(_tmpdir)/stty.log"
    cat >"$_stty_probe_bin/uname" <<'EOF'
#!/bin/sh
printf 'Linux\n'
EOF
    cat >"$_stty_probe_bin/stty" <<'EOF'
#!/bin/sh
printf 'stty-called\n' >>"$SHELL_ENV_STTY_LOG"
EOF
    chmod +x "$_stty_probe_bin/uname" "$_stty_probe_bin/stty"
    : >"$_stty_probe_log"
    env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/bash \
      PATH="$_stty_probe_bin:/usr/bin:/bin" \
      BASH_ENV="$_zsh_home/.config/shell/env-noninteractive.sh" \
      SHELL_ENV_STTY_LOG="$_stty_probe_log" \
      bash -c ':'
    _assert_eq "bash noninteractive: env.d does not touch tty state" \
      "" "$(cat "$_stty_probe_log" 2>/dev/null || true)"
    : >"$_stty_probe_log"
    env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh \
      PATH="$_stty_probe_bin:/usr/bin:/bin" \
      SHELL_ENV_STTY_LOG="$_stty_probe_log" \
      zsh -c ':'
    _assert_eq "zsh noninteractive: env.d does not touch tty state" \
      "" "$(cat "$_stty_probe_log" 2>/dev/null || true)"

    _nested_bash_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/bash PATH="/usr/bin:/bin" \
        BASH_ENV="$_zsh_home/.config/shell/env-noninteractive.sh" \
        PROBE="$_nested_env_probe" bash -c "bash -c \"\$PROBE\""
    )
    _assert_contains "bash noninteractive nested bash: env.d stays single-loaded" \
      "load_count=1" "$_nested_bash_env"
    _assert_contains "bash noninteractive nested bash: bash env.d stays single-loaded" \
      "bash_count=1" "$_nested_bash_env"

    _zsh_to_bash_env=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        PROBE="$_nested_env_probe" zsh -c "bash -c \"\$PROBE\""
    )
    _assert_contains "zsh noninteractive nested bash: bash env.d still runs" \
      "bash_count=1" "$_zsh_to_bash_env"
    _assert_contains "zsh noninteractive nested bash: zsh env.d ran first" \
      "zsh_count=1" "$_zsh_to_bash_env"

    # shellcheck disable=SC2016 # inner zsh intentionally expands test env.
    _interactive_output=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        zsh -ic 'printf "\n__load_count__=%s\n" "${SHELL_ENV_TEST_LOAD_COUNT:-0}"; exit' 2>/dev/null
    )
    _interactive_count=$(
      sed -n 's/^__load_count__=//p' <<<"$_interactive_output" | tail -1
    )
    _assert_eq "zsh interactive: env.d loads only once" "1" "$_interactive_count"

    # shellcheck disable=SC2016 # inner zsh intentionally expands test env.
    _login_interactive_output=$(
      env -i HOME="$_zsh_home" USER="$USER" SHELL=/bin/zsh PATH="/usr/bin:/bin" \
        zsh -lic 'printf "\n__load_count__=%s\n" "${SHELL_ENV_TEST_LOAD_COUNT:-0}"; exit' 2>/dev/null
    )
    _login_interactive_count=$(
      sed -n 's/^__load_count__=//p' <<<"$_login_interactive_output" | tail -1
    )
    _assert_eq "zsh login interactive: env.d loads only once" "1" "$_login_interactive_count"

    # 3. Interactive smoke test: loads env.d + interactive.d
    if _zsh_output=$(HOME="$_zsh_home" PATH="$_zsh_path" zsh -ic 'exit' 2>&1); then
      _pass "zsh interactive: starts and exits cleanly"
    else
      _fail "zsh interactive: starts and exits cleanly"
      while IFS= read -r _line; do
        printf '    %s\n' "$_line" >&2
      done <<<"$_zsh_output"
    fi

    # 4. Shell reload: zsh must replace the current shell instead of
    # re-sourcing .zshrc, because ZLE-wrapping plugins are not reliably
    # idempotent inside a live editor session.
    _real_zsh=$(command -v zsh)
    _reload_home=$(_tmpdir)
    _reload_bin="$_reload_home/bin"
    mkdir -p "$_reload_home/.config/shell/interactive.d" "$_reload_bin"
    cp "${_lint_root}/.config/shell/interactive.d/56-dot.sh" \
      "$_reload_home/.config/shell/interactive.d/56-dot.sh"
    cat >"$_reload_home/.zshrc" <<'ZSHRC'
print sourced-zshrc
ZSHRC
    cat >"$_reload_bin/zsh" <<'ZSH'
#!/usr/bin/env bash
printf '%s\n' exec-zsh
exit 37
ZSH
    chmod +x "$_reload_bin/zsh"
    _zsh_output=$(
      HOME="$_reload_home" PATH="$_reload_bin:$_zsh_path" "$_real_zsh" -fc \
        'source ~/.config/shell/interactive.d/56-dot.sh; _reload_shell' 2>&1
    )
    _zsh_rc=$?
    _assert_eq "zsh reload: replaces shell with fresh zsh" "exec-zsh" "$_zsh_output"
    _assert_exit "zsh reload: returns replacement shell status" 37 "$_zsh_rc"

    _dotu_home=$(_tmpdir)
    _dotu_bin="$_dotu_home/bin"
    _dotu_log="$_dotu_home/dotu.log"
    mkdir -p "$_dotu_home/.config/shell/interactive.d" "$_dotu_bin"
    cp "${_lint_root}/.config/shell/interactive.d/56-dot.sh" \
      "$_dotu_home/.config/shell/interactive.d/56-dot.sh"
    cat >"$_dotu_bin/dot" <<'DOT'
#!/usr/bin/env bash
printf 'DOT_UPDATE_RELOADS_SHELL=%s\n' "${DOT_UPDATE_RELOADS_SHELL:-}" >"$DOTU_LOG"
DOT
    chmod +x "$_dotu_bin/dot"
    DOTU_LOG="$_dotu_log" HOME="$_dotu_home" PATH="$_dotu_bin:/usr/bin:/bin" bash -c '
      source ~/.config/shell/interactive.d/56-dot.sh
      _clear_tool_cache() { :; }
      _reload_shell() { :; }
      dotu
    '
    _assert_file_content "dotu: marks update as followed by shell reload" \
      "DOT_UPDATE_RELOADS_SHELL=1" "$_dotu_log"
  else
    echo "  SKIP: zsh not installed"
  fi

  if [[ "${DOT_CORE_STATIC_ONLY:-0}" == "1" ]]; then
    _test_summary
    exit $?
  fi
}
