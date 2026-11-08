# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source merge-hooks.d/lib/cron-list.sh || return

# shellcheck shell=bash
# Install cron entries from tracked source layers and cron.local into the user
# crontab. Ordered `cron/cron.d` fragments let base dotfiles and overlays add
# jobs without patching a central file; immediate *.replace groups can express
# mutually-exclusive cron policy when a later overlay must replace an earlier
# choice. `cron.local` remains the last, untracked escape hatch.
# Replaces all dot-managed entries (between marker lines) on each run.
# Expands $HOME in cron lines. Sets PATH as a standalone cron variable
# so tools like git, curl, jq are found in cron's minimal environment, and
# SHELL plus BASH_ENV so jobs load env.d like other non-interactive shells.
# Idempotent — skips if the installed block already matches.

# Build a clean PATH for cron from declarative path fragments.
#
# Allowlist-only: read the dirs cron actually needs rather than inherit an
# arbitrary PATH. This is immune to PATH pollution from version managers (mise,
# pyenv, nvm, etc.) that inject per-tool install dirs and can push the generated
# `PATH=...` line past Debian cron's 998-char limit — truncation silently drops
# trailing system dirs (e.g. /usr/bin) and breaks `#!/usr/bin/env bash` lookup
# for cron-invoked scripts.
#
# Dirs that don't exist on the current host are skipped. Ordered `path.d`
# fragments own the order and can use `.replace` groups for environment-specific
# PATH policy.
_cron_path() {
  local result="" source line dir
  while IFS= read -r source; do
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*$ ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue

      dir="$(dot_expand_home "$line")"
      [[ "$dir" != "/" ]] && dir="${dir%/}"
      [[ -n "$dir" ]] || continue

      [[ -d "$dir" ]] || continue
      [[ ":$result:" == *":$dir:"* ]] && continue
      result="${result:+$result:}$dir"
    done <"$source"
  done < <(dot_hook_family_files_matching \
    cron/path.d \
    '*.txt' '*.replace/*.txt' \
    '*.pathlist' '*.replace/*.pathlist')

  if [[ -z "$result" ]]; then
    return 0
  fi

  # Guard against silent truncation by Debian cron (998-char line limit on
  # `PATH=...`). Leave headroom for the `PATH=` prefix and future growth.
  local max=900
  if ((${#result} > max)); then
    dot_hook_warn "  warning: cron PATH is ${#result} chars (>$max) — crond may truncate"
  fi

  echo "$result"
}

# Emit the crontab variable lines that make cron jobs load env.d the way
# agent and script shells do: bash as the job shell, with BASH_ENV pointing at
# the shared non-interactive loader.
#
# Cron otherwise runs every job with a bare /bin/sh environment (dash on Debian,
# bash in sh mode elsewhere) that never loads env.d, so jobs miss dotfiles
# values such as GH_TOKEN; Shdeps then makes anonymous GitHub API calls that
# share one 60-per-hour quota across every host behind the same public IP.
# Crontab variable lines are literal (no expansion), so both values are
# resolved to absolute paths here. The job shell only has to source BASH_ENV,
# so prefer the system bash (Termux keeps it under $PREFIX): a Homebrew, mise,
# or Shdeps bash earlier on PATH could later be removed, and a missing SHELL
# fails every job, including the `dot update` that would repair the crontab.
# Fall back to a PATH lookup only when no system bash exists. When bash or the
# loader is missing, emit nothing and leave cron on its default shell rather
# than break every job.
#
# Args: $1 cron PATH (may be empty)
_cron_shell_env() {
  local cron_path="$1" bash_bin="" candidate
  local loader="$HOME/.config/shell/env-noninteractive.sh"
  [[ -r "$loader" ]] || return 0
  for candidate in /bin/bash /usr/bin/bash ${PREFIX:+"$PREFIX/bin/bash"}; do
    if [[ -x "$candidate" ]]; then
      bash_bin=$candidate
      break
    fi
  done
  if [[ -z "$bash_bin" ]]; then
    bash_bin=$(PATH="${cron_path:+$cron_path:}$PATH" command -v bash) || return 0
  fi
  [[ "$bash_bin" == /* ]] || return 0
  printf 'SHELL=%s\nBASH_ENV=%s\n' "$bash_bin" "$loader"
}

# Parse a `# filter:` directive line into the active cron filter state.
# Resets each key to empty (match-all) first.
# Syntax: # filter: hosts=a,b platforms=linux users=chris   or   # filter: *
_cron_parse_filter() {
  local spec="$1"
  _cron_filter_hosts=""
  _cron_filter_platforms=""
  _cron_filter_users=""

  if [[ "$spec" == "*" ]]; then return 0; fi

  local token
  for token in $spec; do
    case "$token" in
      hosts=*) _cron_filter_hosts="${token#hosts=}" ;;
      platforms=*) _cron_filter_platforms="${token#platforms=}" ;;
      users=*) _cron_filter_users="${token#users=}" ;;
      *) dot_hook_warn "  warning: unknown filter key: $token" ;;
    esac
  done
}

# Check whether a comma-separated include/exclude list matches a value.
# Empty specs match everything. Mixed specs apply exclusions first.
_cron_value_match() {
  local spec="${1:-}" current="${2:-}"
  [[ -z "$spec" ]] && return 0

  local item has_include=0 has_exclude=0
  local IFS=','
  for item in $spec; do
    if [[ "$item" == !* ]]; then has_exclude=1; else has_include=1; fi
  done

  if [[ $has_exclude -eq 1 ]]; then
    for item in $spec; do
      [[ "$item" == "!$current" ]] && return 1
    done
  fi

  if [[ $has_include -eq 1 ]]; then
    for item in $spec; do
      [[ "$item" == "$current" ]] && return 0
    done
    return 1
  fi

  return 0
}

_cron_user_match() {
  local spec="${1:-}"
  [[ -z "$spec" ]] && return 0

  local current
  current=$(id -un 2>/dev/null || printf '%s' "${USER:-${LOGNAME:-}}")
  _cron_value_match "$spec" "$current"
}

# Check if current host/platform/user passes the active cron filter. The
# standalone hook API owns host/platform identity; dependency-provider loading
# must not determine whether client cron policy is filtered.
_cron_filter_match() {
  dot_hook_platform_match "$_cron_filter_platforms" || return 1
  dot_hook_host_match "$_cron_filter_hosts" || return 1
  _cron_user_match "$_cron_filter_users" || return 1
  return 0
}

# Parse a cron file: expand $HOME in entries, preserve comments.
# Supports `# filter:` directives for host/platform/user filtering.
# Filter directives are consumed (not passed through to crontab).
# Appends processed lines to $_cron_parsed (caller must initialize).
_cron_parse_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  _cron_filter_hosts=""
  _cron_filter_platforms=""
  _cron_filter_users=""

  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*filter:[[:space:]]*(.*) ]]; then
      _cron_parse_filter "${BASH_REMATCH[1]}"
      continue
    fi

    _cron_filter_match || continue
    # Editor metadata is stripped by the managed-block builder. Discard it
    # here too so it cannot create a source label for an otherwise empty stanza.
    [[ $line =~ ^#[[:space:]]*(vim:|-\*-) ]] && continue

    line="${line//\$HOME/$HOME}"
    if [[ -n "$_cron_parsed" ]]; then
      _cron_parsed="$_cron_parsed"$'\n'"$line"
    else
      _cron_parsed="$line"
    fi
  done <"$file"
}

# Discover cron source layers in merge order.
#
# The generic family helper owns ordered tracked fragments and `.replace`
# mutual-exclusion. `cron.local` is intentionally outside that family because it
# is untracked machine state: it should always run after tracked policy without
# requiring a private overlay or a committed fragment.
#
# Args: none
#
# Appends source paths to $_cron_sources. The caller must declare/initialize that
# array so this sourced hook can avoid leaking a global when tests invoke helpers
# directly.
_cron_source_files() {
  _cron_sources=()

  local source
  while IFS= read -r source; do
    _cron_sources+=("$source")
  done < <(dot_hook_family_files_matching cron/cron.d '*.cron' '*.replace/*.cron')

  source="$(dot_hook_family cron.local)"
  [[ -f "$source" ]] && _cron_sources+=("$source")
  return 0
}

# Marker of the managed crontab block; `dot doctor` compares against it.
_CRON_MARKER="# dot-managed-cron"

# Render the managed block for both installation and doctor comparison.
# Each applicable fragment retains its position and gets a short editing
# pointer, rather than listing unrelated sources in a single long header.
_cron_render_block() {
  local source fragment stanzas="" cron_path body shell_env

  for source in "${_cron_sources[@]}"; do
    _cron_parsed=""
    _cron_parse_file "$source"
    fragment=${_cron_parsed#"${_cron_parsed%%[![:space:]]*}"}
    fragment=${fragment%"${fragment##*[![:space:]]}"}
    [[ -n $fragment ]] || continue
    stanzas="${stanzas:+$stanzas$'\n\n'}# source: ${source##*/}"$'\n'"$fragment"
  done
  # Filter helpers use REPLY as scratch space, so clear it after parsing.
  REPLY=
  [[ -n $stanzas ]] || return 0

  cron_path=$(_cron_path)
  shell_env=$(_cron_shell_env "$cron_path")
  body=$shell_env
  [[ -z $cron_path ]] || body="${body:+$body$'\n'}PATH=$cron_path"
  body="${body:+$body$'\n\n'}$stanzas"
  REPLY=$(dot_managed_block_build "$_CRON_MARKER" \
    "cron fragments; see stanza sources below" "$body")
}

merge() {
  _dot_tool_present cron || return 0
  local cron_command
  _dot_account_scoped_command \
    "cron merge" crontab "${DOT_TEST_CRONTAB:-}" || return 0
  cron_command="$REPLY"
  local cron_marker=$_CRON_MARKER

  local -a _cron_sources
  _cron_source_files
  ((${#_cron_sources[@]} > 0)) || return 0

  dot_hook_log "  cron"

  local managed_block
  _cron_render_block
  managed_block=$REPLY

  # Everything below rewrites the whole crontab from this listing, so a
  # listing that failed must not pass for an empty crontab: the user's own
  # entries would be replaced by the managed block alone. Only a listing
  # that worked, or crontab's "no crontab yet", is safe to build on.
  local current listed=0
  _cron_list "$cron_command" || listed=$?
  current=$REPLY
  if ((listed == 2)); then
    # With nothing to install the hook would only strip an old block, which
    # it cannot see now; leave the crontab as it is, as before.
    [[ -n "$managed_block" ]] || return 0
    dot_hook_warn "  warning: crontab -l failed ($_CRON_LIST_ERR); crontab left unchanged"
    return 1
  fi

  # The block stripper is substring-based. Validate even an unchanged or
  # strip-only block before it can discard ambiguous user-owned entries.
  if ! _cron_block_valid "$cron_marker" "$current"; then
    dot_hook_warn "  warning: cron block markers are malformed; crontab left unchanged"
    return 1
  fi

  local filtered new_crontab remove=0
  # No active entries — strip any existing managed block.
  if [[ -z "$managed_block" ]]; then
    [[ "$current" == *"$cron_marker begin"* ]] || return 0
    new_crontab="$(dot_managed_block_strip "$cron_marker" "$current")"
    [[ -n "$new_crontab" ]] || remove=1
  else
    # Position is part of the contract: a legacy block at the bottom must move.
    if [[ "$current" == "$managed_block" || "$current" == "$managed_block"$'\n'* ]]; then
      return 0
    fi
    filtered="$(dot_managed_block_strip "$cron_marker" "$current")"
    # Unmanaged assignments remain in place and can override these defaults.
    if [[ -n "$filtered" ]]; then
      new_crontab="$managed_block"$'\n\n'"$filtered"
    else
      new_crontab="$managed_block"
    fi
  fi

  # A second read narrows the window in which a concurrent edit could be lost.
  # Crontab has no compare-and-swap, so another writer can still race afterward.
  local latest latest_status=0
  _cron_list "$cron_command" || latest_status=$?
  latest=$REPLY
  if ((latest_status != listed)) || [[ "$latest" != "$current" ]]; then
    dot_hook_warn "  warning: crontab changed or could not be re-read; crontab left unchanged"
    return 1
  fi
  if ((remove)); then
    "$cron_command" -r
  else
    printf '%s\n' "$new_crontab" | "$cron_command" -
  fi
}
