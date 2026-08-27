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

alias ca='cal -3'
alias c='bat --paging=never'
alias grep='grep --color=auto'
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
