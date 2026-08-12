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

_tool_init sley _tool_shdeps_source_emit cgraf78/sley share/sley/shell.sh
# The 57-git-tools adapter defines consumer hooks first; loading the provider
# here keeps dependency resolution and caching out of the shell-neutral layer.
_tool_init git-tools _tool_shdeps_source_emit \
  cgraf78/git-tools share/git-tools/shell.sh

# fzf --bash emits malformed `complete` commands on some Linux hosts; strip
# the completion section, keeping only key bindings.
# shellcheck disable=SC2329,SC2317  # called indirectly via _tool_init "$@"
_fzf_bash_init() { fzf --bash 2>/dev/null | sed '/^### completion\.bash ###$/,$d'; }
_tool_init fzf _fzf_bash_init
unset -f _fzf_bash_init

_tool_init ds ds init bash
_tool_init zoxide zoxide init bash

if [[ -f ~/.bash-preexec.sh ]]; then
  if [[ "$_UNAME" != "Linux" || -n "$TMUX" ]]; then
    # shellcheck disable=SC1090  # symlinked/generated local file path
    source ~/.bash-preexec.sh
  fi
fi

# Guard: atuin's bash init registers hooks via precmd/preexec_functions+=
# which accumulates duplicates on re-source. reloadsh unsets this guard.
if [[ -z "${__atuin_sourced:-}" ]]; then
  _tool_init atuin atuin init bash --disable-up-arrow
  __atuin_sourced=1
fi

_tool_init direnv direnv hook bash
