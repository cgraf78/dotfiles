# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Merge GitHub CLI preferences from dotfiles into the local gh config.
# Runs during standalone Dot client convergence.
# Requires yq.
#
# Policy: dotfiles keys overwrite matching local keys.
# Local-only keys are preserved.

if ! declare -F dot_xdg_path >/dev/null 2>&1; then
  _dot_gh_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../xdg.sh disable=SC1091
  . "$_dot_gh_hook_dir/../xdg.sh"
fi

_gh_config_sources() {
  _gh_sources=()

  local source
  while IFS= read -r source; do
    _gh_sources+=("$source")
  done < <(dot_hook_family_files_matching gh/config.d '*.yml' '*.yaml' '*.replace/*.yml' '*.replace/*.yaml')
}

_gh_merge_layer() {
  local yq_bin="$1" dst="$2" src="$3" merged

  # Merge: source keys overwrite destination, local-only keys preserved
  merged=$("$yq_bin" eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "$dst" "$src") || {
    dot_hook_warn "    warning: GitHub CLI merge failed for $src — skipping"
    return 0
  }

  dot_write_text_if_changed "$dst" "$merged"
}

_gh_token_from_hosts() {
  local yq_bin="$1" hosts="$HOME/.config/gh/hosts.yml" token
  [[ -f "$hosts" ]] || return 1

  token=$(
    "$yq_bin" eval \
      '[(."github.com".oauth_token // ""), (.["github.com"].users[]?.oauth_token // "")] | map(select(. != "" and . != "null")) | .[0] // ""' \
      "$hosts" 2>/dev/null
  ) || return 1
  [[ -n "$token" ]] || return 1
  printf '%s\n' "$token"
}

_gh_token_seed_failure_stamp_path() {
  dot_xdg_path state "dot/gh-token-seed-failed.stamp"
}

_gh_token_seed_file_mtime() {
  stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0\n'
}

_gh_token_seed_failed_recently() {
  local stamp ttl now mtime
  [[ "${DOT_QUIET:-0}" -eq 1 || "${SHDEPS_QUIET:-0}" == 1 ]] || return 1
  _gh_token_seed_failure_stamp_path || return 1
  stamp="$REPLY"
  [[ -f "$stamp" ]] || return 1
  ttl="${DOT_GH_TOKEN_SEED_RETRY_SECONDS:-86400}"
  case "$ttl" in
    '' | *[!0-9]*) ttl=86400 ;;
  esac
  [[ "$ttl" -gt 0 ]] || return 1
  now=$(date +%s 2>/dev/null || printf '0\n')
  mtime=$(_gh_token_seed_file_mtime "$stamp")
  [[ "$now" -gt 0 && "$mtime" -gt 0 ]] || return 1
  ((now - mtime < ttl))
}

_gh_token_seed_mark_failed() {
  local stamp
  _gh_token_seed_failure_stamp_path || return 0
  stamp="$REPLY"
  mkdir -p "$(dirname "$stamp")"
  : >"$stamp" 2>/dev/null || true
}

_gh_token_seed_clear_failed() {
  local stamp
  _gh_token_seed_failure_stamp_path || return 0
  stamp="$REPLY"
  rm -f "$stamp" 2>/dev/null || true
}

_gh_token_from_cli() {
  local output token timeout_seconds
  command -v gh >/dev/null 2>&1 || return 1
  _gh_token_seed_failed_recently && return 1

  timeout_seconds="${DOT_GH_TOKEN_SEED_TIMEOUT_SECONDS:-5}"
  case "$timeout_seconds" in
    '' | *[!0-9]*) timeout_seconds=5 ;;
  esac

  if command -v timeout >/dev/null 2>&1; then
    output=$(timeout "${timeout_seconds}s" gh auth token 2>/dev/null) || {
      _gh_token_seed_mark_failed
      return 1
    }
  elif command -v gtimeout >/dev/null 2>&1; then
    output=$(gtimeout "${timeout_seconds}s" gh auth token 2>/dev/null) || {
      _gh_token_seed_mark_failed
      return 1
    }
  else
    output=$(gh auth token 2>/dev/null) || {
      _gh_token_seed_mark_failed
      return 1
    }
  fi

  IFS=$'\n' read -r token <<<"$output"
  [[ -n "$token" ]] || {
    _gh_token_seed_mark_failed
    return 1
  }
  _gh_token_seed_clear_failed
  printf '%s\n' "$token"
}

_gh_write_token_file() {
  local token="$1" dst="$HOME/.config/gh/github-pat" dir tmp
  [[ -n "$token" ]] || return 1
  dir=$(dirname "$dst")
  mkdir -p "$dir"
  tmp=$(mktemp "$dir/.github-pat.XXXXXX") || return 1
  chmod 600 "$tmp" 2>/dev/null || true
  printf '%s\n' "$token" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$dst"
  chmod 600 "$dst" 2>/dev/null || true
}

_gh_seed_token_file() {
  local yq_bin="$1" dst="$HOME/.config/gh/github-pat" token=""
  if [[ -f "$dst" ]]; then
    chmod 600 "$dst" 2>/dev/null || true
    return 0
  fi

  token=$(_gh_token_from_hosts "$yq_bin" || true)
  if [[ -z "$token" ]]; then
    token=$(_gh_token_from_cli || true)
  fi
  [[ -n "$token" ]] || return 0
  _gh_write_token_file "$token" || true
}

merge() {
  _dot_tool_present gh || return 0
  local dst="$HOME/.config/gh/config.yml"
  local yq_bin=""
  local -a _gh_sources

  _gh_config_sources
  yq_bin=$(_merge_hook_mikefarah_yq) || return 0
  _gh_seed_token_file "$yq_bin"

  ((${#_gh_sources[@]} > 0)) || return 0

  local src
  dot_hook_log "  GitHub CLI"
  mkdir -p "$(dirname "$dst")"
  if [[ ! -f "$dst" ]]; then
    cp "${_gh_sources[0]}" "$dst"
    _gh_sources=("${_gh_sources[@]:1}")
  fi

  for src in "${_gh_sources[@]}"; do
    _gh_merge_layer "$yq_bin" "$dst" "$src"
  done
}
