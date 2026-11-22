# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Copy WezTerm config into the Windows home when running under WSL.
# Keeps ~/.config/wezterm/wezterm.lua in dotfiles as the source of truth.

_wezterm_copy() {
  local src="$1" dest="$2" tmp

  # A directory or symlink to one makes mv put the temporary file inside
  # that directory instead of publishing the requested companion.
  [[ ! -e "$dest" || -f "$dest" ]] || return 1
  mkdir -p "$(dirname "$dest")" || return 1
  if [[ ! -L "$dest" && -e "$dest" ]] && dot_config_files_equal "$src" "$dest"; then
    return 0
  fi

  # Stage the complete replacement before touching the published dependency.
  # WezTerm may reload the main config while any companion file is copied.
  dot_sibling_tmp_for "$dest" || return 1
  tmp="$REPLY"
  cp "$src" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if [[ ! -L "$dest" && -e "$dest" ]]; then
    cp -p "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)" || {
      rm -f "$tmp"
      return 1
    }
  fi
  mv -f "$tmp" "$dest" || {
    rm -f "$tmp"
    return 1
  }
}

_wezterm_sync_lua_dir() (
  local src_dir="$1" dest_dir="$2"
  local manifest="$dest_dir/.dotfiles-managed"
  local new_manifest
  local src name old_name

  [[ ! -e "$manifest" || -f "$manifest" ]] || return 1
  [[ -d "$src_dir" || -f "$manifest" ]] || return 0

  mkdir -p "$dest_dir" || return 1
  dot_sibling_tmp_for "$manifest" || return 1
  new_manifest="$REPLY"
  trap 'rm -f "$new_manifest"' EXIT

  if [[ -d "$src_dir" ]]; then
    for src in "$src_dir"/*.lua; do
      [[ -f "$src" ]] || continue
      name="${src##*/}"
      _wezterm_copy "$src" "$dest_dir/$name" || return 1
      printf '%s\n' "$name" >>"$new_manifest" || return 1
    done
  fi

  if [[ -f "$manifest" ]]; then
    # The manifest contains only basenames this hook copied previously. That lets
    # overlay removals stop stale Windows-side hyperlink rules without touching
    # unrelated local files in the same directory.
    while IFS= read -r old_name; do
      case "$old_name" in
        "" | .* | */*) continue ;;
      esac
      if ! grep -Fxq -- "$old_name" "$new_manifest"; then
        rm -f "$dest_dir/$old_name" || return 1
      fi
    done <"$manifest"
  fi

  if [[ -s "$new_manifest" ]]; then
    mv "$new_manifest" "$manifest" || return 1
  else
    rm -f "$manifest" "$new_manifest" || return 1
    rmdir "$dest_dir" 2>/dev/null || true
  fi
)

_wezterm_required_asset() {
  local relative_path="$1"
  local src

  if ! src=$(dot_shdeps_dep_file cgraf78/termnav "$relative_path" 2>/dev/null) ||
    [[ ! -f "$src" || ! -r "$src" ]]; then
    dot_hook_warn "    warning: Windows WezTerm needs Termnav asset $relative_path"
    return 1
  fi
  printf '%s\n' "$src"
}

merge() {
  _dot_tool_present wezterm || return 0
  local config_dir="$HOME/.config/wezterm"
  local src="$config_dir/wezterm.lua"
  [[ -f "$src" ]] || return 0

  dot_hook_platform_match wsl || return 0

  dot_hook_log "  WezTerm"

  local winhome module routes rules
  # dot_wsl_writable_windows_home() both asks Windows which profile owns GUI
  # apps (instead of guessing from the Linux username) and refuses accounts
  # other than the one paired with that profile — see its definition. Windows
  # WezTerm's config lives at a single shared path regardless of which Linux
  # account writes it, so a second account (e.g. root) racing on the same
  # copy is how it gets corrupted.
  dot_wsl_writable_windows_home || return 0
  winhome="$REPLY"

  # The main config loads these immediately. Check their sources before
  # publishing any changes, including on a cold WSL install.
  for module in attention.lua link-routes.lua public-link-rules.lua termnav-module.lua; do
    if [[ ! -f "$config_dir/$module" || ! -r "$config_dir/$module" ]]; then
      dot_hook_warn "    warning: Windows WezTerm needs local module $module"
      return 1
    fi
  done
  routes=$(_wezterm_required_asset lib/termnav/wezterm/link-routes.lua) || return 1
  rules=$(_wezterm_required_asset lib/termnav/wezterm/public-link-rules.lua) || return 1

  # Windows WezTerm runs outside the WSL shell environment. Publish Shdeps
  # assets beside the Lua wrappers so they can load without a WSL lookup.
  _wezterm_copy "$HOME/.config/terminal/settings.json" "$winhome/.config/terminal/settings.json" || return 1
  _wezterm_copy "$routes" "$winhome/termnav-link-routes.lua" || return 1
  _wezterm_copy "$rules" "$winhome/termnav-public-link-rules.lua" || return 1

  # Windows WezTerm loads ~/.wezterm.lua, so wezterm.config_dir is the Windows
  # home. Publish all its companions before the primary file, which can
  # trigger an immediate reload.
  for module in "$config_dir"/*.lua; do
    [[ -f "$module" && "${module##*/}" != "wezterm.lua" ]] || continue
    _wezterm_copy "$module" "$winhome/${module##*/}" || return 1
  done

  _wezterm_sync_lua_dir \
    "$config_dir/hyperlink-rules.d" \
    "$winhome/hyperlink-rules.d" || return 1
  _wezterm_copy "$src" "$winhome/.wezterm.lua" || return 1

  # Older configs used the companion appearance file and the spinner frames.
  # Retire them only once the new main file is in place.
  rm -f "$winhome/appearance.json" "$winhome/.config/terminal/working-spinner.frames"
}
