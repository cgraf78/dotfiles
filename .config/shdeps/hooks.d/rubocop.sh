# shellcheck shell=bash
# Hook for rubocop — formatter and linter for Ruby.
#
# Package names vary across distros, and some platforms only reliably provide
# Ruby/RubyGems. The fallback uses RubyGems only when it already exists; dot
# update should not install Ruby as a hidden dependency for an optional linter.
#
# Unlike the java/php hooks, gem discovery and the wrapper stay bespoke: the
# scan must reject policy-wrapper gems across every PATH match (more than
# shdeps_find_runtime's single-match/single-reject contract), and the wrapper
# execs a gem binary with a prepended PATH rather than an interpreter+payload.

_rubocop_gem_usable() {
  local gem_cmd="$1" output
  [[ -x "$gem_cmd" ]] || return 1

  output=$("$gem_cmd" --version 2>&1) || return 1
  case "$output" in
    *"not allowed"* | *"blocked by local policy"*) return 1 ;;
  esac
}

_rubocop_gem() {
  local candidate

  # Managed hosts may put a policy wrapper at /usr/local/bin/gem. Scan all
  # PATH matches and common package-manager locations so a real RubyGems
  # binary installed by the package manager can still be used.
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    _rubocop_gem_usable "$candidate" || continue
    echo "$candidate"
    return 0
  done < <(
    {
      type -P -a gem 2>/dev/null || true
      printf '%s\n' \
        /opt/homebrew/opt/ruby/bin/gem \
        /usr/local/opt/ruby/bin/gem \
        /usr/bin/gem \
        /usr/local/bin/gem
    } | awk '!seen[$0]++'
  )

  return 1
}

exists() {
  command -v rubocop &>/dev/null && return 0
  shdeps_reinstall && return 1
  shdeps_skipped rubocop || return 1

  # If RubyGems appears later, retry automatically instead of requiring the
  # user to know a skip marker exists. A failed gem install stays skipped
  # because retrying every dot update would recreate the same noisy failure.
  if [[ "$(shdeps_skip_reason rubocop)" == "RubyGems unavailable" ]] &&
    _rubocop_gem &>/dev/null; then
    return 1
  fi
  return 0
}

version() {
  if ! command -v rubocop &>/dev/null && shdeps_skipped rubocop; then
    echo "skipped ($(shdeps_skip_reason rubocop))"
    return 0
  fi
  rubocop --version 2>/dev/null | head -1
}

install() {
  shdeps_pkg_install_for_mgr \
    brew:rubocop \
    apt:rubocop \
    dnf:rubygem-rubocop \
    dnf:rubocop \
    pacman:ruby-rubocop \
    zypper:rubygem-rubocop \
    zypper:rubocop \
    apk:ruby-rubocop \
    apk:rubocop && exists && return 0

  local gem_cmd
  if ! gem_cmd=$(_rubocop_gem); then
    shdeps_log "  rubocop skipped: RubyGems unavailable"
    shdeps_skip rubocop "RubyGems unavailable"
    return 0
  fi

  if ! "$gem_cmd" install --user-install --no-document rubocop &>/dev/null; then
    shdeps_log "  rubocop skipped: RubyGems install unavailable"
    shdeps_skip rubocop "RubyGems install unavailable"
    return 0
  fi

  local gem_home gem_bin wrapper
  gem_home=$("$gem_cmd" env user_gemhome 2>/dev/null) || return 1
  gem_bin="$gem_home/bin/rubocop"
  if [[ ! -x "$gem_bin" ]]; then
    shdeps_warn "  warning: rubocop gem installed but $gem_bin is not executable"
    return 1
  fi

  wrapper="$(shdeps_bin_dir)/rubocop"
  mkdir -p "$(dirname "$wrapper")"
  {
    printf '#!/usr/bin/env bash\n'
    # shellcheck disable=SC2016
    printf 'export PATH=%q/bin:"$PATH"\n' "$gem_home"
    printf 'exec %q "$@"\n' "$gem_bin"
  } >"$wrapper"
  chmod u+x "$wrapper"
}

uninstall() {
  rm -f "$(shdeps_bin_dir)/rubocop"
  rm -rf "$(shdeps_install_dir)/rubocop"
  if command -v gem &>/dev/null; then
    gem uninstall --executables --ignore-dependencies --all rubocop &>/dev/null || true
  fi
}
