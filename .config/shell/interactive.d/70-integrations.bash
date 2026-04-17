# shellcheck shell=bash
# Interactive tool integrations: shell extensions, completions, functions.

# ── History & shell options (before tools — atuin reads HISTFILE at init) ─

HISTSIZE=130000
HISTFILESIZE=-1
HISTTIMEFORMAT="%d/%m/%y %T "
HISTCONTROL=ignoreboth
shopt -s histappend
shopt -s checkwinsize

# ── Platform ──────────────────────────────────────────────────────────────

if [[ "$_UNAME" == "Darwin" ]]; then
  if [[ -z "${NVIM:-}" ]]; then
    # shellcheck disable=SC1091  # optional local integration script
    test -e "${HOME}/.iterm2_shell_integration.bash" && . "${HOME}/.iterm2_shell_integration.bash"
    # shellcheck disable=SC1091  # optional local app integration script
    # Guard: wezterm.sh appends duplicate hooks on every re-source.
    if [[ -z "${__wezterm_sourced:-}" ]]; then
      test -e "/Applications/WezTerm.app/Contents/Resources/wezterm.sh" && . "/Applications/WezTerm.app/Contents/Resources/wezterm.sh"
      __wezterm_sourced=1
    fi
  fi
fi

# ── Tool integrations (after history) ─────────────────────────────────────
# On some Linux hosts, `fzf --bash` emits malformed `complete` commands when it
# tries to wrap distro-provided bash-completion specs. Keep the key bindings,
# but skip the completion section to avoid login-time warnings.

# Load bash-completion when present so shdeps-linked user completions under
# ~/.local/share/bash-completion/completions are active in bash too.
if ! shopt -oq posix; then
  export BASH_COMPLETION_USER_DIR="$HOME/.local/share/bash-completion"

  if [[ -f /opt/homebrew/etc/profile.d/bash_completion.sh ]]; then
    # shellcheck disable=SC1091  # optional package-managed script
    source /opt/homebrew/etc/profile.d/bash_completion.sh
  elif [[ -f /usr/local/etc/profile.d/bash_completion.sh ]]; then
    # shellcheck disable=SC1091  # optional package-managed script
    source /usr/local/etc/profile.d/bash_completion.sh
  elif [[ -f /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck disable=SC1091  # optional distro script
    source /usr/share/bash-completion/bash_completion
  fi
fi

if command -v fzf &>/dev/null; then
  eval "$(
    fzf --bash 2>/dev/null | sed '/^### completion\.bash ###$/,$d'
  )"
fi
if command -v ds &>/dev/null; then
  eval "$(ds init bash)"
fi
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
fi
if [[ -f ~/.bash-preexec.sh ]]; then
  if [[ "$_UNAME" != "Linux" || -n "$TMUX" ]]; then
    # shellcheck disable=SC1090  # symlinked/generated local file path
    source ~/.bash-preexec.sh
  fi
fi
# Guard: atuin's bash init uses raw precmd/preexec_functions+=
# which accumulates duplicates on re-source.
if command -v atuin &>/dev/null && [[ -z "${__atuin_sourced:-}" ]]; then
  eval "$(atuin init bash --disable-up-arrow)"
  __atuin_sourced=1
fi
if command -v direnv &>/dev/null; then
  eval "$(direnv hook bash)"
fi
