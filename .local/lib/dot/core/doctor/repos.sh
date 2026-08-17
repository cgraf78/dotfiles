# shellcheck shell=bash
# dot doctor: Repos checks.
#
# shellcheck disable=SC2088  # tilde strings here are display text.

_dr_is_dotfiles_checkout() {
  local root home_real root_real

  root=$(git -C "$HOME" rev-parse --show-toplevel 2>/dev/null) || return 1
  home_real=$(cd "$HOME" 2>/dev/null && pwd -P) || return 1
  root_real=$(cd "$root" 2>/dev/null && pwd -P) || return 1
  [[ "$root_real" == "$home_real" ]] || return 1

  # CI tests run from an Actions checkout with HOME set to the workspace.
  # That checkout is a valid source tree even though it is not the installed
  # bare-repo layout used on real machines, so verify tracked dot
  # infrastructure rather than accepting any arbitrary HOME git repository.
  # DOT_BIN is absolute; ls-files pathspecs are worktree-relative (root == HOME
  # is verified above), so strip the leading $HOME/ to reuse the one constant.
  git -C "$root" ls-files --error-unmatch \
    "${DOT_BIN#"$HOME/"}" \
    .local/lib/dot/core/doctor.sh \
    .local/lib/dot/core/doctor/runtime.sh >/dev/null 2>&1
}
_dr_check_base_repo() {
  _dr_section "Dotfiles base repo"

  if [[ ! -d "$DOTFILES" ]]; then
    if _dr_is_dotfiles_checkout; then
      _dr_ok "dotfiles checkout exists" "regular checkout rooted at \$HOME"
      return 0
    fi
    _dr_fail "~/.dotfiles missing" "bare repo not cloned — run dotbootstrap"
    return 0
  fi
  _dr_ok "~/.dotfiles exists"

  # The repo can be either core.bare=true (classic bare repo) or
  # core.bare=false with an explicit core.worktree (works identically
  # since $GIT passes --work-tree=$HOME). Both are valid.
  local is_bare has_worktree
  is_bare=$($GIT config --get core.bare 2>/dev/null || echo false)
  has_worktree=$($GIT config --get core.worktree 2>/dev/null || echo "")
  if [[ "$is_bare" == "true" ]]; then
    _dr_ok "core.bare = true"
  elif [[ -n "$has_worktree" ]]; then
    _dr_ok "core.bare = false with explicit worktree" "$(_dr_tilde "$has_worktree")"
  else
    _dr_fail "core.bare not true and no core.worktree" \
      "expected bare repo or explicit worktree — run dotbootstrap"
  fi

  # worktree: either configured via core.worktree OR dot uses --work-tree flag.
  # Our GIT wrapper passes --work-tree=$HOME explicitly, so a missing
  # core.worktree is fine as long as dot always uses $GIT. Verify by running
  # any git command through $GIT.
  if $GIT rev-parse --show-toplevel &>/dev/null; then
    local wt
    wt=$($GIT rev-parse --show-toplevel 2>/dev/null)
    if [[ "$wt" == "$HOME" ]]; then
      _dr_ok "work-tree resolves to \$HOME"
    else
      _dr_fail "work-tree mismatch" "expected $HOME, got $wt"
    fi
  else
    _dr_fail "git cannot resolve work-tree via \$GIT wrapper"
  fi

  # dot CLI on PATH and points to the tracked copy
  if command -v dot >/dev/null 2>&1; then
    local dot_path
    dot_path=$(command -v dot)
    if [[ "$dot_path" == "$DOT_BIN" ]]; then
      _dr_ok "dot CLI on PATH" "$(_dr_tilde "$dot_path")"
    else
      _dr_warn "dot CLI resolves outside dotfiles" "$dot_path"
    fi
  else
    _dr_fail "dot not on PATH" "\$HOME/.local/bin missing from PATH?"
  fi

  # Phantom dirty status — tracked files that match the committed blob but
  # show as modified (typically a line-ending or mode-bit artifact).
  # `git status --porcelain` vs actual diff size mismatch indicates trouble.
  local dirty_count
  dirty_count=$($GIT status --porcelain 2>/dev/null | grep -cvE '^\?\?' || true)
  if [[ "$dirty_count" -eq 0 ]]; then
    _dr_ok "no uncommitted changes"
  else
    _dr_warn "$dirty_count uncommitted file(s)" "run 'dot status' to inspect"
  fi

  # Head not detached
  local head_ref
  head_ref=$($GIT symbolic-ref --short HEAD 2>/dev/null || echo "")
  if [[ -n "$head_ref" ]]; then
    _dr_ok "HEAD on branch" "$head_ref"
  else
    _dr_warn "HEAD is detached" "on a raw commit — 'git switch main' to reattach"
  fi
}
