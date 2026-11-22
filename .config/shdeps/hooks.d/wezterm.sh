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
  local target=$1 row version digest url extra lock
  lock=$(_wezterm_lock)
  [[ -r $lock ]] || return 1
  while read -r row version digest url extra; do
    [[ $row == "$target" ]] || continue
    [[ $version =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ &&
      $digest =~ ^[0-9a-f]{64}$ &&
      $url == https://*/* && ${url##*/} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ &&
      -z $extra && (-z $expected || $expected == "$version") ]] || return 1
    expected=$version
    urls+=("$url")
    digests+=("$digest")
  done <"$lock"
  [[ -n $expected ]]
}

_wezterm_app() {
  printf '%s/Applications/WezTerm.app\n' "$HOME"
}

_wezterm_payload() {
  local install_dir
  install_dir=$(shdeps_install_dir) || return 1
  printf '%s/wezterm/%s-%s/WezTerm.app\n' "$install_dir" "$1" "$2"
}

_wezterm_version() {
  local result
  result=$("$1" --version 2>/dev/null) || return 1
  [[ $result == 'wezterm '* ]] || return 1
  printf '%s\n' "${result#wezterm }"
}

version() {
  local os
  os=$(shdeps_platform) || return 1
  if [[ $os == macos ]]; then
    _wezterm_version "$(_wezterm_app)/Contents/MacOS/wezterm"
  else
    _wezterm_version wezterm
  fi
}

exists() {
  local os target expected='' urls=() digests=()
  os=$(shdeps_platform) || return 1
  _wezterm_skip "$os" && return 0
  target=$(_wezterm_target "$os") || return 1
  _wezterm_pin "$target" || return 1
  if [[ $os == macos ]]; then
    local app bin_dir payload
    app=$(_wezterm_app)
    bin_dir=$(shdeps_bin_dir) || return 1
    payload=$(_wezterm_payload "$expected" "${digests[0]}") || return 1
    [[ $(readlink "$app") == "$payload" &&
    $(readlink "$bin_dir/wezterm") == "$app/Contents/MacOS/wezterm" ]] || return 1
  elif [[ $(shdeps_pkg_mgr) == dnf ]]; then
    # The RPM metapackage does not enforce equal versions of its components.
    # The CLI belongs to wezterm-common and cannot prove the GUI is current.
    local package_version installed
    package_version=${expected//-/_}-1.${target%-x86_64}
    installed=$(rpm -q --qf '%{VERSION}-%{RELEASE}\n' \
      wezterm wezterm-common wezterm-gui wezterm-mux-server) || return 1
    [[ $installed == "$(printf '%s\n' "$package_version" "$package_version" \
      "$package_version" "$package_version")" ]] || return 1
  fi
  [[ $(version) == "$expected" ]]
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
  shdeps_curl -fsSL --proto '=https' --proto-redir '=https' --no-netrc \
    -H 'Authorization:' "$url" -o "$destination" || {
    shdeps_warn "  warning: could not download pinned WezTerm archive: $url"
    return 1
  }
  # The publisher can replace a nightly at the same URL. Refuse it until the
  # new build is reviewed and its version and checksum are pinned together.
  if [[ $(_wezterm_sha256 "$destination") != "$checksum" ]]; then
    shdeps_warn "  warning: WezTerm archive checksum differs from its pin: $url"
    return 1
  fi
}

# Keep the existing system app available when adopting the pin. Both the CLI
# and Finder shortcut follow one symlink switched on the Applications volume.
_wezterm_macos() (
  local archive=$1 expected=$2 checksum=$3
  local app bin_dir root staged bundle target cli scratch
  app=$(_wezterm_app)
  bin_dir=$(shdeps_bin_dir) || return 1
  cli=$bin_dir/wezterm
  target=$(_wezterm_payload "$expected" "$checksum") || return 1
  root=${target%/*/*}

  if [[ -e $app || -L $app ]]; then
    case "$(readlink "$app")" in
      "$root/"*/WezTerm.app) ;;
      *)
        shdeps_warn "  warning: preserving an unmanaged WezTerm app at $app"
        return 1
        ;;
    esac
  fi
  if [[ -e $cli || -L $cli ]]; then
    if [[ $(readlink "$cli") != "$app/Contents/MacOS/wezterm" ]]; then
      shdeps_warn "  warning: preserving an unmanaged WezTerm command at $cli"
      return 1
    fi
  fi
  [[ ! -L $root && ! -L ${target%/*} && ! -L $target ]] || return 1
  mkdir -p "${app%/*}" "$bin_dir" "${target%/*}" || return 1
  staged=$(mktemp -d "$root/.stage.XXXXXXXX") || return 1
  scratch=''
  trap 'rm -rf -- "$staged"; [[ -z $scratch ]] || rm -rf -- "$scratch"' EXIT
  if [[ ! -e $target ]]; then
    ditto -x -k "$archive" "$staged" || return 1
    local bundles=("$staged"/WezTerm-macos-*/WezTerm.app)
    [[ ${#bundles[@]} -eq 1 && -d "${bundles[0]}" ]] || return 1
    bundle=${bundles[0]}
    codesign --verify --deep --strict "$bundle" || return 1
    [[ $(_wezterm_version "$bundle/Contents/MacOS/wezterm") == "$expected" ]] ||
      return 1
    # The version directory may already exist after an interrupted install or
    # deletion of the app. Publish the validated bundle at the exact leaf.
    mv -- "$bundle" "$target" || return 1
  else
    codesign --verify --deep --strict "$target" || return 1
  fi
  [[ $(_wezterm_version "$target/Contents/MacOS/wezterm") == "$expected" ]] ||
    return 1
  scratch=$(mktemp -d "${app%/*}/.wezterm-link.XXXXXXXX") || return 1
  ln -s "$target" "$scratch/WezTerm.app" || return 1

  local cli_created=0
  if [[ ! -L $cli ]]; then
    ln -s "$app/Contents/MacOS/wezterm" "$cli" || return 1
    cli_created=1
  fi
  # BSD mv -h replaces the app symlink instead of following its destination.
  if ! mv -fh -- "$scratch/WezTerm.app" "$app"; then
    ((cli_created == 0)) || rm -f -- "$cli"
    return 1
  fi
)

_wezterm_linux() {
  local manager package pacman_packages=()
  manager=$(shdeps_pkg_mgr) || return 1
  case "$manager" in
    apt) sudo apt-get install -y --allow-downgrades "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    pacman)
      # Pacman reads the detached signature beside the named package.
      for package in "$@"; do
        [[ $package == *.pkg.tar.zst ]] && pacman_packages+=("$package")
      done
      [[ ${#pacman_packages[@]} -eq 1 && -f ${pacman_packages[0]}.sig ]] || return 1
      sudo pacman -U --noconfirm "${pacman_packages[0]}"
      ;;
    *) return 1 ;;
  esac
}

install() (
  local os target expected='' urls=() digests=() packages=() tmp index url
  os=$(shdeps_platform) || return 1
  _wezterm_skip "$os" && return 0
  target=$(_wezterm_target "$os") || return 1
  _wezterm_pin "$target" || {
    shdeps_warn "  warning: no valid WezTerm build pin for $target"
    return 1
  }
  # Shdeps may restart the hook after prompting for sudo. Do that before
  # spending time on downloads, but call the package manager only after verify.
  if [[ $os == linux ]]; then
    shdeps_require_sudo || return 1
  fi

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
    _wezterm_linux "${packages[@]}" || return 1
  fi
  if ! exists; then
    shdeps_warn "  warning: WezTerm did not converge to build $expected"
    return 1
  fi
)
