# shellcheck shell=bash
# Hook for editorconfig-checker — lints .editorconfig files.
#
# The upstream release binary is named `ec`; some packages expose
# `editorconfig-checker` instead. Keep both names discoverable without hiding
# release/package update policy behind a custom install hook.

_editorconfig_checker_cmd() {
  local candidate name path_dir

  # PATH can contain stale version-manager shims. Probe every matching
  # binary instead of trusting the first command name resolution. Preserve
  # PATH order across both accepted binary names.
  local IFS=:
  for path_dir in $PATH; do
    [[ -n "$path_dir" ]] || path_dir=.
    for name in editorconfig-checker ec; do
      candidate="$path_dir/$name"
      [[ -x "$candidate" ]] || continue
      "$candidate" --version &>/dev/null || continue
      echo "$candidate"
      return 0
    done
  done

  return 1
}

exists() {
  _editorconfig_checker_cmd &>/dev/null
}

version() {
  local cmd
  cmd=$(_editorconfig_checker_cmd) || return 0
  "$cmd" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1
}

post() {
  local cmd wrapper
  cmd=$(_editorconfig_checker_cmd) || return 0
  [[ "${cmd##*/}" == "editorconfig-checker" ]] || return 0
  wrapper="$(shdeps_bin_dir)/ec"
  mkdir -p "$(dirname "$wrapper")"
  ln -sf "$cmd" "$wrapper"
}

uninstall() {
  rm -f "$(shdeps_bin_dir)/ec"
}
