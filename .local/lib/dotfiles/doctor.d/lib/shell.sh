# shellcheck shell=bash
# dot doctor: Shell checks.
#
# shellcheck disable=SC2088  # tilde strings here are display text.

_dr_check_shell() {
  _dr_section "Shell environment"

  # bash 4+ (required by dot/shdeps — macOS system bash is 3.2)
  local bash_ver
  if ! bash_ver=$(BASH_ENV='' bash -c 'printf "%s.%s\n" "${BASH_VERSINFO[0]}" "${BASH_VERSINFO[1]}"' 2>/dev/null); then
    bash_ver=""
  fi
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
  local loader="$HOME/.local/lib/dotfiles/shell-loader.sh"
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

  # ~/.local/bin on PATH (all dot scripts live there)
  case ":$PATH:" in
    *:"$HOME/.local/bin":*) _dr_ok "~/.local/bin on PATH" ;;
    *) _dr_fail "~/.local/bin not on PATH" "dot, autoformat, autolint, agent hooks all live here" ;;
  esac

  # Shell config directories
  for dir in "$DOT_SHELL_ENV_DIR" "$DOT_SHELL_INTERACTIVE_DIR"; do
    local label="${dir#"$HOME"/.config/shell/}"
    if [[ -d "$dir" ]]; then
      _dr_ok "$label/ exists"
    else
      _dr_fail "$label/ missing" "shell config won't load — run dotbootstrap"
    fi
  done
}
