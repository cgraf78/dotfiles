# shellcheck shell=bash
# SSH helpers shared across interactive shells.

_shell_pick_remote_login_shell() {
  local shell_name=""

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    shell_name="zsh"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    shell_name="bash"
  elif [[ -n "${SHELL:-}" ]]; then
    shell_name="${SHELL##*/}"
  fi

  case "$shell_name" in
    bash | zsh | sh)
      printf '%s\n' "$shell_name"
      ;;
    *)
      printf '%s\n' "sh"
      ;;
  esac
}

# SSH bypassing tmux, preferring the current local shell on the remote side.
# This is a login helper: put SSH options before the host. It always appends
# its own remote shell command, so use ssh for commands and non-login modes.
# It requests a tty by default; pass -T to disable that request.
sshn() {
  local preferred shell_cmd

  if [[ $# -lt 1 ]]; then
    echo "usage: sshn [ssh options] <host>" >&2
    return 1
  fi

  preferred="$(_shell_pick_remote_login_shell)"
  shell_cmd="NO_TMUX=1 DS_SSHN_SHELL=$preferred /bin/sh -lc 'if command -v \"\$DS_SSHN_SHELL\" >/dev/null 2>&1; then exec \"\$DS_SSHN_SHELL\" -l; elif command -v zsh >/dev/null 2>&1; then exec zsh -l; elif command -v bash >/dev/null 2>&1; then exec bash -l; else exec sh -l; fi'"
  ssh -t "$@" "$shell_cmd"
}
