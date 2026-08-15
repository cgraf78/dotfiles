#!/usr/bin/env bash
# Activate the one-time public-library handoff only after the fleet gate has
# published durable capability authority in XDG state.

prepare() {
  local helper capability

  helper=${DOT_EXTENSIONS_DIR:?}/dot-library-handoff.sh
  [[ -f $helper && ! -L $helper && -x $helper ]] || return 1
  dot_xdg_path state dot/library-handoff-v1/capability || return 1
  capability=$REPLY
  [[ -e $capability || -L $capability ]] || return 0
  "$helper" apply
}
