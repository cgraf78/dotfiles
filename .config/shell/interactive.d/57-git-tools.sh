# shellcheck shell=bash
# shellcheck disable=SC2154  # fzf option arrays are defined by 56-dot.sh
# Dotfiles policy for git-tools' reusable interactive shell workflows.
#
# The provider owns Git and worktree mechanics. Keep this adapter intentionally
# boring: it supplies local presentation/editor choices and preserves the short
# commands used at the prompt. That boundary lets other consumers reuse the
# workflows without inheriting this dotfiles repository's naming policy.

# git-tools checks for these hooks before installing standalone defaults. They
# must therefore be defined in the shared .sh layer, before the provider is
# loaded from the shell-specific 70-integrations files.
git_tools_fzf_preview() {
  fzf "${_fzf_preview[@]}" "$@"
}

git_tools_fzf_pick() {
  fzf "${_fzf_pick[@]}" "$@"
}

git_tools_edit_file() {
  _edit_file "$@"
}

# Make the existing layout an explicit consumer policy even though it matches
# git-tools' standalone default. This keeps a future provider default change
# from silently moving dotfiles-managed worktrees.
# The value is read by git-tools after this adapter is sourced.
# shellcheck disable=SC2034
GIT_TOOLS_WORKTREE_PARENT="$HOME/worktrees"

# Preserve the established interactive command surface without duplicating any
# provider behavior. `_worktree_root` is retained because it was previously a
# sourceable helper alongside these commands.
gbr() { git_tools_fzf_branch "$@"; }
glo() { git_tools_fzf_log "$@"; }
gst() { git_tools_fzf_status "$@"; }
gstash() { git_tools_fzf_stash "$@"; }
_worktree_root() { git_tools_worktree_root "$@"; }
gw() { git_tools_worktree "$@"; }
gwl() { git_tools_worktree_list "$@"; }
gwd() { git_tools_worktree_remove "$@"; }
gwp() { git_tools_worktree_prune "$@"; }
