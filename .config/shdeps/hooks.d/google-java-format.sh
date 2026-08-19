# shellcheck shell=bash
# Hook for google-java-format — formatter and lint-style checker for Java.
#
# Most Linux distros do not package this CLI, but upstream publishes a single
# all-deps JAR. The fallback uses an existing Java runtime and writes a tiny
# wrapper with that path pinned. dot update should not surprise small systems
# by installing a full JRE just to support an optional formatter.

_google_java_format_java() {
  shdeps_find_runtime \
    --path /opt/homebrew/opt/openjdk/bin \
    --path /usr/local/opt/openjdk/bin \
    --path /usr/bin \
    --path /usr/local/bin \
    java
}

exists() {
  command -v google-java-format &>/dev/null && return 0

  shdeps_reinstall && return 1
  shdeps_skipped google-java-format || return 1

  # If Java appears later, retry automatically instead of requiring the user
  # to know a skip marker exists.
  _google_java_format_java &>/dev/null && return 1
  return 0
}

version() {
  if ! command -v google-java-format &>/dev/null && shdeps_skipped google-java-format; then
    echo "skipped ($(shdeps_skip_reason google-java-format))"
    return 0
  fi
  google-java-format --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1
}

install() {
  shdeps_pkg_install_for_mgr \
    brew:google-java-format \
    pacman:google-java-format && exists && return 0

  local java
  java=$(_google_java_format_java) || {
    shdeps_log "  google-java-format skipped: Java runtime unavailable"
    shdeps_skip google-java-format "Java runtime unavailable"
    return 0
  }

  local release_json asset_url latest_tag install_dir jar
  release_json=$(shdeps_curl -fsSL --no-netrc -H "Authorization:" \
    "https://api.github.com/repos/google/google-java-format/releases/latest" 2>/dev/null) || {
    shdeps_warn "  warning: couldn't fetch google-java-format release info"
    return 1
  }
  latest_tag=$(echo "$release_json" | grep -o '"tag_name":[[:space:]]*"[^"]*"' | cut -d'"' -f4)
  asset_url=$(echo "$release_json" |
    grep -o '"browser_download_url":[[:space:]]*"[^"]*all-deps\.jar"' |
    cut -d'"' -f4 |
    head -1)
  if [[ -z "$asset_url" ]]; then
    shdeps_warn "  warning: no all-deps jar found for google-java-format ${latest_tag:-latest}"
    return 1
  fi

  install_dir="$(shdeps_install_dir)/google-java-format"
  jar="$install_dir/google-java-format.jar"
  mkdir -p "$install_dir"
  shdeps_curl -fsSL --no-netrc "$asset_url" -o "$jar" || return 1

  # Pin the resolved Java path so an unrelated `java` later on PATH cannot
  # break the formatter; shdeps_write_wrapper handles the bin dir and chmod.
  shdeps_write_wrapper google-java-format "$java" -jar -- "$jar" >/dev/null || return 1
  shdeps_unskip google-java-format
}

uninstall() {
  rm -rf "$(shdeps_install_dir)/google-java-format"
  rm -f "$(shdeps_bin_dir)/google-java-format"
}
