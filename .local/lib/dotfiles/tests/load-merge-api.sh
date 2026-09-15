# shellcheck shell=bash
# Test-only loader for client hooks sourced in fresh Bash subprocesses.

_dot_test_api_source_home=${DOT_TEST_SOURCE_HOME:-${REAL_HOME:-$HOME}}
_dot_test_api_host_home=${DOT_TEST_HOST_HOME:-$HOME}
_dot_test_api_root=${DOT_TEST_DOT_ROOT:-}

if [[ -n $_dot_test_api_root ]]; then
  # An explicit root must still be a usable Dot checkout; release roots
  # cannot satisfy this private-engine loader, so reject them loudly.
  [[ -r $_dot_test_api_root/lib/dot/extension-worker.sh ||
    -r $_dot_test_api_root/lib/dot/public/hook-runtime-v1/hook-api.sh ]] ||
    return 1
else
  for _dot_test_api_candidate in \
    "$_dot_test_api_host_home/git/dot" \
    "$_dot_test_api_host_home/.local/share/cgraf78/dot"; do
    [[ -r $_dot_test_api_candidate/lib/dot/extension-worker.sh ||
      -r $_dot_test_api_candidate/lib/dot/public/hook-runtime-v1/hook-api.sh ]] ||
      continue
    _dot_test_api_root=$(cd -P -- "$_dot_test_api_candidate" && pwd -P) || return
    break
  done
fi
[[ -n $_dot_test_api_root ]] || return 1

DOT_SOURCE_ROOT=$_dot_test_api_root
DOT_EXTENSIONS_DIR=$_dot_test_api_source_home/.local/lib/dotfiles
DOT_EXTENSION_API=1
export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR DOT_EXTENSION_API

if [[ -r $_dot_test_api_root/lib/dot/public/hook-runtime-v1/hook-api.sh ]]; then
  _dot_test_api_lib=$_dot_test_api_root/lib/dot/public/hook-runtime-v1
else
  _dot_test_api_lib=$_dot_test_api_root/lib/dot
fi

# shellcheck source=/dev/null
. "$_dot_test_api_root/lib/dot/public/xdg.sh" || return
# shellcheck disable=SC1090 # Members of the resolved runtime directory.
for _dot_test_api_file in log.sh temp.sh merge-block.sh families.sh \
  merge-hooks.sh extension-trust.sh hook-api.sh; do
  # shellcheck source=/dev/null
  . "$_dot_test_api_lib/$_dot_test_api_file" || return
done
dot_hook_source merge-hooks.d/lib/compat.sh || return

unset _dot_test_api_candidate _dot_test_api_host_home _dot_test_api_file
unset _dot_test_api_lib _dot_test_api_root _dot_test_api_source_home
