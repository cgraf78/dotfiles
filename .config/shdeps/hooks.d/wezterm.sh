# shellcheck shell=bash
# Install the reviewed WezTerm snapshot for this desktop target.

_wezterm_lock() {
  printf '%s\n' "${BASH_SOURCE[0]%/*}/wezterm-build.lock"
}

_wezterm_os_release() {
  local ID='' VERSION_ID=''
  if [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
  fi
  printf '%s|%s\n' "$ID" "$VERSION_ID"
}

_wezterm_skip() {
  [[ -n "${CI:-}" ]] || case "$1" in
    macos) return 1 ;;
    linux) [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]] ;;
    *) return 0 ;; # Includes Windows-native WezTerm under WSL.
  esac
}

_wezterm_target() {
  local os=$1 arch release distro revision
  case "$(uname -m)" in
    x86_64 | amd64) arch=x86_64 ;;
    aarch64 | arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  if [[ $os == macos ]]; then
    printf 'macos\n'
    return
  fi
  release=$(_wezterm_os_release)
  distro=${release%%|*}
  revision=${release#*|}
  case "$distro" in
    centos | rhel | rocky | almalinux)
      distro=centos
      revision=${revision%%.*}
      ;;
  esac
  printf '%s%s-%s\n' "$distro" "$revision" "$arch"
}

