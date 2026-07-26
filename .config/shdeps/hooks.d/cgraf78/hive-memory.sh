# shellcheck shell=bash
# Post-install hook for Hive Memory.

_hive_memory_install_dir() {
  printf '%s\n' "$(shdeps_install_dir)/hive-memory"
}

_hive_memory_core_path() {
  printf '%s\n' "$(_hive_memory_install_dir)/bin/hm-core"
}

_hive_memory_launcher_path() {
  printf '%s\n' "$HOME/.local/lib/dot/hive-memory/hm-launcher"
}

_hive_memory_link_launcher() {
  local core launcher bin_dir
  core=$(_hive_memory_core_path)
  launcher=$(_hive_memory_launcher_path)
  bin_dir=$(shdeps_bin_dir)

  [[ -x "$core" ]] || return 1
  [[ -x "$launcher" ]] || return 1
  mkdir -p "$bin_dir"
  # Keep the PATH-visible command named `hm`, but point it at the dotfiles
  # launcher. The generic upstream binary lives behind `hm-core` so the
  # launcher can add agent session context without the core tool knowing about
  # Claude, Codex, Gemini, or this dotfiles layout.
  ln -sf "$launcher" "$bin_dir/hm"
}

post() {
  local release_bin core
  release_bin="$(shdeps_install_dir)/cgraf78/hive-memory/hm"
  core=$(_hive_memory_core_path)

  [[ -x "$release_bin" ]] || return 1
  mkdir -p "$(dirname "$core")"
  # Keep shdeps' release install authoritative, but expose dotfiles' launcher
  # as the PATH entry so agent-session context stays outside the upstream tool.
  command install -m 0755 "$release_bin" "$core"
  _hive_memory_link_launcher
}

uninstall() {
  rm -f "$(shdeps_bin_dir)/hm"
  rm -rf "$(_hive_memory_install_dir)"
}
