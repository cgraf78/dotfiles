# shellcheck shell=bash
# Merge Codex CLI config into ~/.codex/config.toml.
# Shared by dotbootstrap and dot (on pull).
# Requires mikefarah/yq from shdeps and python3.
#
# Layers come from codex/config.d. Direct files aggregate in lexical order;
# each immediate *.replace directory contributes only its last lexical file, so
# overlays can express environment-specific overrides without this hook knowing
# those environment names.
#
# Named profiles are rendered from codex/profiles/<name>.d fragments into
# ~/.codex/<name>.config.toml overlay files.
#
# Local-only Codex keys are preserved, including CLI-managed state such as
# notice.model_migrations and tui.model_availability_nux. Those fields change
# as Codex runs, so tracking them in dotfiles causes meaningless churn.

# Resolve from the moved core hook back to the declarative Codex source tree.
# Tests source this hook while HOME points at a fixture, so this cannot rely on
# $HOME for the implementation checkout.
_dot_codex_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
_dot_codex_source_dir="${DOT_CODEX_SOURCE_DIR:-$_dot_codex_hook_dir/../../../../../../.config/dot/merge-hooks.d/codex}"
_dot_codex_config_lib="${DOT_CODEX_CONFIG_LIB:-$_dot_codex_source_dir/api.sh}"
_dot_codex_trust_helper="${DOT_CODEX_TRUST_HELPER:-$_dot_codex_source_dir/refresh-trust.py}"
# shellcheck source=../../../../../../.config/dot/merge-hooks.d/codex/api.sh disable=SC1091
. "$_dot_codex_config_lib"

merge() {
  _dot_tool_present codex || return 0
  dot_codex_config_merge
}
