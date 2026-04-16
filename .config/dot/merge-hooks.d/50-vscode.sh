# shellcheck shell=bash
# Merge VS Code settings and keybindings from dotfiles into local config.
# Shared by dotbootstrap and dot (on pull).
# Requires jq.

# Strip // line comments from JSONC so jq can parse it.
# Uses [[:space:]] instead of \s for macOS BSD sed compatibility.
_strip_jsonc() {
  grep -v '^[[:space:]]*//' "$1" | jq --indent 4 '.'
}

# Merge VS Code keybindings from dotfiles into a local keybindings.json.
# Policy: dotfiles win on conflicts (same key+when, different command).
# Local-only keybindings (not in dotfiles) are preserved.
# Writes to a .tmp file first so the original is preserved on failure.
_merge_vscode_keybindings() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    _strip_jsonc "$src" >"$dst"
    return
  fi

  # Create clean JSON temp files (strip JSONC comments for jq)
  local src_clean dst_clean
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  trap 'rm -f "${src_clean:-}" "${dst_clean:-}"' RETURN

  if ! _strip_jsonc "$src" >"$src_clean" || ! _strip_jsonc "$dst" >"$dst_clean"; then
    _warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    return
  fi

  # Merge: all dotfiles entries first, then any local-only entries.
  # A keybinding's identity is its key+when pair.
  if ! jq -n --indent 4 --slurpfile s "$src_clean" --slurpfile d "$dst_clean" '
    ($s[0] | map({key: .key, when: (.when // "")})) as $skeys |
    $s[0] + [$d[0][] | select({key: .key, when: (.when // "")} as $k | $skeys | map(. == $k) | any | not)]
  ' >"$dst.tmp"; then
    _warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$dst.tmp"
  else
    mv "$dst.tmp" "$dst"
  fi
}

# Merge VS Code settings from dotfiles into a local settings.json.
# Policy: dotfiles win on conflicts (same key, different value).
# Local-only settings are preserved. Writes to .tmp first for safety.
_merge_vscode_settings() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    _strip_jsonc "$src" >"$dst"
    return
  fi

  # Create clean JSON temp files (strip JSONC comments for jq)
  local src_clean dst_clean
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  trap 'rm -f "${src_clean:-}" "${dst_clean:-}"' RETURN

  if ! _strip_jsonc "$src" >"$src_clean" || ! _strip_jsonc "$dst" >"$dst_clean"; then
    _warn "    warning: settings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    return
  fi

  # Merge: local settings * dotfiles settings (recursive merge, dotfiles win)
  # Using * instead of + so nested objects (like "[python]") are merged
  # recursively — local-only nested keys are preserved.
  if ! jq -n --indent 4 --slurpfile s "$src_clean" --slurpfile d "$dst_clean" \
    '$d[0] * $s[0]' >"$dst.tmp"; then
    _warn "    warning: settings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$dst.tmp"
  else
    mv "$dst.tmp" "$dst"
  fi
}

# Merge both settings and keybindings into a VS Code config dir.
# $1 = target config dir (e.g., ~/Library/Application Support/Code/User)
_merge_vscode_config() {
  # Settings (cross-platform)
  local settings_src="$HOME/.config/dot/merge-hooks.d/vscode-settings.json"
  if [[ -f "$settings_src" ]]; then
    _merge_vscode_settings "$settings_src" "$1/settings.json"
  fi

  # Keybindings: merge common first, then platform-specific
  local kb_common="$HOME/.config/dot/merge-hooks.d/vscode-keybindings.json"
  if [[ -f "$kb_common" ]]; then
    _merge_vscode_keybindings "$kb_common" "$1/keybindings.json"
  fi

  local kb_platform=""
  case "$(uname -s)" in
  Darwin) kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-mac.json" ;;
  Linux)
    if _is_wsl; then
      kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-windows.json"
    else
      kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-linux.json"
    fi
    ;;
  MINGW* | MSYS*) kb_platform="$HOME/.config/dot/merge-hooks.d/vscode-keybindings-windows.json" ;;
  esac
  if [[ -n "$kb_platform" && -f "$kb_platform" ]]; then
    _merge_vscode_keybindings "$kb_platform" "$1/keybindings.json"
  fi
}

# Ensure a local extension is registered in an extensions.json.
# Idempotent — skips if the extension ID is already present.
# $1 = extension ID (e.g., cgraf.term-notify-sound)
# $2 = extension dir name (e.g., term-notify-sound-0.0.1)
# $3 = extensions.json path
_ensure_vscode_extension() {
  local ext_id="$1" ext_dir="$2" ext_json="$3"
  [[ -f "$ext_json" ]] || return 0

  local ext_base
  ext_base="$(dirname "$ext_json")"
  [[ -d "$ext_base/$ext_dir" ]] || return 0

  # Already registered?
  if jq -e --arg id "$ext_id" 'map(.identifier.id) | index($id)' "$ext_json" >/dev/null 2>&1; then
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --arg id "$ext_id" --arg dir "$ext_dir" --arg path "$ext_base/$ext_dir" \
    '. + [{
      identifier: {id: $id},
      version: "0.0.1",
      location: {"\u0024mid": 1, path: $path, scheme: "file"},
      relativeLocation: $dir,
      metadata: {source: "local"}
    }]' "$ext_json" >"$tmp"; then
    mv "$tmp" "$ext_json"
  else
    rm -f "$tmp"
  fi
}

# Discover installed VS Code variants.  Each entry is a pair of
# tab-separated paths: extensions_dir<TAB>config_dir.  Only variants
# with a confirmed installation are included.
#
# On macOS, config dirs in ~/Library/Application Support persist after
# uninstall, so we check for the .app bundle instead.  On Linux, config
# dirs are only created by the app, so their presence is sufficient.
_vscode_variants() {
  local -a pairs=()
  case "$(uname -s)" in
  Darwin)
    local s="$HOME/Library/Application Support"
    # app_bundle<TAB>extensions_dir<TAB>config_dir
    local -a candidates=(
      "/Applications/Visual Studio Code.app	$HOME/.vscode/extensions	$s/Code/User"
      "/Applications/Visual Studio Code - Insiders.app	$HOME/.vscode-insiders/extensions	$s/Code - Insiders/User"
      "/Applications/VS Code @ FB.app	$HOME/.vscode-fb-mkt/extensions	$s/VS Code @ FB/User"
      "/Applications/VS Code @ FB - Insiders.app	$HOME/.vscode-fb-insiders-mkt/extensions	$s/VS Code @ FB - Insiders/User"
      "/Applications/Cursor.app	$HOME/.cursor/extensions	$s/Cursor/User"
    )
    local c app rest
    for c in "${candidates[@]}"; do
      app="${c%%	*}"
      rest="${c#*	}"
      [[ -d "$app" ]] && pairs+=("$rest")
    done
    ;;
  Linux)
    if _is_wsl; then
      local wa
      wa="$(wslpath "$(cmd.exe /C 'echo %APPDATA%' 2>/dev/null | tr -d '\r')" 2>/dev/null)" || true
      [[ -n "$wa" ]] && pairs=("$HOME/.vscode/extensions	$wa/Code/User")
    else
      pairs=(
        "$HOME/.vscode/extensions	$HOME/.config/Code/User"
        "$HOME/.vscode-insiders/extensions	$HOME/.config/Code - Insiders/User"
        "$HOME/.cursor/extensions	$HOME/.config/Cursor/User"
      )
    fi
    ;;
  MINGW* | MSYS*)
    pairs=("$HOME/.vscode/extensions	$APPDATA/Code/User")
    ;;
  esac

  local pair cfg
  for pair in "${pairs[@]}"; do
    cfg="${pair#*	}"
    [[ -d "$cfg" ]] && printf '%s\n' "$pair"
  done
}

