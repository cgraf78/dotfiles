#!/usr/bin/env bash
# fixtures.sh - dotfiles-specific test fixture builders.
#
# Source helpers.sh before this file. These helpers set up dotfiles runtime
# state for tests; assertions stay in the calling test so coverage remains
# readable.

dot_fixture_home() {
  _mock_home
  # shellcheck disable=SC2034  # TEST_HOME_PHYSICAL is used by calling tests.
  TEST_HOME_PHYSICAL=$(cd "$TEST_HOME" && pwd -P)
}

dot_fixture_base_repo() {
  DOTFILES="$TEST_HOME/.dotfiles"
  GIT="git --git-dir=$DOTFILES --work-tree=$TEST_HOME"

  git init --bare "$DOTFILES" >/dev/null 2>&1
  # shellcheck disable=SC2086  # GIT is intentionally word-split.
  _git_set_test_identity $GIT
}

dot_fixture_copy_core() {
  local engine_root="${1:-$REAL_HOME/.local/lib/dot/core}"

  mkdir -p "$TEST_HOME/.local/lib/dot/core"
  cp "$engine_root/"*.sh "$TEST_HOME/.local/lib/dot/core/"
  cp -R "$engine_root/doctor" "$TEST_HOME/.local/lib/dot/core/"
  cp -R "$engine_root/repos" "$TEST_HOME/.local/lib/dot/core/"
}

dot_fixture_write_shdeps_config() {
  local root="$1"

  mkdir -p "$root/.config/shdeps/hooks.d/fixture"
  cat >"$root/.config/shdeps/deps.conf" <<'CONF'
fixture/test-tool  github:repo
fixture/hook-pack  github:repo
CONF
  cat >"$root/.config/shdeps/hooks.d/fixture/hook-pack.sh" <<'HOOK'
post() {
  mkdir -p "$HOME/.test-hooks"
  printf '%s\n' "$HOME/.local/share/fixture/hook-pack" > "$HOME/.test-hooks/hook-pack"
}
HOOK
}

dot_fixture_shdeps_config() {
  dot_fixture_write_shdeps_config "$TEST_HOME"
}

dot_fixture_seed_base_file() {
  printf '%s\n' "initial" >"$TEST_HOME/.testrc"
  $GIT add .testrc
  $GIT commit -m "initial" >/dev/null 2>&1
}

dot_fixture_seed_bootstrap_files() {
  printf '%s\n' "initial" >"$TEST_HOME/.testrc"
  mkdir -p "$TEST_HOME/.config/dot"
  printf '%s\n' "# placeholder" >"$TEST_HOME/.config/dot/placeholder"
  $GIT add .testrc .config/dot/placeholder
  $GIT commit -m "initial" >/dev/null 2>&1
}

dot_fixture_source_core_init() {
  local engine_root="${1:-$TEST_HOME/.local/lib/dot/core}"

  # shellcheck source=/dev/null
  . "$engine_root/init.sh"
  _ensure_shdeps
}

dot_fixture_seed_repo() {
  local bare="$1" staging="$2"

  git init --bare "$bare" >/dev/null 2>&1
  git clone "$bare" "$staging/.git-tmp" >/dev/null 2>&1
  mv "$staging/.git-tmp/.git" "$staging/.git"
  rm -rf "$staging/.git-tmp"
  _git_set_test_identity git -C "$staging"
  git -C "$staging" add -A >/dev/null 2>&1
  git -C "$staging" commit -m "seed" >/dev/null 2>&1
  git -C "$staging" push >/dev/null 2>&1
}

dot_fixture_file_origin() {
  local out_var="$1" path="$2" content="$3" staging origin parent

  staging=$(_tmpdir)
  parent=$(dirname "$path")
  if [[ "$parent" != "." ]]; then
    mkdir -p "$staging/$parent"
  fi
  printf '%s\n' "$content" >"$staging/$path"

  origin=$(_tmpdir)
  dot_fixture_seed_repo "$origin" "$staging"
  printf -v "$out_var" '%s' "$origin"
}

dot_fixture_clone_repo() {
  local origin="$1" destination="$2"

  git clone "$origin" "$destination" >/dev/null 2>&1
  _git_set_test_identity git -C "$destination"
}

dot_fixture_shdeps_tool_origin() {
  local out_var="$1" staging origin

  staging=$(_tmpdir)
  mkdir -p "$staging/bin"
  cat >"$staging/bin/test-tool" <<'TOOL'
#!/bin/bash
echo "test-tool"
TOOL
  chmod +x "$staging/bin/test-tool"

  origin=$(_tmpdir)
  dot_fixture_seed_repo "$origin" "$staging"
  printf -v "$out_var" '%s' "$origin"
}

dot_fixture_shdeps_hook_pack_origin() {
  local out_var="$1" staging origin

  staging=$(_tmpdir)
  mkdir -p "$staging/review"
  printf '%s\n' "# hook pack" >"$staging/review/README.md"

  origin=$(_tmpdir)
  dot_fixture_seed_repo "$origin" "$staging"
  printf -v "$out_var" '%s' "$origin"
}

dot_fixture_shdeps_overlay_tool_origin() {
  local out_var="$1" staging origin

  staging=$(_tmpdir)
  mkdir -p "$staging/bin"
  cat >"$staging/bin/overlay-tool" <<'TOOL'
#!/bin/bash
echo "overlay-tool"
TOOL
  chmod +x "$staging/bin/overlay-tool"

  origin=$(_tmpdir)
  dot_fixture_seed_repo "$origin" "$staging"
  printf -v "$out_var" '%s' "$origin"
}

dot_fixture_remote_from_base() {
  local out_var="$1" remote

  remote=$(_tmpdir)
  git clone --bare "$DOTFILES" "$remote" >/dev/null 2>&1
  $GIT remote add origin "$remote" 2>/dev/null || $GIT remote set-url origin "$remote"
  $GIT fetch origin >/dev/null 2>&1
  $GIT branch --set-upstream-to="origin/$DEFAULT_BRANCH" "$DEFAULT_BRANCH" >/dev/null 2>&1 || true
  printf -v "$out_var" '%s' "$remote"
}

dot_fixture_mock_crontab() {
  MOCK_CRONTAB=$(_tmpdir)/crontab
  touch "$MOCK_CRONTAB"
  MOCK_BIN=$(_mock_bin)
  export PATH="$MOCK_BIN:$PATH"
  cat >"$MOCK_BIN/crontab" <<CRON
#!/bin/bash
case "\${1:-}" in
  -l) cat "$MOCK_CRONTAB" 2>/dev/null || { echo "no crontab" >&2; exit 1; } ;;
  -r) > "$MOCK_CRONTAB" ;;
  -)  cat > "$MOCK_CRONTAB" ;;
  *)  echo "mock crontab: unknown arg \$1" >&2; exit 1 ;;
esac
CRON
  chmod +x "$MOCK_BIN/crontab"
}
