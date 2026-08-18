# shellcheck shell=bash
# Test-only loader for client hooks sourced in fresh Bash subprocesses.

_dot_test_api_source_home=${DOT_TEST_SOURCE_HOME:-${REAL_HOME:-$HOME}}
_dot_test_api_host_home=${DOT_TEST_HOST_HOME:-$HOME}
_dot_test_api_root=${DOT_TEST_DOT_ROOT:-}

if [[ -z $_dot_test_api_root ]]; then
  for _dot_test_api_candidate in \
    "$_dot_test_api_host_home/git/dot" \
    "$_dot_test_api_host_home/.local/share/cgraf78/dot"; do
    [[ -r $_dot_test_api_candidate/lib/dot/extension-worker.sh ]] || continue
    _dot_test_api_root=$(cd -P -- "$_dot_test_api_candidate" && pwd -P) || return
    break
  done
fi
[[ -n $_dot_test_api_root ]] || return 1

DOT_SOURCE_ROOT=$_dot_test_api_root
DOT_EXTENSIONS_DIR=$_dot_test_api_source_home/.local/lib/dotfiles
DOT_EXTENSION_API=1
export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR DOT_EXTENSION_API

# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/public/xdg.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/log.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/temp.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/merge-block.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/families.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/merge-hooks.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/extension-trust.sh"
# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/hook-api.sh"
dot_hook_source merge-hooks.d/lib/compat.sh || return

unset _dot_test_api_candidate _dot_test_api_host_home
unset _dot_test_api_root _dot_test_api_source_home
