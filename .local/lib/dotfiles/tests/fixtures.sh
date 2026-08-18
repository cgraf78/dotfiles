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
  # Standalone dot accepts the historical bare separate-Git-dir topology only
  # when it has a single durable repository identity. The fixture's self URL
  # supplies that identity without introducing network or a second checkout.
  git --git-dir="$DOTFILES" remote add origin "file://$DOTFILES"
  # shellcheck disable=SC2086  # GIT is intentionally word-split.
  _git_set_test_identity $GIT
}

dot_fixture_copy_core() {
  local source_home=${DOT_TEST_SOURCE_HOME:-$REAL_HOME}

  # Client-policy tests execute the standalone engine from its own checkout and
  # copy only the consumer-owned extensions into the fixture HOME. Keeping this
  # helper name avoids churn in the retained application suites while ensuring
  # no embedded engine tree is recreated after cutover.
  mkdir -p "$TEST_HOME/.config/dot" "$TEST_HOME/.local/lib/dotfiles"
  cp -R "$source_home/.local/lib/dotfiles/merge-hooks.d" \
    "$TEST_HOME/.local/lib/dotfiles/"
  cp -R "$source_home/.local/lib/dotfiles/doctor.d" \
    "$TEST_HOME/.local/lib/dotfiles/"
  cat >"$TEST_HOME/.config/dot/config" <<'CONF'
version=1
extension_api=1
extensions_dir=$HOME/.local/lib/dotfiles
dependency_provider=none
CONF
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
  local dot_root

  dot_root=$(_test_dot_root) || return 1
  DOT_SOURCE_ROOT=$dot_root
  DOT_CONFIG_VERSION=1
  DOT_EXTENSION_API=1
  DOT_EXTENSIONS_DIR=$TEST_HOME/.local/lib/dotfiles
  DOT_DEPENDENCY_PROVIDER=none
  export DOT_SOURCE_ROOT DOT_CONFIG_VERSION DOT_EXTENSION_API
  export DOT_EXTENSIONS_DIR DOT_DEPENDENCY_PROVIDER
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/xdg.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/runtime.sh"
  # Retained client-policy suites probe logical application presence and
  # provider adapters directly; production hooks load this compatibility layer
  # through the public hook API in their isolated workers.
  dot_hook_source merge-hooks.d/lib/compat.sh
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
