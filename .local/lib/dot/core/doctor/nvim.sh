# shellcheck shell=bash
# dot doctor: Nvim checks.

_dr_csv() {
  local IFS=,
  printf '%s' "$*"
}
_dr_lsp_policy_diff() {
  local enabled="$1" covered="$2"
  local missing=() stale=() server

  for server in $enabled; do
    case " $covered " in
      *" $server "*) ;;
      *) missing+=("$server") ;;
    esac
  done

  for server in $covered; do
    case " $enabled " in
      *" $server "*) ;;
      *) stale+=("$server") ;;
    esac
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    mapfile -t missing < <(printf '%s\n' "${missing[@]}" | sort)
  fi
  if [[ "${#stale[@]}" -gt 0 ]]; then
    mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
  fi

  printf 'missing=%s\n' "$(_dr_csv "${missing[@]+"${missing[@]}"}")"
  printf 'stale=%s\n' "$(_dr_csv "${stale[@]+"${stale[@]}"}")"
}
_dr_check_nvim_lsp_policy() {
  local query_file policy_out exit_code enabled covered drift missing stale

  query_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-lsp-policy.lua.XXXXXX") || {
    _dr_warn "nvim LSP fallback policy check failed" "could not create temp file"
    return 0
  }
  cat >"$query_file" <<'LUA'
local policy = require("config.mason-policy")
require("lazy").load({ plugins = { "nvim-lspconfig" } })

local opts = require("lazyvim.util").opts("nvim-lspconfig")
local enabled = {}
for server, server_opts in pairs(opts.servers or {}) do
  if server ~= "*" and type(server_opts) == "table" and server_opts.enabled ~= false then
    table.insert(enabled, server)
  end
end
table.sort(enabled)

local covered = {}
for server, _ in pairs(policy.lsp_server_packages()) do
  table.insert(covered, server)
end
table.sort(covered)

