# shellcheck shell=bash
# Hook for php-cs-fixer — formatter for PHP.
#
# The fallback installs the official PHAR when PHP is already available.
# The wrapper pins the PHP interpreter path so an unrelated `php`
# compatibility shim earlier on PATH does not break the formatter later.
# dot update should not install PHP as a hidden dependency for an optional
# formatter.

_php_cs_fixer_php() {
  # Reject HHVM's php shim: it satisfies `command -v php` but cannot run the
  # PHAR. shdeps_find_runtime probes `--version`, which HHVM prints as
  # "HipHop VM ...", so the reject substring still filters it out.
  shdeps_find_runtime --reject "HipHop VM" \
    --path /opt/homebrew/opt/php/bin \
    --path /usr/local/opt/php/bin \
    --path /usr/bin \
    --path /usr/local/bin \
    php
}

exists() {
  command -v php-cs-fixer &>/dev/null && return 0

  shdeps_reinstall && return 1
  shdeps_skipped php-cs-fixer || return 1

  # If PHP appears later, retry automatically instead of requiring the user
  # to know a skip marker exists.
  _php_cs_fixer_php &>/dev/null && return 1
  return 0
}

version() {
  if ! command -v php-cs-fixer &>/dev/null && shdeps_skipped php-cs-fixer; then
    echo "skipped ($(shdeps_skip_reason php-cs-fixer))"
    return 0
  fi
  php-cs-fixer --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1
}

install() {
  shdeps_pkg_install_for_mgr \
    brew:php-cs-fixer \
    pacman:php-cs-fixer && exists && return 0

  local php
  php=$(_php_cs_fixer_php) || {
    shdeps_log "  php-cs-fixer skipped: PHP CLI unavailable"
    shdeps_skip php-cs-fixer "PHP CLI unavailable"
    return 0
  }

  local install_dir phar
  install_dir="$(shdeps_install_dir)/php-cs-fixer"
  phar="$install_dir/php-cs-fixer.phar"
  mkdir -p "$install_dir"
  shdeps_curl -fsSL --no-netrc \
    "https://cs.symfony.com/download/php-cs-fixer-v3.phar" \
    -o "$phar" || return 1

  shdeps_write_wrapper php-cs-fixer "$php" -- "$phar" >/dev/null || return 1
  shdeps_unskip php-cs-fixer
}

uninstall() {
  rm -rf "$(shdeps_install_dir)/php-cs-fixer"
  rm -f "$(shdeps_bin_dir)/php-cs-fixer"
}
