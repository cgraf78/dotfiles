# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return

# shellcheck shell=bash
# Copy WezTerm config into the Windows home when running under WSL.
# Keeps ~/.config/wezterm/wezterm.lua in dotfiles as the source of truth.

if ! declare -F dot_sibling_tmp_for >/dev/null 2>&1; then
  _dot_wezterm_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../temp.sh disable=SC1091
  . "$_dot_wezterm_hook_dir/../temp.sh"
fi
if ! declare -F dot_wsl_windows_home >/dev/null 2>&1; then
  _dot_wezterm_hook_dir="${_dot_wezterm_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../windows.sh disable=SC1091
  . "$_dot_wezterm_hook_dir/../windows.sh"
fi

_wezterm_copy() {
  local src="$1" dest="$2" tmp

  mkdir -p "$(dirname "$dest")"

  if [[ -L "$dest" ]]; then
    rm -f "$dest"
  elif [[ -e "$dest" ]] && ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    mv "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)"
  fi

  if [[ ! -e "$dest" ]] || ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    dot_sibling_tmp_for "$dest" || return 1
    tmp="$REPLY"
    cp "$src" "$tmp" || {
      rm -f "$tmp"
      return 1
    }
    mv "$tmp" "$dest" || {
      rm -f "$tmp"
      return 1
    }
  fi
}

_wezterm_sync_lua_dir() {
  local src_dir="$1" dest_dir="$2"
  local manifest="$dest_dir/.dotfiles-managed"
  local new_manifest
  local src name old_name

  [[ -d "$src_dir" || -f "$manifest" ]] || return 0

  mkdir -p "$dest_dir"
  dot_sibling_tmp_for "$manifest" || return 1
  new_manifest="$REPLY"
  : >"$new_manifest"

  if [[ -d "$src_dir" ]]; then
    for src in "$src_dir"/*.lua; do
      [[ -f "$src" ]] || continue
      name="${src##*/}"
      _wezterm_copy "$src" "$dest_dir/$name"
      printf '%s\n' "$name" >>"$new_manifest"
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
        rm -f "$dest_dir/$old_name"
      fi
    done <"$manifest"
  fi

  if [[ -s "$new_manifest" ]]; then
    mv "$new_manifest" "$manifest" || {
      rm -f "$new_manifest"
      return 1
    }
  else
    rm -f "$manifest" "$new_manifest"
    rmdir "$dest_dir" 2>/dev/null || true
  fi
}

_wezterm_load_shdeps_assets() {
  declare -F dot_shdeps_dep_file >/dev/null 2>&1 && return 0

  local hook_dir
  hook_dir="${BASH_SOURCE[0]%/*}"
  [[ -r "$hook_dir/../shdeps-assets.sh" ]] || return 1
  # shellcheck source=../shdeps-assets.sh disable=SC1091
  . "$hook_dir/../shdeps-assets.sh"
  declare -F dot_shdeps_dep_file >/dev/null 2>&1
}

_wezterm_copy_shdeps_asset() {
  local relative_path="$1" dest="$2"
  local src

  src=$(dot_shdeps_dep_file cgraf78/termnav "$relative_path" 2>/dev/null || true)
  [[ -n "$src" ]] || return 0

  _wezterm_copy "$src" "$dest"
}

merge() {
  _dot_tool_present wezterm || return 0
  local config_dir="$HOME/.config/wezterm"
  local src="$config_dir/wezterm.lua"
  [[ -f "$src" ]] || return 0

  case "$(uname -s)" in
    Linux)
      _is_wsl || return 0
      ;;
    MINGW* | MSYS*)
      # On Windows-native shells, HOME is already the Windows home.
      return 0
      ;;
    *)
      return 0
      ;;
  esac

  dot_hook_log "  WezTerm"

  local winhome
  # dot_wsl_writable_windows_home() both asks Windows which profile owns GUI
  # apps (instead of guessing from the Linux username) and refuses accounts
  # other than the one paired with that profile — see its definition. Windows
  # WezTerm's config lives at a single shared path regardless of which Linux
  # account writes it, so a second account (e.g. root) racing on the same
  # copy is how it gets corrupted.
  dot_wsl_writable_windows_home || return 0
  winhome="$REPLY"

  _wezterm_copy "$src" "$winhome/.wezterm.lua"

  # Windows WezTerm loads ~/.wezterm.lua, so wezterm.config_dir is the Windows
  # home. Keep companion Lua modules beside that file or dofile(config_dir...)
  # fails even though the main config was copied correctly.
  local module
  for module in "$config_dir"/*.lua; do
    [[ -f "$module" && "${module##*/}" != "wezterm.lua" ]] || continue
    _wezterm_copy "$module" "$winhome/${module##*/}"
  done

  _wezterm_sync_lua_dir \
    "$config_dir/hyperlink-rules.d" \
    "$winhome/hyperlink-rules.d"

  if _wezterm_load_shdeps_assets; then
    # Windows WezTerm runs outside the WSL shell environment. Copy the
    # shdeps-resolved reusable modules beside their wrappers so the copied
    # config remains self-contained on the Windows side.
    _wezterm_copy_shdeps_asset \
      lib/termnav/wezterm/link-routes.lua \
      "$winhome/termnav-link-routes.lua"
    _wezterm_copy_shdeps_asset \
      lib/termnav/wezterm/public-link-rules.lua \
      "$winhome/termnav-public-link-rules.lua"
  fi
}