print("enabled=" .. table.concat(enabled, " "))
print("covered=" .. table.concat(covered, " "))
LUA

  # Set mason_disabled before init.lua loads. This lets LazyVim resolve enabled
  # LSP servers without allowing Mason to install packages during doctor.
  policy_out=$(nvim -i NONE --headless --cmd 'lua vim.g.mason_disabled = true' \
    +"luafile $query_file" +"qa!" 2>&1)
  exit_code=$?
  rm -f "$query_file"

  if [[ $exit_code -ne 0 ]]; then
    _dr_warn "nvim LSP fallback policy check failed" \
      "run 'nvim -i NONE --headless --cmd \"lua vim.g.mason_disabled = true\"' to debug"
    return 0
  fi

  enabled=$(printf '%s\n' "$policy_out" | awk -F= '/^enabled=/ {print $2; exit}')
  covered=$(printf '%s\n' "$policy_out" | awk -F= '/^covered=/ {print $2; exit}')
  drift=$(_dr_lsp_policy_diff "$enabled" "$covered")
  missing=$(printf '%s\n' "$drift" | awk -F= '/^missing=/ {print $2; exit}')
  stale=$(printf '%s\n' "$drift" | awk -F= '/^stale=/ {print $2; exit}')

  if [[ -z "$missing" && -z "$stale" ]]; then
    _dr_ok "nvim LSP fallback policy in sync"
  else
    local details=()
    [[ -n "$missing" ]] && details+=("missing fallback policy for enabled server(s): $missing")
    [[ -n "$stale" ]] && details+=("fallback policy for disabled server(s): $stale")
    _dr_warn "nvim LSP fallback policy drift" "$(_dr_csv "${details[@]}")"
  fi
}
_dr_nvim_health_error_counts() {
  local health_file="$1"

  awk '
    function ignore_error() {
      # Snacks still reports the image renderer dependency stack when the image
      # module is disabled. Those missing tools are useful in :checkhealth, but
      # dot doctor should not make a disabled optional feature look actionable.
      if (section == "snacks_image" && snacks_image_disabled) {
        return 1
      }

      # These two Snacks checks are false positives in headless doctor runs; a
      # real tmux Neovim TUI initializes both integrations successfully.
      if (section == "snacks_input" && /`vim\.ui\.input` is not set/) {
        return 1
      }
      if (section == "snacks_notifier" && /is not ready/) {
        return 1
      }

      return 0
    }

    /^Snacks\.image ~/ {
      section = "snacks_image"
      snacks_image_disabled = 0
      next
    }
    /^Snacks\.input ~/ {
      section = "snacks_input"
      next
    }
    /^Snacks\.notifier ~/ {
      section = "snacks_notifier"
      next
    }
    /^[^[:space:]].* ~$/ && !/^Snacks\.(image|input|notifier) ~/ {
      section = ""
      snacks_image_disabled = 0
    }
    section == "snacks_image" && /setup \{disabled\}/ {
      snacks_image_disabled = 1
      next
    }
    /ERROR/ {
      if (ignore_error()) {
        ignored++
      } else {
        actionable++
      }
    }
    END { printf "%d %d\n", actionable + 0, ignored + 0 }
  ' "$health_file"
}
_dr_check_nvim() {
  _dr_section "Neovim"

  if ! command -v nvim >/dev/null 2>&1; then
    _dr_skip "nvim not installed"
    return 0
  fi

  if ! nvim --version >/dev/null 2>&1; then
    _dr_warn "nvim found but cannot run" "binary may be incompatible with this platform"
    return 0
  fi

  local nvim_ver
  nvim_ver=$(nvim --version 2>/dev/null | head -1 | awk '{print $2}')
  _dr_ok "nvim installed" "$nvim_ver"

  local nvim_err exit_code
  # Doctor is diagnostic, not a bootstrap path. Force Mason off before init.lua
  # loads so devservers without npm/network access do not try editor-local
  # installs just because a health check ran.
  nvim_err=$(nvim -i NONE --headless --cmd 'lua vim.g.mason_disabled = true' -c 'qa!' 2>&1)
  exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    _dr_fail "nvim config failed to load" "run 'nvim --headless -c qa!' to debug"
    return 0
  fi

  local error_lines
  error_lines=$(printf '%s' "$nvim_err" | grep -ciE '^E[0-9]+:|^error' || true)
  if [[ "$error_lines" -gt 0 ]]; then
    _dr_warn "nvim startup had $error_lines error(s)" "run 'nvim --headless -c qa! 2>&1' to debug"
  else
    _dr_ok "nvim config loads cleanly"
  fi

  _dr_check_nvim_lsp_policy

  local health_file timeout_cmd=""
  health_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-health.XXXXXX") || {
    _dr_skip "checkhealth" "could not create temp file"
    return 0
  }

  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout 15"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout 15"
  fi

  if [[ -z "$timeout_cmd" ]]; then
    _dr_skip "checkhealth" "timeout command not available"
  elif $timeout_cmd nvim -i NONE --headless --cmd 'lua vim.g.mason_disabled = true' \
    +"checkhealth" +"w! $health_file" +"qa!" 2>/dev/null; then
    local health_errors ignored_health_errors health_counts
    health_counts=$(_dr_nvim_health_error_counts "$health_file" 2>/dev/null || true)
    read -r health_errors ignored_health_errors <<<"${health_counts:-0 0}"
    if [[ "$health_errors" -gt 0 ]]; then
      _dr_warn "checkhealth: $health_errors error(s)" "run ':checkhealth' in nvim to inspect"
    elif [[ "$ignored_health_errors" -gt 0 ]]; then
      _dr_ok "checkhealth passed" "ignored $ignored_health_errors non-actionable headless/disabled Snacks error(s)"
    else
      _dr_ok "checkhealth passed"
    fi
  else
    _dr_skip "checkhealth" "timed out after 15s"
  fi

  rm -f "$health_file"
}
