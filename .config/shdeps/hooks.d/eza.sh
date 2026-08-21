# shellcheck shell=bash
# DNF fallback for eza, which is not available in CentOS Stream 9's enabled
# repositories. Keep the dependency named `eza` so package-to-release changes
# remain a normal method transition in Shdeps' manifest.

_eza_release_root() {
  printf '%s/eza\n' "$(shdeps_install_dir)"
}

_eza_public_bin() {
  printf '%s/eza\n' "$(shdeps_bin_dir)"
}

_eza_release_root_owned() {
  local root marker
  root=$(_eza_release_root)
  marker="$root/.shdeps-release-layout"

  [[ -d "$root" && ! -L "$root" ]] || return 1
  [[ -f "$marker" && ! -L "$marker" ]] || return 1
  [[ $(<"$marker") == "v1 archive" ]]
}

_eza_public_link_owned() {
  local public root target
  public=$(_eza_public_bin)
  root=$(_eza_release_root)

  _eza_release_root_owned || return 1
  [[ -L "$public" ]] || return 1
  target=$(readlink "$public") || return 1
  case "$target" in
    /*) ;;
    *) target="${public%/*}/$target" ;;
  esac
  case "$target" in
    "$root"/*) return 0 ;;
    *) return 1 ;;
  esac
}

_eza_managed() {
  local public
  public=$(_eza_public_bin)

  _eza_public_link_owned || return 1
  [[ -x "$public" && ! -d "$public" ]] || return 1
  "$public" --version >/dev/null 2>&1
}

exists() {
  _eza_managed
}

version() {
  local public
  public=$(_eza_public_bin)
  _eza_managed || return 1
  "$public" --version 2>/dev/null | awk '/^v[0-9]/{ print; exit }'
}

install() {
  # The generic release helper owns asset selection, freshness, atomic
  # activation, and transport bounds. Supplying the repository separately lets
  # the manifest identity remain `eza` across the package-to-release change.
  shdeps_github_release_install eza eza eza-community/eza || return 1
  _eza_managed
}

uninstall() {
  local public root
  public=$(_eza_public_bin)
  root=$(_eza_release_root)

  # Release archives can expose completions and man pages. Remove only links
  # recorded by Shdeps, then independently protect a public command that a user
  # or another installer may have replaced since installation.
  shdeps_unlink_extras eza || return 1
  if _eza_public_link_owned; then
    rm -f -- "$public" || return 1
  fi
  if _eza_release_root_owned; then
    rm -rf -- "$root" || return 1
  fi
  if [[ -n ${SHDEPS_STATE_DIR:-} ]]; then
    rm -f -- "$SHDEPS_STATE_DIR/eza.binlinks" || return 1
  fi
}