# Main: deploy extensions, settings, and keybindings to all VS Code variants.
merge() {
  command -v jq &>/dev/null || return 0

  local -a variants=()
  local line
  while IFS= read -r line; do
    variants+=("$line")
  done < <(_vscode_variants)

  (( ${#variants[@]} > 0 )) || return 0

  # Deploy and register local extensions.
  # Source of truth: ~/.local/share/dot-vscode-extensions/<ext-dir>/
  local _ext_name="term-notify-sound-0.0.1"
  local _ext_src="$HOME/.local/share/dot-vscode-extensions/$_ext_name"
  local ext_dir cfg_dir
  if [[ -d "$_ext_src" ]]; then
    for line in "${variants[@]}"; do
      ext_dir="${line%%	*}"
      mkdir -p "$ext_dir"
      if [[ ! -e "$ext_dir/$_ext_name" ]]; then
        ln -sf "$_ext_src" "$ext_dir/$_ext_name"
      fi
      _ensure_vscode_extension "cgraf.term-notify-sound" "$_ext_name" "$ext_dir/extensions.json"
    done
  fi

  # Merge settings and keybindings.
  _log "  VS Code"
  for line in "${variants[@]}"; do
    cfg_dir="${line#*	}"
    _merge_vscode_config "$cfg_dir"
  done
}
