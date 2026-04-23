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
alias dl='dot git log --oneline --graph --decorate'
alias dll='dot git log --oneline --all --graph --decorate'
alias fzf='fzf --bind=ctrl-n:down,ctrl-p:up,ctrl-d:half-page-down,ctrl-u:half-page-up,alt-j:down,alt-k:up'
# shellcheck disable=SC2139  # intentional: expand $_fd_cmd at define time
[[ -n "$_fd_cmd" ]] && alias fd="$_fd_cmd -H"

# ls defaults: prefer eza (cross-platform); platform files set native fallbacks.
if command -v eza >/dev/null 2>&1; then
  alias ls='eza --group-directories-first'
  alias ll='eza -alF --group-directories-first'
  alias la='eza -a --group-directories-first'
  alias l='eza -F --group-directories-first'
  alias lt='eza --tree --level=2'
  alias llt='eza --tree -al --level=2'
else
  alias ll='ls -alF'
  alias la='ls -A'
  alias l='ls -CF'
fi

# Smart lazygit: detects bare dotfiles repo at $HOME, otherwise normal.
lg() {
  if ! git rev-parse --git-dir &>/dev/null && [[ -d "$HOME/.dotfiles" ]]; then
    lazygit --git-dir="$HOME/.dotfiles" --work-tree="$HOME"
  else
    lazygit "$@"
  fi
}

# OpenClaw TUI — launch a conversation with the main agent.
# Usage: argus [session-name]   (default: tui)
argus() {
  local sess="${1:-tui}"
  openclaw tui --session "agent:main:${sess}"
}

# ── SSH / tunnels ─────────────────────────────────────────────────────────

alias rdptun.bevo2='autossh -M0 -N -L 9000:bevo2.lan:3389 nas'
alias vnctun.metro='autossh -M0 -N -L 9001:metro.web:5901 nas'
