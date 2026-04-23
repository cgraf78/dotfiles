# shellcheck shell=bash
# Health checks for the dotfiles installation. Entry point: `_dot_doctor`.
#
# Aggregates per-section checks that verify the assumptions dot/bootstrap
# make: shell environment, base repo, overlays, tools, git hooks, cron.
# Each check prints one line prefixed with OK / WARN / FAIL and updates a
# counter. The entry point prints a summary and exits non-zero if any FAIL.

# ---------------------------------------------------------------------------
# Output helpers (share color state with core.sh when available)
# ---------------------------------------------------------------------------

# shellcheck disable=SC2088  # tilde-paths in _dr_* arg strings are for display, not expansion

_DR_PASS_COUNT=0
_DR_WARN_COUNT=0
_DR_FAIL_COUNT=0

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _DR_GREEN=$'\033[32m'
  _DR_YELLOW=$'\033[33m'
  _DR_RED=$'\033[31m'
  _DR_DIM=$'\033[2m'
  _DR_BOLD=$'\033[1m'
  _DR_RESET=$'\033[0m'
else
  _DR_GREEN='' _DR_YELLOW='' _DR_RED='' _DR_DIM='' _DR_BOLD='' _DR_RESET=''
fi

_dr_ok() {
  printf '  %s✓%s %s' "$_DR_GREEN" "$_DR_RESET" "$1"
  [[ $# -gt 1 ]] && printf ' %s(%s)%s' "$_DR_DIM" "$2" "$_DR_RESET"
  printf '\n'
  _DR_PASS_COUNT=$((_DR_PASS_COUNT + 1))
}

_dr_warn() {
  printf '  %s⚠%s %s' "$_DR_YELLOW" "$_DR_RESET" "$1"
  [[ $# -gt 1 ]] && printf '\n    %s%s%s' "$_DR_DIM" "$2" "$_DR_RESET"
  printf '\n'
  _DR_WARN_COUNT=$((_DR_WARN_COUNT + 1))
}

_dr_fail() {
  printf '  %s✗%s %s' "$_DR_RED" "$_DR_RESET" "$1"
  [[ $# -gt 1 ]] && printf '\n    %s%s%s' "$_DR_DIM" "$2" "$_DR_RESET"
  printf '\n'
  _DR_FAIL_COUNT=$((_DR_FAIL_COUNT + 1))
}

_dr_skip() {
  printf '  %s·%s %s' "$_DR_DIM" "$_DR_RESET" "$1"
  [[ $# -gt 1 ]] && printf ' %s(%s)%s' "$_DR_DIM" "$2" "$_DR_RESET"
  printf '\n'
}

_dr_section() {
  printf '\n%s%s%s\n' "$_DR_BOLD" "$1" "$_DR_RESET"
}

# ---------------------------------------------------------------------------
# Shell environment
# ---------------------------------------------------------------------------

_dr_check_shell() {
  _dr_section "Shell environment"

  # bash 4+ (required by dot/shdeps — macOS system bash is 3.2)
  local bash_ver
  bash_ver=$(bash --version 2>/dev/null | awk 'NR==1 {match($0, /[0-9]+\.[0-9]+/); print substr($0, RSTART, RLENGTH); exit}')
  if [[ -z "$bash_ver" ]]; then
    _dr_fail "bash not found on PATH"
  elif [[ "${bash_ver%%.*}" -lt 4 ]]; then
    _dr_fail "bash version too old" "found $bash_ver, need >= 4 (brew install bash)"
  else
    _dr_ok "bash version" "$bash_ver"
  fi

  # zsh present (user's primary shell)
  if command -v zsh >/dev/null 2>&1; then
    local zsh_ver
    zsh_ver=$(zsh --version 2>/dev/null | awk '{print $2; exit}')
    _dr_ok "zsh present" "${zsh_ver:-?}"
  else
    _dr_warn "zsh not on PATH" "fine if you only use bash"
  fi

  # EDITOR set
  if [[ -n "${EDITOR:-}" ]]; then
    _dr_ok "EDITOR set" "$EDITOR"
  else
    _dr_warn "EDITOR not set" "tools that spawn an editor may fall back to vi"
  fi

  # BASH_ENV configured — only needed for bash non-interactive paths
  if [[ -n "${BASH_ENV:-}" ]]; then
    if [[ -f "$BASH_ENV" ]]; then
      _dr_ok "BASH_ENV" "$(_dr_tilde "$BASH_ENV")"
    else
      _dr_fail "BASH_ENV set but target missing" "$BASH_ENV"
    fi
  else
    _dr_warn "BASH_ENV unset" "non-interactive bash subshells won't inherit env.d"
  fi

  # Shared shell loader
  local loader="$HOME/.local/lib/dot/shell-loader.sh"
  if [[ -f "$loader" ]]; then
    _dr_ok "shell-loader.sh present"
  else
    _dr_fail "shell-loader.sh missing" "$loader"
  fi

  # rc files exist and reference the shared loader
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ ! -f "$rc" ]]; then
      _dr_fail "$(basename "$rc") missing at \$HOME"
    elif grep -q "shell-loader.sh" "$rc" 2>/dev/null; then
      _dr_ok "$(basename "$rc") sources shared loader"
    else
      _dr_warn "$(basename "$rc") does not reference shell-loader.sh" \
        "may be a stale copy from before the loader extraction"
    fi
  done
}

# ---------------------------------------------------------------------------
# Dotfiles base repo
# ---------------------------------------------------------------------------

_dr_check_base_repo() {
  _dr_section "Dotfiles base repo"

  if [[ ! -d "$DOTFILES" ]]; then
    _dr_fail "~/.dotfiles missing" "bare repo not cloned — run dotbootstrap"
    return 0
  fi
  _dr_ok "~/.dotfiles exists"

  local is_bare
  is_bare=$($GIT config --get core.bare 2>/dev/null || echo false)
  if [[ "$is_bare" == "true" ]]; then
    _dr_ok "core.bare = true"
  else
    _dr_fail "core.bare not true" "expected a bare repo (got core.bare=$is_bare)"
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
    if [[ "$dot_path" == "$HOME/.local/bin/dot" ]]; then
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
    _dr_warn "HEAD is detached" "on a raw commit — 'dot git switch main' to reattach"
  fi
}

# ---------------------------------------------------------------------------
# Overlays
# ---------------------------------------------------------------------------

_dr_check_overlays() {
  local conf_dir="$HOME/.config/dot/overlays.d"
  local conf_count=0
  [[ -d "$conf_dir" ]] && conf_count=$(find "$conf_dir" -maxdepth 1 -name '*.conf' -type f 2>/dev/null | wc -l | tr -d ' ')
  _dr_section "Overlays ($conf_count configured)"

  if [[ "$conf_count" -eq 0 ]]; then
    _dr_skip "no overlays to check"
    return 0
  fi

  # Walk each conf, check against the parsed OVERLAYS array (filtered set).
  local f name want_url
  for f in "$conf_dir"/*.conf; do
    [[ -f "$f" ]] || continue
    name=$(_overlay_name "$f")
    # Extract URL from conf directly (OVERLAYS may have filtered it out).
    want_url=$(awk -F= '/^url=/ {sub(/^url=/, ""); print; exit}' "$f")

    # Is this overlay active for this host?
    local active=0 entry path
    for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
      IFS='|' read -r n path _ <<<"$entry"
      if [[ "$n" == "$name" ]]; then
        active=1
        break
      fi
    done

    if [[ "$active" -eq 0 ]]; then
      _dr_skip "$name" "filtered out for this machine"
      continue
    fi

    if [[ ! -d "$path/.git" ]]; then
      _dr_fail "$name: not cloned" "expected at $(_dr_tilde "$path")"
      continue
    fi
    _dr_ok "$name: cloned" "$(_dr_tilde "$path")"

    # Origin URL matches conf
    local actual_url
    actual_url=$(git -C "$path" config --get remote.origin.url 2>/dev/null || echo "")
    if [[ "$actual_url" == "$want_url" ]]; then
      _dr_ok "$name: remote.origin.url matches conf"
    else
      _dr_warn "$name: remote URL drift" \
        "conf=$want_url vs actual=$actual_url"
    fi

    # Companion .ssh file (if present) references an existing key
    local ssh_conf="${f%.conf}.ssh"
    if [[ -f "$ssh_conf" ]]; then
      local key
      key=$(awk '/^[[:space:]]+IdentityFile /{print $2; exit}' "$ssh_conf")
      if [[ -z "$key" ]]; then
        _dr_warn "$name: .ssh has no IdentityFile"
      else
        # Expand ~
        key="${key/#\~/$HOME}"
        if [[ -f "$key" ]]; then
          _dr_ok "$name: SSH deploy key present" "$(_dr_tilde "$key")"
        else
          _dr_fail "$name: SSH deploy key missing" "$key"
        fi
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

_dr_check_tools() {
  _dr_section "Tools"

  # yq — required by autofmt/autolint
  if command -v yq >/dev/null 2>&1; then
    _dr_ok "yq" "$(yq --version 2>/dev/null | awk '{print $NF}' | head -1)"
  else
    _dr_fail "yq missing" "required by autoformat/autolint — install via 'dot update'"
  fi

  # git — obviously
  if command -v git >/dev/null 2>&1; then
    _dr_ok "git" "$(git --version 2>/dev/null | awk '{print $3}')"
  else
    _dr_fail "git missing"
  fi

  # direnv — if any tracked .envrc suggests it's expected
  # shellcheck disable=SC2016  # intentional literal; we're searching for this string
  if grep -q 'eval "\$(direnv hook' "$HOME/.config/shell/interactive.d/"*.bash "$HOME/.config/shell/interactive.d/"*.zsh 2>/dev/null; then
    if command -v direnv >/dev/null 2>&1; then
      _dr_ok "direnv" "$(direnv version 2>/dev/null)"
    else
      _dr_warn "direnv hook configured but binary missing" "run 'dot update' to install"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Git hooks
# ---------------------------------------------------------------------------

_dr_check_git_hooks() {
  _dr_section "Git hooks"

  local want_hooks="$HOME/.local/share/git-hooks"
  local actual_hooks
  actual_hooks=$(git config --get --global core.hooksPath 2>/dev/null || echo "")
  # Normalize ~
  actual_hooks="${actual_hooks/#\~/$HOME}"

  if [[ "$actual_hooks" == "$want_hooks" ]]; then
    _dr_ok "core.hooksPath" "$(_dr_tilde "$actual_hooks")"
  elif [[ -z "$actual_hooks" ]]; then
    _dr_warn "core.hooksPath not set globally" \
      "dotfiles ship a pre-commit hook — see $(_dr_tilde "$want_hooks")"
  else
    _dr_warn "core.hooksPath points elsewhere" "got $actual_hooks, expected $(_dr_tilde "$want_hooks")"
  fi

  if [[ -x "$want_hooks/pre-commit" ]]; then
    _dr_ok "pre-commit hook present and executable"
  elif [[ -f "$want_hooks/pre-commit" ]]; then
    _dr_fail "pre-commit hook not executable" "chmod +x $want_hooks/pre-commit"
  else
    _dr_warn "pre-commit hook missing" "$want_hooks/pre-commit"
  fi
}

# ---------------------------------------------------------------------------
# Cron
# ---------------------------------------------------------------------------

_dr_check_cron() {
  _dr_section "Cron"

  local cron_src="$HOME/.config/dot/merge-hooks.d/cron"
  if [[ ! -f "$cron_src" ]]; then
    _dr_skip "no tracked cron entries to check"
    return 0
  fi

  local crontab_out
  crontab_out=$(crontab -l 2>/dev/null || echo "")
  if [[ -z "$crontab_out" ]]; then
    _dr_warn "user crontab is empty" "run 'dot update' to install tracked entries"
    return 0
  fi

  # Spot-check: the dot update auto-cron should be present
  if echo "$crontab_out" | grep -q 'dot update --cron'; then
    _dr_ok "auto-update cron entry present"
  else
    _dr_warn "auto-update cron not found" "run 'dot update' to install from merge-hooks.d/cron"
  fi
}

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

# Abbreviate a path by replacing $HOME with ~.
_dr_tilde() {
  local p="$1"
  case "$p" in
    "$HOME") echo "~" ;;
    "$HOME"/*) echo "~/${p#"$HOME"/}" ;;
    *) echo "$p" ;;
  esac
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

_dot_doctor() {
  # Title banner via gum (falls back to plain bold if gum is missing).
  if command -v gum >/dev/null 2>&1; then
    gum style --bold --foreground 212 --border normal --padding '0 2' \
      --margin '0 0 1 0' 'dot doctor'
  else
    printf '\n%sdot doctor%s\n\n' "$_DR_BOLD" "$_DR_RESET"
  fi

  _dr_check_shell
  _dr_check_base_repo
  _dr_check_overlays
  _dr_check_tools
  _dr_check_git_hooks
  _dr_check_cron

  # Summary: coloured by worst status. Use gum for the box so the summary
  # reads as the conclusion rather than just another line.
  local summary_line summary_color
  summary_line=$(printf '%d passed · %d warnings · %d failed' \
    "$_DR_PASS_COUNT" "$_DR_WARN_COUNT" "$_DR_FAIL_COUNT")
  if [[ "$_DR_FAIL_COUNT" -gt 0 ]]; then
    summary_color=9 # red
  elif [[ "$_DR_WARN_COUNT" -gt 0 ]]; then
    summary_color=11 # yellow
  else
    summary_color=10 # green
  fi
  if command -v gum >/dev/null 2>&1; then
    echo
    gum style --bold --foreground "$summary_color" \
      --border rounded --padding '0 2' "$summary_line"
  else
    printf '\n─────────\n%s\n' "$summary_line"
  fi

  [[ "$_DR_FAIL_COUNT" -eq 0 ]]
}
