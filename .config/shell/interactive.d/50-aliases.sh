# shellcheck shell=bash
# Cross-platform aliases and helper detection.
# Platform-specific aliases live in 51-aliases-{macos,linux,wsl}.sh.

# ── Platform binary detection (shared across 51-* files and overlays) ─────

_fd_cmd=""
if command -v fd &>/dev/null; then
  _fd_cmd="fd"
elif command -v fdfind &>/dev/null; then
  _fd_cmd="fdfind"
fi

if [[ -n "$_fd_cmd" ]]; then
  export FZF_DEFAULT_COMMAND="$_fd_cmd --hidden --exclude .git ."
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="$_fd_cmd --hidden --exclude .git --type d ."
fi

_bat_cmd=""
if command -v bat &>/dev/null; then
  _bat_cmd="bat"
elif command -v batcat &>/dev/null; then
  _bat_cmd="batcat"
fi

# ── Tools ─────────────────────────────────────────────────────────────────

alias vs='code'
alias ca='cal -3'
alias vi='nvim'
alias c='bat --paging=never'
alias grep='grep --color=auto'
alias gl='git log --oneline --graph --decorate'
alias gll='git log --oneline --all --graph --decorate'
# shellcheck disable=SC2139  # intentional: expand $_fd_cmd at define time
[[ -n "$_fd_cmd" ]] && alias fd="$_fd_cmd -H"

# ls defaults: prefer eza (cross-platform); platform files set native fallbacks.
_dot_env_has_vscode_marker() {
  local env_text
  env_text=$'\n'"$1"$'\n'
  case "$env_text" in
    *$'\nTERM_PROGRAM=vscode\n'* | *$'\nVSCODE_IPC_HOOK_CLI='* | *$'\nDOT_VSCODE_TERMINAL=1\n'*)
      return 0
      ;;
  esac
  return 1
}

_dot_env_has_wsl_marker() {
  local env_text
  env_text=$'\n'"$1"$'\n'
  case "$env_text" in
    *$'\nWSL_DISTRO_NAME='* | *$'\nWSL_INTEROP='*)
      return 0
      ;;
  esac
  return 1
}

_dot_env_has_file_link_router() {
  local env_text
  env_text=$'\n'"$1"$'\n'
  case "$env_text" in
    *$'\nTERM_PROGRAM=WezTerm\n'* | *$'\nWEZTERM_PANE='*)
      return 0
      ;;
  esac
  return 1
}

_dot_env_needs_plain_file_links() {
  local env_text
  env_text="$1"

  _dot_env_has_file_link_router "$env_text" && return 1
  _dot_env_has_vscode_marker "$env_text" && return 0

  # Windows-to-WSL terminal launches do not reliably preserve VS Code's normal
  # TERM_PROGRAM/VSCODE_* markers. In an unmarked WSL terminal, file:// OSC-8
  # URLs point at Linux paths that the Windows-side terminal cannot generally
  # resolve as workspace files. Keep rich links only for clients that explicitly
  # identify as a router we control, such as WezTerm plus termnav.
  if _dot_env_has_wsl_marker "$env_text"; then
    return 0
  fi

  return 1
}

_dot_current_env_needs_plain_file_links() {
  local env_text
  env_text=$(
    [[ -n "${TERM_PROGRAM:-}" ]] && printf 'TERM_PROGRAM=%s\n' "$TERM_PROGRAM"
    [[ -n "${VSCODE_IPC_HOOK_CLI:-}" ]] && printf 'VSCODE_IPC_HOOK_CLI=%s\n' "$VSCODE_IPC_HOOK_CLI"
    [[ -n "${DOT_VSCODE_TERMINAL:-}" ]] && printf 'DOT_VSCODE_TERMINAL=%s\n' "$DOT_VSCODE_TERMINAL"
    [[ -n "${WEZTERM_PANE:-}" ]] && printf 'WEZTERM_PANE=%s\n' "$WEZTERM_PANE"
    [[ -n "${WSL_DISTRO_NAME:-}" ]] && printf 'WSL_DISTRO_NAME=%s\n' "$WSL_DISTRO_NAME"
    [[ -n "${WSL_INTEROP:-}" ]] && printf 'WSL_INTEROP=%s\n' "$WSL_INTEROP"
  )

  _dot_env_needs_plain_file_links "$env_text"
}

