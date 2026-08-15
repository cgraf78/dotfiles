# shellcheck shell=bash
# dot doctor: Tools checks.

_dr_shdeps_link_issue() {
  local level="$1" label="$2" detail="${3:-}"

  if [[ "$level" == "fail" ]]; then
    _dr_fail "$label" "$detail"
  else
    _dr_warn "$label" "$detail"
  fi
}

_dr_check_shdeps_bin_group() {
  local level="$1" dependency="$2"

  local rows
  if ! rows=$(SHDEPS_CONF_DIR="$(_dot_shdeps_conf_dir)" \
    command shdeps dep-links "cgraf78/$dependency" 2>/dev/null); then
    _dr_shdeps_link_issue "$level" "$dependency bin links unchecked" \
      "shdeps cannot resolve command links for cgraf78/$dependency"
    return 0
  fi

  if [[ -z "$rows" ]]; then
    _dr_shdeps_link_issue "$level" "$dependency bin links missing" \
      "shdeps reported no public command links for cgraf78/$dependency"
    return 0
  fi

  local cmd link expected extra actual
  local issue_count=0 command_count=0

  # shdeps owns the vocabulary of commands and expected targets. Dot doctor
  # only verifies that the live public command path still matches that contract.
  while IFS=$'\t' read -r cmd link expected extra || [[ -n "$cmd$link$expected$extra" ]]; do
    if [[ -z "$cmd" || -z "$link" || -z "$expected" || -n "$extra" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$dependency bin links malformed" \
        "unexpected shdeps dep-links row for cgraf78/$dependency"
      continue
    fi

    ((command_count++)) || true

    if [[ ! -e "$link" && ! -L "$link" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$cmd not linked" \
        "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected")"
      continue
    fi

    if [[ "$link" != "$expected" ]]; then
      if [[ ! -L "$link" ]]; then
        ((issue_count++)) || true
        _dr_shdeps_link_issue "$level" "$cmd not linked" \
          "expected $(_dr_tilde "$link") -> $(_dr_tilde "$expected")"
        continue
      fi

      if ! _dr_symlink_points_to "$link" "$expected"; then
        ((issue_count++)) || true
        actual=$(_dr_symlink_target_path "$link" 2>/dev/null || echo "?")
        _dr_shdeps_link_issue "$level" "$cmd link target drift" \
          "got $(_dr_tilde "$actual"), expected $(_dr_tilde "$expected")"
        continue
      fi
    fi

    if [[ ! -x "$link" ]]; then
      ((issue_count++)) || true
      _dr_shdeps_link_issue "$level" "$cmd not executable" "$(_dr_tilde "$link")"
    fi
  done <<<"$rows"

  if [[ "$issue_count" -eq 0 ]]; then
    _dr_ok "$dependency bin links" "$command_count command(s)"
  fi
}
_dr_check_shdeps_shell_asset() {
  local dependency="$1"
  local asset="share/$dependency/shell.sh"
  local path

  if ! path=$(SHDEPS_CONF_DIR="$(_dot_shdeps_conf_dir)" \
    command shdeps dep-file "cgraf78/$dependency" "$asset" 2>/dev/null); then
    _dr_warn "$dependency shell asset unresolved" \
      "expected shdeps asset cgraf78/$dependency:$asset"
    return 0
  fi

  if [[ -r "$path" ]]; then
    _dr_ok "$dependency shell asset" "$(_dr_tilde "$path")"
  else
    _dr_warn "$dependency shell asset unreadable" "$(_dr_tilde "$path")"
  fi
}
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

  # curl — used by shdeps bootstrap and github:release installs
  if command -v curl >/dev/null 2>&1; then
    _dr_ok "curl" "$(curl --version 2>/dev/null | awk 'NR==1 {print $2; exit}')"
  else
    _dr_warn "curl missing" "needed to bootstrap shdeps and install github:release deps"
  fi

  # shdeps — dependency system used by dot update
  if command -v shdeps >/dev/null 2>&1; then
    _dr_ok "shdeps" "$(shdeps version 2>/dev/null | awk '{print $2; exit}' || echo '?')"
  elif [[ -f "$HOME/.local/share/shdeps/shdeps.sh" ]]; then
    _dr_ok "shdeps" "library installed"
  else
    _dr_warn "shdeps not installed" "run 'dot update' to bootstrap"
  fi

  # shdeps config
  local shdeps_conf_dir
  shdeps_conf_dir="$(_dot_shdeps_conf_dir)"
  if [[ -d "$shdeps_conf_dir" ]]; then
    local conf_count
    conf_count=$(find "$shdeps_conf_dir" -maxdepth 1 -name '*.conf' -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$conf_count" -gt 0 ]]; then
      _dr_ok "shdeps config" "$conf_count .conf file(s)"
    else
      _dr_warn "shdeps config dir exists but no .conf files" "$(_dr_tilde "$shdeps_conf_dir")"
    fi
  else
    _dr_warn "shdeps config dir missing" "$(_dr_tilde "$shdeps_conf_dir")"
  fi

  if _dr_python_has_schema_deps; then
    _dr_ok "schema validation deps" "python jsonschema + PyYAML"
  elif command -v uv >/dev/null 2>&1; then
    _dr_ok "schema validation deps" "uv bootstrap available"
  else
    _dr_warn "schema validation deps unavailable" \
      "install jsonschema/PyYAML or uv for schema-lint.py"
  fi

  # Core developer workflow front doors. These are live installation checks,
  # not shdeps behavior tests: shdeps owns the generic bin-link mechanics, and
  # doctor verifies the installed dotfiles environment still points at the
  # intended dependency repos.
  if command -v shdeps >/dev/null 2>&1; then
    _dr_check_shdeps_bin_group fail sley
    _dr_check_shdeps_bin_group warn checkrun
    _dr_check_shdeps_bin_group warn termnav
    _dr_check_shdeps_bin_group warn cmdblocks
    _dr_check_shdeps_bin_group warn git-tools
    _dr_check_shdeps_bin_group warn tmux-tools
    _dr_check_shdeps_bin_group warn ds
    _dr_check_shdeps_bin_group fail agentguard
    local _shdeps_shell_dep
    for _shdeps_shell_dep in sley checkrun termnav cmdblocks agentguard; do
      _dr_check_shdeps_shell_asset "$_shdeps_shell_dep"
    done
  else
    _dr_warn "dependency command links unchecked" "shdeps is not on PATH"
  fi

  # direnv — if any tracked .envrc suggests it's expected
  # shellcheck disable=SC2016  # intentional literal; we're searching for this string
  if grep -q 'eval "\$(direnv hook' "$DOT_SHELL_INTERACTIVE_DIR/"*.bash "$DOT_SHELL_INTERACTIVE_DIR/"*.zsh 2>/dev/null; then
    if command -v direnv >/dev/null 2>&1; then
      _dr_ok "direnv" "$(direnv version 2>/dev/null)"
    else
      _dr_warn "direnv hook configured but binary missing" "run 'dot update' to install"
    fi
  fi
}

_dr_python_has_schema_deps() {
  python3 - <<'PY' >/dev/null 2>&1
import jsonschema
import yaml
PY
}
