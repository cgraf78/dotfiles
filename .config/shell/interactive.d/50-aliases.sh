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
# Termnav's shell loader runs later in startup, before a user can invoke these
# functions. Keep only the consumer choice here: plain paths for terminals that
# need native linkification, semantic OSC-8 links for Termnav-capable routers.
# Translate the dotfiles-specific policy once into Termnav's reusable marker so
# a subsequently launched tmux client carries the same decision. Termnav stays
# independent of the private DOT_ namespace while attached panes retain the
# pre-extraction behavior.
if [[ "${DOT_VSCODE_TERMINAL:-}" == 1 ]]; then
  export TERMNAV_FILE_LINKS_PLAIN=1
fi

# If the dependency failed to load, fail safely to plain output rather than
# emitting links that no installed router can open.
_dot_file_links_need_plain_output() {
  typeset -f termnav_file_links_need_plain_output >/dev/null 2>&1 || return 0
  termnav_file_links_need_plain_output
}

if command -v eza >/dev/null 2>&1; then
  unalias ls ll la l lt llt 2>/dev/null || true
fi

if command -v eza >/dev/null 2>&1 && command -v termnav >/dev/null 2>&1; then
  _dot_eza() {
    if _dot_file_links_need_plain_output; then
      eza "$@"
    else
      termnav eza "$@"
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
    if _dot_file_links_need_plain_output; then
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
    if _dot_file_links_need_plain_output; then
      command rg --hyperlink-format=none "$@"
    else
      command rg "$@"
    fi
  }
fi

# Smart lazygit: the git launcher makes `$HOME` look like a real repo, but
# lazygit still needs explicit Git-directory and worktree args for that shape.
lg() {
  local git_dir
  git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null || true)
  if [[ "$git_dir" == "$HOME/.dotfiles" ]]; then
    lazygit --git-dir="$git_dir" --work-tree="$HOME" "$@"
  else
    lazygit "$@"
  fi
}

# Risk acceptance (single-user dev machine): the agent wrappers below run with
# interactive permission prompts DISABLED, so the agents act with full
# unsandboxed shell access. This is deliberate — command safety is enforced by
# the agentguard pre-bash/pre-edit hooks (destructive-command guards) rather than
# by per-action approval. Do NOT carry this default onto shared or multi-user
# hosts, where interactive approval should stay on.
#
# Flag placement differs per CLI. Claude and Codex accept their native yolo
# flags ahead of every invocation, so those wrappers prepend unconditionally.
# Muse and opencode accept theirs only on the commands that actually run an
# agent, so those wrappers route by invocation shape — see each note below.

# Claude - disable permission checks (see risk-acceptance note above).
claude() {
  command claude --dangerously-skip-permissions "$@"
}

# Codex - disable approval and sandboxing (see risk-acceptance note above).
codex() {
  command codex --dangerously-bypass-approvals-and-sandbox "$@"
}

# Muse - disable approval and sandboxing (see risk-acceptance note above).
#
# `--yolo` is a root option, but Muse rejects a subcommand that follows root
# options ("`skills` is a command, not a root option"), so it can only be
# prepended for the bare TUI/prompt form. `exec` and `resume` take it after the
# subcommand name; the remaining subcommands reject it outright. Keep the
# pass-through list in sync with `muse --help`: a stale entry can only make that
# one subcommand fail loudly, never send a listed one down the wrong path.
muse() {
  case "${1-}" in
    exec | resume)
      local muse_cmd="$1"
      shift
      command muse "$muse_cmd" --yolo "$@"
      ;;
    export | trace | skills | sandbox | session-message | auth | login | logout | init)
      command muse "$@"
      ;;
    *)
      command muse --yolo "$@"
      ;;
  esac
}

# opencode - auto-approve every permission that is not explicitly denied (see
# risk-acceptance note above).
#
# `--auto` is only accepted by the two commands that run tools: the default TUI
# and `run`. Every other subcommand (`models`, `providers`, `serve`, `pr`, ...)
# rejects it as an unknown option, and a leading `--auto` silently binds the
# subcommand name to the default command's `[project]` positional instead
# (`opencode --auto models` tries to open ./models). The default command's
# positional is a directory, so an existing path means TUI and any other bare
# word means subcommand — no subcommand list to keep in sync.
opencode() {
  if [[ "${1-}" == "run" ]]; then
    shift
    command opencode run --auto "$@"
  elif [[ $# -eq 0 || "${1-}" == -* || -d "${1-}" ]]; then
    # Default TUI: no args, leading flags, or a project directory.
    command opencode --auto "$@"
  else
    command opencode "$@"
  fi
}
