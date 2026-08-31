#!/usr/bin/env bash
# Install the base-owned tmux version from the reviewed tmux-builds archives.

_TMUX_VERSION=3.6b

_tmux_root() {
  # ~/.local/share/tmux is application state (including tmux-resurrect data),
  # so keep the managed executable in its own owned child directory.
  printf '%s/tmux/tmux-builds\n' "$(shdeps_install_dir)"
}

_tmux_public() {
  printf '%s/tmux\n' "$(shdeps_bin_dir)"
}

_tmux_asset() {
  local platform arch asset checksum
  platform=$(shdeps_platform) || return 1
  arch=$(uname -m) || return 1
  case $platform:$arch in
    linux:x86_64 | linux:amd64 | wsl:x86_64 | wsl:amd64)
      asset=linux-x86_64
      checksum=002a6f4fd52212600fa0d72d865dcf328e5b8b6e83c179788144d8587b75677a
      ;;
    linux:aarch64 | linux:arm64 | wsl:aarch64 | wsl:arm64)
      asset=linux-arm64
      checksum=fd4a2206c5e468dd2ee4e9a65f2d40e0762551965d7fdbe849c494ab14f513e9
      ;;
    macos:x86_64 | macos:amd64)
      asset=macos-x86_64
      checksum=073f6e2c2baa7eb5d643563600ee6052ca8619f3ec5a0cfdf99c56397fb72c94
      ;;
    macos:aarch64 | macos:arm64)
      asset=macos-arm64
      checksum=88323402bd28d21103239caf009b130086ebf334807de485d4a1e1c7188ee810
      ;;
    *) return 1 ;;
  esac
  REPLY_URL="https://github.com/tmux/tmux-builds/releases/download/v$_TMUX_VERSION/tmux-$_TMUX_VERSION-$asset.tar.gz"
  REPLY_SHA256=$checksum
}

_tmux_sha256() {
  local path=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{ print $1; exit }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{ print $1; exit }'
  else
    return 1
  fi
}

_tmux_root_owned() {
  local root marker
  root=$(_tmux_root)
  marker=$root/.shdeps-tmux-build
  [[ -d $root && ! -L $root && -f $marker && ! -L $marker ]] || return 1
  [[ $(<"$marker") == "version=$_TMUX_VERSION" ]]
}

_tmux_public_owned() {
  local public root target
  public=$(_tmux_public)
  root=$(_tmux_root)
  _tmux_root_owned || return 1
  [[ -L $public ]] || return 1
  target=$(readlink "$public") || return 1
  case $target in
    /*) ;;
    *) target=${public%/*}/$target ;;
  esac
  [[ $target == "$root/tmux" ]]
}

_tmux_publish() {
  local root public bin_dir temporary target
  root=$(_tmux_root)
  public=$(_tmux_public)
  bin_dir=${public%/*}
  target=$root/tmux
  mkdir -p "$bin_dir" || return 1

  if [[ -e $public || -L $public ]]; then
    if ! _tmux_public_owned; then
      if [[ -x $public && ! -d $public ]]; then
        shdeps_warn "  warning: preserving non-Shdeps tmux command: $public"
        return 0
      fi
      shdeps_warn "  warning: refusing to replace non-Shdeps path: $public"
      return 1
    fi
  else
    ln -s "$target" "$public" || return 1
    return 0
  fi

  temporary=$(mktemp "$bin_dir/.tmux-link.XXXXXX") || return 1
  rm -f -- "$temporary" || return 1
  ln -s "$target" "$temporary" || return 1
  if ! mv -f -- "$temporary" "$public"; then
    rm -f -- "$temporary"
    return 1
  fi
}

exists() {
  if [[ $(shdeps_platform) == android ]]; then
    command -v tmux >/dev/null 2>&1 && tmux -V >/dev/null 2>&1
    return
  fi

  local root public
  root=$(_tmux_root)
  public=$(_tmux_public)
  _tmux_root_owned && [[ -x $root/tmux && ! -d $root/tmux ]] || return 1
  "$root/tmux" -V 2>/dev/null | grep -Fx "tmux $_TMUX_VERSION" >/dev/null || return 1
  if _tmux_public_owned; then
    return 0
  fi
  [[ -x $public && ! -d $public ]]
}

version() {
  if [[ $(shdeps_platform) == android ]]; then
    tmux -V 2>/dev/null
    return
  fi
  "$(_tmux_root)/tmux" -V 2>/dev/null
}

install() {
  if [[ $(shdeps_platform) == android ]]; then
    shdeps_pkg_install_for_mgr android:tmux
    return
  fi

  local root install_base stage archive candidate backup='' checksum
  _tmux_asset || {
    shdeps_warn '  warning: no pinned tmux build for this platform'
    return 1
  }
  root=$(_tmux_root)
  install_base=${root%/*}
  mkdir -p "$install_base" || return 1
  stage=$(mktemp -d "$install_base/.tmux-stage.XXXXXX") || return 1
  archive=$stage/tmux.tar.gz
  candidate=$stage/install
  mkdir "$candidate" || {
    rm -rf -- "$stage"
    return 1
  }

  if ! shdeps_curl -fsSL --no-netrc "$REPLY_URL" -o "$archive"; then
    rm -rf -- "$stage"
    shdeps_warn '  warning: tmux archive download failed'
    return 1
  fi
  checksum=$(_tmux_sha256 "$archive") || {
    rm -rf -- "$stage"
    shdeps_warn '  warning: no SHA-256 implementation is available'
    return 1
  }
  if [[ $checksum != "$REPLY_SHA256" ]]; then
    rm -rf -- "$stage"
    shdeps_warn '  warning: tmux archive checksum mismatch'
    return 1
  fi
  if ! tar -xzf "$archive" -C "$candidate" ||
    [[ ! -x $candidate/tmux || -L $candidate/tmux || -d $candidate/tmux ]]; then
    rm -rf -- "$stage"
    shdeps_warn '  warning: tmux archive layout is invalid'
    return 1
  fi
  rm -f -- "$archive"
  printf 'version=%s\n' "$_TMUX_VERSION" >"$candidate/.shdeps-tmux-build" || {
    rm -rf -- "$stage"
    return 1
  }

  if [[ -e $root || -L $root ]]; then
    _tmux_root_owned || {
      rm -rf -- "$stage"
      shdeps_warn "  warning: refusing to replace unowned tmux payload: $root"
      return 1
    }
    backup=$(mktemp -d "$install_base/.tmux-backup.XXXXXX") || {
      rm -rf -- "$stage"
      return 1
    }
    rmdir "$backup" || return 1
    mv -- "$root" "$backup" || {
      rm -rf -- "$stage"
      return 1
    }
  fi
  if ! mv -- "$candidate" "$root"; then
    [[ -z $backup ]] || mv -- "$backup" "$root" || true
    rm -rf -- "$stage"
    return 1
  fi
  if ! _tmux_publish; then
    rm -rf -- "$root"
    [[ -z $backup ]] || mv -- "$backup" "$root" || true
    rm -rf -- "$stage"
    return 1
  fi
  [[ -z $backup ]] || rm -rf -- "$backup"
  rm -rf -- "$stage"
}

uninstall() {
  local public root
  public=$(_tmux_public)
  root=$(_tmux_root)
  _tmux_public_owned && rm -f -- "$public"
  _tmux_root_owned && rm -rf -- "$root"
}
