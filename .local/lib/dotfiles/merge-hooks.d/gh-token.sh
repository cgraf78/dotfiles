# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# Credential-file lifecycle is independent of development tools and gh
# preferences. Only read local files: calling `gh auth token` can activate a
# keyring even without a prompt, so missing files or YAML tooling simply skip
# seeding. Shell startup never needs either gh or yq.

_gh_token_from_hosts() {
  local yq_bin="$1" hosts="$HOME/.config/gh/hosts.yml" token
  [[ -n "$yq_bin" && -f "$hosts" ]] || return 1

  token=$(
    "$yq_bin" eval \
      '[(."github.com".oauth_token // ""), (.["github.com"].users[]?.oauth_token // "")] | map(select(. != "" and . != "null")) | .[0] // ""' \
      "$hosts" 2>/dev/null
  ) || return 1
  [[ -n "$token" ]] || return 1
  printf '%s\n' "$token"
}

_gh_write_token_file() {
  local token="$1" dst="$HOME/.config/gh/github-pat" dir tmp
  [[ -n "$token" ]] || return 1
  dir=$(dirname "$dst")
  mkdir -p "$dir" || return 1
  tmp=$(mktemp "$dir/.github-pat.XXXXXX") || return 1
  chmod 600 "$tmp" 2>/dev/null || {
    rm -f "$tmp"
    return 1
  }
  printf '%s\n' "$token" >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  mv -f "$tmp" "$dst" || {
    rm -f "$tmp"
    return 1
  }
}

_gh_seed_token_file() {
  local yq_bin="$1" dst="$HOME/.config/gh/github-pat" token=""
  if [[ -f "$dst" ]]; then
    chmod 600 "$dst" 2>/dev/null || true
    return 0
  fi

  token=$(_gh_token_from_hosts "$yq_bin" || true)
  [[ -n "$token" ]] || return 0
  _gh_write_token_file "$token" || true
}

merge() {
  _dot_tool_present gh-token || return 0
  local yq_bin=""
  # Existing files need only permission repair. A missing optional parser
  # leaves a missing token file untouched and never activates a keyring.
  if [[ ! -f "$HOME/.config/gh/github-pat" ]]; then
    yq_bin=$(_merge_hook_mikefarah_yq) || yq_bin=""
  fi
  _gh_seed_token_file "$yq_bin"
}