# Callers declare the outputs locally. An RPM target can have several files
# but all of them must come from the same executable build.
_wezterm_pin() {
  local target=$1 row version digest url extra lock previous
  lock=$(_wezterm_lock)
  [[ -r $lock ]] || return 1
  while read -r row version digest url extra; do
    [[ $row == "$target" ]] || continue
    [[ $version =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ &&
      $digest =~ ^[0-9a-f]{64}$ &&
      $url == https://*/* && ${url##*/} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
      -z $extra && (-z $expected || $expected == "$version") ]] || return 1
    for previous in ${urls[@]+"${urls[@]}"}; do
      [[ ${previous##*/} != "${url##*/}" ]] || return 1
    done
    expected=$version
    urls+=("$url")
    digests+=("$digest")
  done <"$lock"
  [[ -n $expected ]]
}

_wezterm_rpm_names() {
  printf '%s\n' 'wezterm wezterm-common wezterm-gui wezterm-mux-server'
}

_wezterm_packages() {
  local os=$1 manager=$2 target=$3 name url
  if [[ $os == macos ]]; then
    [[ ${#urls[@]} -eq 1 && ${urls[0]} == *.zip ]]
    return
  fi
  case "$manager" in
    apt) [[ ${#urls[@]} -eq 1 && ${urls[0]} == *.deb ]] ;;
    dnf)
      local names=() missing
      read -r -a names <<<"$(_wezterm_rpm_names)"
      [[ ${#urls[@]} -eq ${#names[@]} ]] || return 1
      for name in "${names[@]}"; do
        missing=1
        for url in "${urls[@]}"; do
          if [[ ${url##*/} == "$name-nightly-${target%-x86_64}.rpm" ]]; then
            missing=0
            break
          fi
        done
        ((missing == 0)) || return 1
      done
      ;;
    pacman)
      [[ ${#urls[@]} -eq 2 && -n $(_wezterm_arch_archive) ]] || return 1
      local archive
      archive=$(_wezterm_arch_archive)
      [[ ${urls[0]##*/} == "$archive.sig" || ${urls[1]##*/} == "$archive.sig" ]]
      ;;
    *) return 1 ;;
  esac
}

_wezterm_arch_archive() {
  local url
  for url in "${urls[@]}"; do
    if [[ ${url##*/} == wezterm-*-x86_64.pkg.tar.zst ]]; then
      printf '%s\n' "${url##*/}"
      return
    fi
  done
  return 1
}

_wezterm_rpm_current() {
  # The metapackage doesn't require matching component versions. Check each
  # package because even a current CLI can coexist with an older GUI or mux.
  local target=$1 expected=$2 names=() installed version
  read -r -a names <<<"$(_wezterm_rpm_names)"
  version=${expected//-/_}-1.${target%-x86_64}
  installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' "${names[@]}") || return 1
  [[ $installed == "$(printf '%s\n' "$version" "$version" "$version" "$version")" ]]
}

_wezterm_native_current() {
  local manager=$1 target=$2 expected=$3 archive version
  case "$manager" in
    apt)
      [[ $(dpkg-query -W -f='${db:Status-Status}\t${Version}\n' wezterm-nightly) == "installed"$'\t'"$expected" ]]
      ;;
    dnf) _wezterm_rpm_current "$target" "$expected" ;;
    pacman)
      archive=$(_wezterm_arch_archive) || return 1
      version=${archive#wezterm-}
      [[ $(pacman -Q wezterm) == "wezterm ${version%-x86_64.pkg.tar.zst}" ]]
      ;;
  esac
}

_wezterm_app() {
  printf '%s/Applications/WezTerm.app\n' "$HOME"
}

_wezterm_payload() {
  local install_dir
  install_dir=$(shdeps_install_dir) || return 1
  printf '%s/wezterm/%s-%s/WezTerm.app\n' "$install_dir" "$1" "$2"
}

_wezterm_matching_app() {
  # A repair may replace the active bundle without overwriting the damaged
  # one at the original path. Both locations encode the same pinned build.
  case "$1" in
    "$2" | "${2%/*}".repair.????????/WezTerm.app) return 0 ;;
    *) return 1 ;;
  esac
}

_wezterm_owns_app() {
  local link=$1 root=$2 relative
  [[ $link == "$root/"* ]] || return 1
  relative=${link#"$root/"}
  [[ $relative =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}-[0-9a-f]{64}(\.repair\.[a-zA-Z0-9]{8})?/WezTerm\.app$ ]]
}

_wezterm_cli_script() {
  # WezTerm uses its executable's directory to locate wezterm-gui. Invoking
  # the bundle binary through a bare symlink can make it look in the bin dir.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/sh' 'exec "$HOME/Applications/WezTerm.app/Contents/MacOS/wezterm" "$@"'
}

_wezterm_owns_cli() {
  [[ -f $1 && ! -L $1 && $(<"$1") == "$(_wezterm_cli_script)" ]]
}

_wezterm_cli_available() {
  [[ ! -e $1 && ! -L $1 ]] || _wezterm_owns_cli "$1" ||
    [[ $(readlink "$1") == "$2/Contents/MacOS/wezterm" ]]
}

_wezterm_app_link() {
  if [[ -L $1 ]]; then
    readlink "$1"
  elif [[ -e $1 ]]; then
    return 1
  fi
}

_wezterm_version() {
  local result
  result=$("$1" --version 2>/dev/null) || return 1
  [[ $result == "${1##*/} "* ]] || return 1
  printf '%s\n' "${result#* }"
}

version() {
  local os
  os=$(shdeps_platform) || return 1
  if [[ $os == macos ]]; then
    _wezterm_version "$(_wezterm_app)/Contents/MacOS/wezterm"
  else
    _wezterm_version /usr/bin/wezterm
  fi
}

exists() {
  local os manager='' target expected='' urls=() digests=()
  os=$(shdeps_platform) || return 1
  _wezterm_skip "$os" && return 0
  target=$(_wezterm_target "$os") || return 1
  _wezterm_pin "$target" || return 1
  [[ $os == macos ]] || manager=$(shdeps_pkg_mgr) || return 1
  _wezterm_packages "$os" "$manager" "$target" || return 1
  if [[ $os == macos ]]; then
    local app bin_dir payload linked
    app=$(_wezterm_app)
    bin_dir=$(shdeps_bin_dir) || return 1
    payload=$(_wezterm_payload "$expected" "${digests[0]}") || return 1
    linked=$(_wezterm_app_link "$app") || return 1
    _wezterm_matching_app "$linked" "$payload" || return 1
    [[ -x $bin_dir/wezterm ]] || return 1
    _wezterm_owns_cli "$bin_dir/wezterm" || return 1
    _wezterm_valid_app "$app" "$expected" 2>/dev/null
  else
    _wezterm_native_current "$manager" "$target" "$expected" || return 1
    [[ $(version) == "$expected" && $(_wezterm_version /usr/bin/wezterm-gui) == "$expected" ]]
  fi
}

_wezterm_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

_wezterm_fetch() {
  local url=$1 checksum=$2 destination=$3
  # Curl only suppresses .curlrc when --disable is its first argument. Use
  # the usual Shdeps timeouts without inheriting credentials or TLS settings.
  curl --disable --connect-timeout 10 --speed-limit 1024 --speed-time 60 --retry 3 \
    -fsSL --proto '=https' --proto-redir '=https' --no-netrc \
    -H 'Authorization:' "$url" -o "$destination" || {
    shdeps_warn "  warning: could not download pinned WezTerm archive: $url"
    return 1
  }
  # Refuse any payload that does not match the reviewed snapshot, even if
  # the release URL and executable version appear unchanged.
  if [[ $(_wezterm_sha256 "$destination") != "$checksum" ]]; then
    shdeps_warn "  warning: WezTerm archive checksum differs from its pin: $url"
    return 1
  fi
}

# Keep the existing system app available when adopting the pin. Both the CLI
# and Finder shortcut follow one symlink switched on the Applications volume.
_wezterm_valid_app() {
  local app=$1 expected=$2
  [[ -x $app/Contents/MacOS/wezterm-gui && -x $app/Contents/MacOS/wezterm ]] &&
    codesign --verify --deep --strict "$app" &&
    [[ $(_wezterm_version "$app/Contents/MacOS/wezterm") == "$expected" ]]
}

_wezterm_macos() (
  local archive=$1 expected=$2 checksum=$3
  local app bin_dir root staged bundle target cli scratch='' cli_stage='' repair=''
  local before after cli_created=0
  app=$(_wezterm_app)
  bin_dir=$(shdeps_bin_dir) || return 1
  cli=$bin_dir/wezterm
  target=$(_wezterm_payload "$expected" "$checksum") || return 1
  root=${target%/*/*}

  if ! before=$(_wezterm_app_link "$app") || { [[ -n $before ]] && ! _wezterm_owns_app "$before" "$root"; }; then
    shdeps_warn "  warning: preserving an unmanaged WezTerm app at $app"
    return 1
  fi
  if ! _wezterm_cli_available "$cli" "$app"; then
    shdeps_warn "  warning: preserving an unmanaged WezTerm command at $cli"
    return 1
  fi
  [[ ! -L $root && ! -L ${target%/*} && ! -L $target ]] || return 1
  mkdir -p "${app%/*}" "$bin_dir" "${target%/*}" || return 1
  staged=$(mktemp -d "$root/.stage.XXXXXXXX") || return 1
  trap 'rm -rf -- "$staged"; [[ -z $scratch ]] || rm -rf -- "$scratch"; [[ -z $cli_stage ]] || rm -f -- "$cli_stage"; [[ -z $repair ]] || rm -rf -- "$repair"' EXIT
  if _wezterm_matching_app "$before" "$target" && _wezterm_valid_app "$before" "$expected" 2>/dev/null; then
    target=$before
  elif ! _wezterm_valid_app "$target" "$expected" 2>/dev/null; then
    ditto -x -k "$archive" "$staged" || return 1
    local bundles=("$staged"/WezTerm-macos-*/WezTerm.app)
    [[ ${#bundles[@]} -eq 1 && -d "${bundles[0]}" ]] || return 1
    bundle=${bundles[0]}
    _wezterm_valid_app "$bundle" "$expected" || return 1
    # When the leaf is damaged, publish a separate validated generation so
    # the active link switches in one operation and never sees a partial app.
    if [[ -e $target ]]; then
      repair=$(mktemp -d "${target%/*}.repair.XXXXXXXX") || return 1
      target=$repair/WezTerm.app
    fi
    mv -- "$bundle" "$target" || return 1
  fi
  scratch=$(mktemp -d "${app%/*}/.wezterm-link.XXXXXXXX") || return 1
  ln -s "$target" "$scratch/WezTerm.app" || return 1

  # Recheck public paths after verification, which gives other installers
  # time to create an app or command that was absent during the first check.
  after=$(_wezterm_app_link "$app") || return 1
  [[ $after == "$before" ]] || return 1
  if ! _wezterm_owns_cli "$cli" || [[ ! -x $cli ]]; then
    cli_stage=$(mktemp "$bin_dir/.wezterm.XXXXXXXX") || return 1
    _wezterm_cli_script >"$cli_stage" && chmod 0755 "$cli_stage" || return 1
    _wezterm_cli_available "$cli" "$app" || return 1
    [[ -e $cli || -L $cli ]] || cli_created=1
    mv -fh -- "$cli_stage" "$cli" || return 1
  fi
  # BSD mv -h replaces the app symlink instead of following its destination.
  if ! after=$(_wezterm_app_link "$app") || [[ $after != "$before" ]] ||
    ! mv -fh -- "$scratch/WezTerm.app" "$app"; then
    if ((cli_created)) && _wezterm_owns_cli "$cli"; then rm -f -- "$cli"; fi
    return 1
  fi
  repair=''
)

_wezterm_linux() {
  local manager=$1 target=$2 expected=$3 archive package dnf_action=install
  shift 3
  case "$manager" in
    apt) sudo apt-get install -y --allow-downgrades --reinstall "$@" ;;
    dnf)
      # Install skips an already-registered build even if its CLI is missing.
      _wezterm_rpm_current "$target" "$expected" && dnf_action=reinstall
      sudo dnf "$dnf_action" -y "$@"
      ;;
    pacman)
      # Pacman reads the detached signature beside the named package.
      archive=$(_wezterm_arch_archive) || return 1
      for package in "$@"; do
        [[ ${package##*/} == "$archive" ]] || continue
        sudo pacman -U --noconfirm "$package"
        return
      done
      return 1
      ;;
    *) return 1 ;;
  esac
}

install() {
  local os manager='' target expected='' urls=() digests=()
  os=$(shdeps_platform) || return 1
  _wezterm_skip "$os" && return 0
  target=$(_wezterm_target "$os") || return 1
  [[ $os == macos ]] || manager=$(shdeps_pkg_mgr) || return 1
  if ! _wezterm_pin "$target" || ! _wezterm_packages "$os" "$manager" "$target"; then
    shdeps_warn "  warning: no valid WezTerm build pin for $target"
    return 1
  fi
  if [[ $manager == pacman ]]; then
    # The Arch OpenSSL 4 rebuild declares an unversioned dependency. On a
    # partially updated host pacman could replace a working app with one
    # linked to libraries the host doesn't have yet.
    if ! pacman -T 'openssl>=4' >/dev/null; then
      shdeps_warn '  warning: update Arch before installing the pinned WezTerm build (OpenSSL 4 required)'
      return 1
    fi
    if pacman -Q wezterm-shell-integration >/dev/null 2>&1; then
      shdeps_warn '  warning: update Arch to retire the old wezterm-shell-integration package before applying the WezTerm pin'
      return 1
    fi
  fi
  # Shdeps may restart the hook after prompting for sudo. Do that before
  # starting the staging subshell so the request exits the whole hook.
  if [[ $os == linux ]]; then
    shdeps_require_sudo || return 1
  fi

  _wezterm_stage "$os" "$manager" "$target" "$expected"
}

_wezterm_stage() (
  local os=$1 manager=$2 target=$3 expected=$4 packages=() tmp index url
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/wezterm.XXXXXXXX") || return 1
  trap 'rm -rf -- "$tmp"' EXIT
  for index in "${!urls[@]}"; do
    url=${urls[index]}
    packages+=("$tmp/${url##*/}")
    _wezterm_fetch "$url" "${digests[index]}" "${packages[index]}" ||
      return 1
  done
  if [[ $os == macos ]]; then
    [[ ${#packages[@]} -eq 1 ]] || return 1
    _wezterm_macos "${packages[0]}" "$expected" "${digests[0]}" || return 1
  else
    _wezterm_linux "$manager" "$target" "$expected" "${packages[@]}" || return 1
  fi
  if ! exists; then
    shdeps_warn "  warning: WezTerm did not converge to build $expected"
    return 1
  fi
)
