# shellcheck shell=bash
# Repo configuration and base-dotfiles remote normalization.
#
# These helpers are kept separate from pull/command code because they encode
# durable repo policy: every repo should have the same pull/filter settings,
# while the base bare repo also needs private SSH remotes and no fsmonitor over
# the whole home directory.

_repo_has_upstream() {
  "$@" rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1
}

_overlay_is_worktree() {
  local path="$1" checkout_root git_root
  [[ -d "$path" ]] && [[ -d "$path/.git" || -f "$path/.git" ]] || return 1
  checkout_root=$(cd -P -- "$path" 2>/dev/null && pwd -P) || return 1
  git_root=$(git -C "$path" rev-parse --show-toplevel 2>/dev/null) || return 1
  git_root=$(cd -P -- "$git_root" 2>/dev/null && pwd -P) || return 1
  [[ "$checkout_root" == "$git_root" ]]
}

# Resolve local relative URLs from HOME before both clone and validation. Git
# rewrites a relative source to a cwd-dependent absolute origin during clone;
# making the base explicit keeps later updates stable from every working
# directory. Colon-bearing SSH/scp URLs, schemes, absolute paths, and Windows
# drive paths keep their configured spelling.
_overlay_effective_url() {
  local url="$1"
  case "$url" in
    \~) REPLY="$HOME" ;;
    \~/*) REPLY="$HOME/${url#\~/}" ;;
    /* | [A-Za-z]:[\\/]* | *:*) REPLY="$url" ;;
    *) REPLY="$HOME/$url" ;;
  esac
}

# Compare the one authoritative origin URL with the configured spelling. REPLY
# contains the recorded URL, or a diagnostic placeholder when origin is absent
# or ambiguous.
_overlay_origin_matches() {
  local path="$1" expected="$2"
  local -a urls=()
  mapfile -t urls < <(git -C "$path" config --get-all remote.origin.url 2>/dev/null)

  case "${#urls[@]}" in
    0)
      REPLY="<missing>"
      return 1
      ;;
    1)
      REPLY="${urls[0]}"
      [[ "$REPLY" == "$expected" ]]
      ;;
    *)
      REPLY="<multiple origin URLs>"
      return 1
      ;;
  esac
}

_overlay_checkout_matches() {
  local path="$1" url="$2"
  _overlay_is_worktree "$path" || {
    REPLY="<not a Git worktree>"
    return 1
  }
  _overlay_effective_url "$url"
  local expected="$REPLY"
  _overlay_origin_matches "$path" "$expected"
}

# Ensure pull-behavior and filter config is set for all repos.
# Called by _dot_update_finalize so it runs in dot update, dot pull, and dotbootstrap.
_ensure_repo_config() {
  # Apply git config to a single repo. $1... is the git command prefix.
  # shellcheck disable=SC2086  # git_cmd is intentionally word-split.
  _apply_repo_config() {
    local git_cmd="$*" record key value
    local pull_seen=0 pull_ok=1 rebase_seen=0 rebase_ok=1
    local refresh_seen=0 refresh_ok=1 filter_seen=0 filter_ok=1
    local fsmonitor_seen=0 fsmonitor_ok=1

    while IFS= read -r -d '' record; do
      key="${record%%$'\n'*}"
      value="${record#*$'\n'}"
      case "$key" in
        pull.rebase)
          pull_seen=1
          [[ "$value" == true ]] || pull_ok=0
          ;;
        rebase.autostash)
          rebase_seen=1
          [[ "$value" == true ]] || rebase_ok=0
          ;;
        diff.autorefreshindex)
          refresh_seen=1
          [[ "$value" == true ]] || refresh_ok=0
          ;;
        filter.json-normalize.clean)
          filter_seen=1
          [[ "$value" == "jq --sort-keys ." ]] || filter_ok=0
          ;;
        core.fsmonitor)
          fsmonitor_seen=1
          [[ "$value" == false ]] || fsmonitor_ok=0
          ;;
      esac
    done < <(
      $git_cmd config --local --null --get-regexp \
        '^(pull\.rebase|rebase\.autostash|diff\.autorefreshindex|filter\.json-normalize\.clean|core\.fsmonitor)$' \
        2>/dev/null
    )

    [[ "$pull_seen" -eq 1 && "$pull_ok" -eq 1 ]] ||
      $git_cmd config pull.rebase true 2>/dev/null || true
    [[ "$rebase_seen" -eq 1 && "$rebase_ok" -eq 1 ]] ||
      $git_cmd config rebase.autoStash true 2>/dev/null || true
    [[ "$refresh_seen" -eq 1 && "$refresh_ok" -eq 1 ]] ||
      $git_cmd config diff.autoRefreshIndex true 2>/dev/null || true
    [[ "$filter_seen" -eq 1 && "$filter_ok" -eq 1 ]] ||
      $git_cmd config filter.json-normalize.clean "jq --sort-keys ." 2>/dev/null || true

    DOT_REPO_CONFIG_FSMONITOR_OK=0
    [[ "$fsmonitor_seen" -eq 1 && "$fsmonitor_ok" -eq 1 ]] &&
      DOT_REPO_CONFIG_FSMONITOR_OK=1
    return 0
  }
  # shellcheck disable=SC2086  # $GIT is intentionally word-split.
  if [[ -d "$DOTFILES" ]]; then
    _apply_repo_config $GIT
    # Bare repo uses $HOME as work-tree; fsmonitor would watch the entire
    # home directory, causing hangs. Disable it unconditionally.
    [[ "$DOT_REPO_CONFIG_FSMONITOR_OK" -eq 1 ]] ||
      $GIT config core.fsmonitor false 2>/dev/null || true
  fi
  local entry
  for entry in "${OVERLAYS[@]+"${OVERLAYS[@]}"}"; do
    local path url
    IFS='|' read -r _ path url _ <<<"$entry"
    if _overlay_checkout_matches "$path" "$url"; then
      _apply_repo_config git -C "$path"
    fi
  done
  unset -f _apply_repo_config
  unset DOT_REPO_CONFIG_FSMONITOR_OK
}

_dotfiles_repo_url() {
  printf '%s' 'git@github.com:cgraf78/dotfiles.git'
}

_prefer_base_dotfiles_ssh_remote() {
  local url="" push_url="" ssh_url record key value url_count=0 push_count=0
  ssh_url="$(_dotfiles_repo_url)"
  while IFS= read -r -d '' record; do
    key="${record%%$'\n'*}"
    value="${record#*$'\n'}"
    case "$key" in
      remote.origin.url)
        url="$value"
        url_count=$((url_count + 1))
        ;;
      remote.origin.pushurl)
        push_url="$value"
        push_count=$((push_count + 1))
        ;;
    esac
  done < <(
    # Inspect raw local values so url.*.insteadOf cannot make an already-correct
    # SSH remote appear to be the legacy HTTPS spelling.
    # shellcheck disable=SC2086  # $GIT is intentionally word-split.
    $GIT config --local --null --get-regexp \
      '^remote\.origin\.(url|pushurl)$' 2>/dev/null
  )
  # An ambiguous fetch URL is not a recognizable legacy install. Leave both
  # fetch and push routing untouched for explicit user repair.
  [[ "$url_count" -eq 1 ]] || return 0
  case "$url" in
    https://github.com/cgraf78/dotfiles | https://github.com/cgraf78/dotfiles.git)
      # The base repo used to be public, so older installs may still point at
      # the anonymous HTTPS URL. Rewrite only that known legacy remote before
      # pulling so private-repo auth goes through the user's GitHub SSH key.
      # shellcheck disable=SC2086  # $GIT is intentionally word-split.
      $GIT remote set-url origin "$ssh_url" 2>/dev/null || true
      ;;
    git@github.com:cgraf78/dotfiles.git)
      ;;
    *) return 0 ;;
  esac
  # Keep explicit push routing in sync with the read remote. This matters on
  # machines that still have a stale HTTPS pushUrl from the public-repo era.
  if [[ "$push_count" -ne 1 || "$push_url" != "$ssh_url" ]]; then
    # shellcheck disable=SC2086  # $GIT is intentionally word-split.
    $GIT remote set-url --push origin "$ssh_url" 2>/dev/null || true
  fi
}