# OSC-8 links let eza attach the real path for listings like `ll dir`,
# avoiding terminal-side guesses from bare names such as README.md.
_dot_tmux_client_needs_plain_file_links() {
  [[ -n "${TMUX:-}" ]] || return 1

  local client_pid client_env proc_environ
  client_pid=$(tmux display-message -p '#{client_pid}' 2>/dev/null || true)
  [[ "$client_pid" =~ ^[0-9]+$ ]] || return 1
  proc_environ="${DOT_TEST_PROC_ROOT:-/proc}/$client_pid/environ"
  if [[ -r "$proc_environ" ]]; then
    client_env=$(tr '\0' '\n' <"$proc_environ" 2>/dev/null || true)
  else
    # macOS has no /proc, so inspect the attached tmux client process when we
    # can. This keeps tmux panes attached from VS Code on the VS Code path while
    # still avoiding stale pane env when the real client is WezTerm.
    client_env=$(ps eww -p "$client_pid" 2>/dev/null | tr ' ' '\n' || true)
  fi

  _dot_env_needs_plain_file_links "$client_env"
}

_dot_plain_file_link_terminal() {
  if [[ -n "${TMUX:-}" ]]; then
    _dot_tmux_client_needs_plain_file_links
    return
  fi

  _dot_current_env_needs_plain_file_links
}

_dot_vscode_file_link_terminal_uncached() {
  _dot_plain_file_link_terminal || return 1

  # VS Code owns file opening inside its integrated terminal. Unmarked WSL
  # terminals have the same practical constraint: Linux file:// OSC-8 links can
  # cross to the Windows side as non-workspace local URLs. Keep rich OSC-8 links
  # for WezTerm/tmux termnav, but otherwise let the terminal linkify plain
  # command output.
  return 0
}

_dot_vscode_file_link_terminal() {
  local now
  now="${SECONDS:-0}"

  # This function sits on hot interactive commands (`ls` and `rg`). Re-checking
  # once per shell second keeps tmux reattach behavior responsive while avoiding
  # a tmux IPC + /proc read for every command in tight loops.
  if [[ "${_dot_vscode_file_link_cache_second:-}" == "$now" &&
    -n "${_dot_vscode_file_link_cache_status+x}" ]]; then
    return "$_dot_vscode_file_link_cache_status"
  fi

  _dot_vscode_file_link_terminal_uncached
  _dot_vscode_file_link_cache_status=$?
  _dot_vscode_file_link_cache_second="$now"
  return "$_dot_vscode_file_link_cache_status"
}

if command -v eza >/dev/null 2>&1; then
  unalias ls ll la l lt llt 2>/dev/null || true
fi

if command -v eza >/dev/null 2>&1 && command -v eza-nvim-links >/dev/null 2>&1; then
  _dot_eza() {
    if _dot_vscode_file_link_terminal; then
      eza "$@"
    else
      eza-nvim-links "$@"
    fi
  }

  function ls { _dot_eza --group-directories-first "$@"; }
  function ll { _dot_eza -alF --group-directories-first "$@"; }
  function la { _dot_eza -a --group-directories-first "$@"; }
  function l { _dot_eza -F --group-directories-first "$@"; }
  function lt { _dot_eza --tree --level=2 "$@"; }
  function llt { _dot_eza --tree -al --level=2 "$@"; }
elif command -v eza >/dev/null 2>&1; then
  _dot_eza() {
    if _dot_vscode_file_link_terminal; then
      eza "$@"
    else
      eza --hyperlink "$@"
    fi
  }

  function ls { _dot_eza --group-directories-first "$@"; }
  function ll { _dot_eza -alF --group-directories-first "$@"; }
  function la { _dot_eza -a --group-directories-first "$@"; }
  function l { _dot_eza -F --group-directories-first "$@"; }
  function lt { _dot_eza --tree --level=2 "$@"; }
  function llt { _dot_eza --tree -al --level=2 "$@"; }
else
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
fi

if command -v rg >/dev/null 2>&1; then
  unalias rg 2>/dev/null || true

  function rg {
    if _dot_vscode_file_link_terminal; then
      command rg --hyperlink-format=none "$@"
    else
      command rg "$@"
    fi
  }
fi

# Smart lazygit: the git launcher makes `$HOME` look like a real repo, but
# lazygit still needs explicit bare-repo args for that shape.
lg() {
  local git_dir
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  if [[ "$git_dir" == "$HOME/.dotfiles" ]]; then
    lazygit --git-dir="$git_dir" --work-tree="$HOME" "$@"
  else
    lazygit "$@"
  fi
}

# Risk acceptance (single-user dev machine): the Claude and Codex wrappers below
# run with interactive permission prompts DISABLED, so the agents act with full
# unsandboxed shell access. This is deliberate — command safety is enforced by
# the agentguard pre-bash/pre-edit hooks (destructive-command guards) rather than
# by per-action approval. Do NOT carry this default onto shared or multi-user
# hosts, where interactive approval should stay on.

# Claude - disable permission checks (see risk-acceptance note above).
claude() {
  command claude --dangerously-skip-permissions "$@"
}

# Codex - disable permission checks (see risk-acceptance note above).
_codex_allow_all() {
  command codex --profile allow_all --ask-for-approval never "$@"
}

codex() {
  _codex_allow_all "$@"
}
