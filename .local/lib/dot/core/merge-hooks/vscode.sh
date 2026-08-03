# shellcheck shell=bash
# Merge VS Code settings and keybindings from dotfiles into local config.
# Shared by dotbootstrap and dot (on pull).
# Requires jq.

if ! declare -F _merge_hook_source >/dev/null 2>&1; then
  _dot_vscode_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || return
  # shellcheck source=../merge-hooks.sh disable=SC1091
  . "$_dot_vscode_hook_dir/../merge-hooks.sh"
fi
if ! declare -F dot_wsl_windows_home >/dev/null 2>&1; then
  _dot_vscode_hook_dir="${_dot_vscode_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../windows.sh disable=SC1091
  . "$_dot_vscode_hook_dir/../windows.sh"
fi
if ! declare -F _dot_xdg_path >/dev/null 2>&1; then
  _dot_vscode_hook_dir="${_dot_vscode_hook_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}" || return
  # shellcheck source=../xdg.sh disable=SC1091
  . "$_dot_vscode_hook_dir/../xdg.sh"
fi

# Strip // line comments from JSONC so jq can parse it. Normalize transport
# bytes first because Settings Sync can move CRLF/BOM files across platforms;
# leaving a BOM attached to the first comment would make a valid source or
# synchronized destination fail parsing for a formatting-only reason.
_strip_jsonc() {
  LC_ALL=C awk '
    NR == 1 { sub(/^\357\273\277/, "", $0) }
    { sub(/\r$/, "", $0) }
    !/^[[:space:]]*\/\//
  ' "$1" | jq --indent 4 '.'
}

# Retirement history stays in source because there is no universally inert
# ownership field in a VS Code keybinding. Comments disappear during divergent
# Settings Sync merges, `when` participates in resolver implication, and `args`
# can change positive-command behavior. Exact source records are less clever
# and more durable: they alter no generated shortcut semantics at all.
_DOT_VSCODE_KEYBINDING_RETIRE='dotfiles.retire'
_DOT_VSCODE_KEYBINDING_RETIRE_PROOF='dotfiles.retire-proof'
_DOT_VSCODE_KEYBINDING_REVIEW_PROOF='review-build:7030e8e'
_DOT_VSCODE_KEYBINDING_LEGACY_PROOF='legacy-local:280f7f8'

_vscode_is_wsl() {
  if command -v _is_wsl >/dev/null 2>&1; then
    _is_wsl
    return
  fi

  [[ -n "${WSL_DISTRO_NAME:-}" || -n "${WSL_INTEROP:-}" ]]
}

_vscode_commit_tmp() {
  local tmp="$1" dst="$2" size

  if [[ -f "$dst" ]] && cmp -s -- "$tmp" "$dst"; then
    rm -f -- "$tmp"
    return 0
  fi

  if _vscode_is_wsl; then
    if ! command -v python3 >/dev/null 2>&1; then
      _warn "    warning: python3 unavailable for verified VS Code config write to $dst — leaving temp file"
      return 1
    fi

    # WSL writes to native Windows config files can report a successful rename
    # while leaving a short byte stream behind. Write through an already-open
    # handle, truncate only after all bytes are written, then verify the final
    # content before deleting the temp file.
    if python3 - "$tmp" "$dst" <<'PY'; then
import os
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src, "rb") as handle:
    expected = handle.read()

try:
    with open(dst, "rb") as handle:
        original = handle.read()
    existed = True
except FileNotFoundError:
    original = b""
    existed = False

def write_bytes(data):
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT, 0o666)
    try:
        view = memoryview(data)
        written = 0
        while written < len(view):
            written += os.write(fd, view[written:])
        os.ftruncate(fd, len(data))
        os.fsync(fd)
    finally:
        os.close(fd)

try:
    write_bytes(expected)
    with open(dst, "rb") as handle:
        actual = handle.read()
    if actual != expected:
        raise RuntimeError("destination did not match expected bytes after write")
except BaseException:
    try:
        if existed:
            write_bytes(original)
        else:
            os.unlink(dst)
    except BaseException:
        pass
    raise
PY
      rm -f -- "$tmp"
      return 0
    fi
    _warn "    warning: verified VS Code config write failed for $dst — leaving temp file"
    return 1
  fi

  # On NTFS via WSL, O_TRUNC at open time (shell redirect, cp) fails with
  # EACCES when another process holds the file open (e.g. VS Code watching
  # settings.json). mv -f avoids this by copying without O_TRUNC when it falls
  # back across filesystem boundaries, but that leaves stale trailing bytes
  # when the new content is shorter. Fix: record the expected size, let mv -f
  # write the bytes, then explicitly truncate via ftruncate() (SetEndOfFile on
  # Windows), which succeeds on an already-open write handle even when O_TRUNC
  # at open time is blocked.
  size=$(wc -c <"$tmp")
  if mv -f -- "$tmp" "$dst"; then
    truncate -s "$size" "$dst" 2>/dev/null || true
  else
    rm -f -- "$tmp"
    return 1
  fi
}

# Merge VS Code keybindings from dotfiles into a local keybindings.json.
# Policy: dotfiles win on key+when conflicts. Append-only, exact source
# retirement records identify old managed generations that can be removed,
# including bindings imported by Settings Sync from another machine. Genuinely
# local-only bindings retain their precedence. Keeping history in JSONC teaches
# this hook nothing about keys, commands, platforms, or Termnav behavior.
#
# Managed terminal tab routes are the exception to normal ordering: they must
# reach the pty ahead of stale local handlers with overlapping when clauses.
# Writes to a .tmp file first so the original is preserved on failure.
_merge_vscode_keybindings() {
  local src="$1" dst="$2"
  local out src_clean dst_clean
  mkdir -p "$(dirname "$dst")"

  # Normalize exactly one top-level array from each JSONC input. Accepting a
  # second JSON document would let a plausible-looking prefix hide corruption,
  # then silently discard retirement policy or bindings through $slurpfile[0].
  src_clean=$(mktemp)
  dst_clean=$(mktemp)
  trap 'rm -f "${src_clean:-}" "${dst_clean:-}"' RETURN

  if ! _strip_jsonc "$src" |
    jq -s -e \
      --arg retire "$_DOT_VSCODE_KEYBINDING_RETIRE" \
      --arg proof "$_DOT_VSCODE_KEYBINDING_RETIRE_PROOF" \
      --arg review_proof "$_DOT_VSCODE_KEYBINDING_REVIEW_PROOF" \
      --arg legacy_proof "$_DOT_VSCODE_KEYBINDING_LEGACY_PROOF" '
      def valid_binding:
        type == "object"
        and (.key | type == "string" and length > 0)
        and (.command | type == "string" and length > 0)
        and ((has("when") | not) or (.when | type == "string"))
        and (
          (has($retire) | not)
          or .[$retire] == true
        )
        and (
          (has($proof) | not)
          or (
            .[$retire] == true
            and (
              .[$proof] == $review_proof
              or .[$proof] == $legacy_proof
            )
          )
        );

      if length == 1
        and (.[0] | type == "array")
        and all(.[0][]; valid_binding)
      then .[0]
      else error("expected one valid keybinding array")
      end
    ' \
      >"$src_clean"; then
    _warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    return 1
  fi

  if [[ -f "$dst" ]]; then
    if ! _strip_jsonc "$dst" |
      jq -s -e 'if length == 1 and (.[0] | type == "array") then .[0] else error("expected one array") end' \
        >"$dst_clean"; then
      _warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
      return 1
    fi
  else
    printf '[]\n' >"$dst_clean"
  fi

  # Current key+when conflicts and exact retirement records are source-owned
  # policy. A changed or deleted binding keeps its former exact object in the
  # JSONC history, allowing machines to skip releases without stranding an
  # intermediate generation synchronized from elsewhere. "Exact" deliberately
  # includes args and any additional properties: a near-match may be a user's
  # independent binding, so broad key/command heuristics are not safe deletion
  # authority.
  # VS Code resolves equal-weight user bindings from the bottom up, so keep only
  # the managed terminal tab routes after preserved local entries; unrelated
  # local overrides retain the existing source-first precedence.
  _merge_hook_tmp_for "$dst" || return 1
  out="$REPLY"
  if ! jq -n --indent 4 --sort-keys \
    --arg retire "$_DOT_VSCODE_KEYBINDING_RETIRE" \
    --arg proof "$_DOT_VSCODE_KEYBINDING_RETIRE_PROOF" \
    --slurpfile s "$src_clean" \
    --slurpfile d "$dst_clean" '
    def terminal_tab_route:
      .command == "workbench.action.terminal.sendSequence"
      and .when == "terminalFocus"
      and (.key == "ctrl+tab" or .key == "ctrl+shift+tab");

    ($s[0] | map(select(.[$retire] != true))) as $active |
    ($s[0] | map(select(.[$retire] == true) | del(.[$retire], .[$proof]))) as $retired |
    ($active | map({key: .key, when: (.when // "")})) as $skeys |
    # Current managed entries come first, matching the historical merge
    # policy. A local key+when conflict is removed even when its command
    # differs because VS Code would otherwise resolve two definitions for the
    # same shortcut condition.
    ($active | map(select(terminal_tab_route | not)))
    + [
      $d[0][]
      | select(
          ({key: .key, when: (.when // "")} as $key_when
            | $skeys | map(. == $key_when) | any | not)
          and
          (. as $binding
            | $retired | map(. == $binding) | any | not)
        )
    ]
    + ($active | map(select(terminal_tab_route)))
  ' >"$out"; then
    _warn "    warning: keybindings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$out"
    return 1
  fi

  _vscode_commit_tmp "$out" "$dst"
}

# Merge VS Code settings from dotfiles into a local settings.json.
# Policy: dotfiles win on conflicts (same key, different value).
# Local-only settings are preserved. Writes to .tmp first for safety.
_merge_vscode_settings() {
  local src="$1" dst="$2" out
  mkdir -p "$(dirname "$dst")"

  # No existing file — just copy (stripping comments)
  if [[ ! -f "$dst" ]]; then
    _merge_hook_tmp_for "$dst" || return 1
    out="$REPLY"
    if _strip_jsonc "$src" | jq --indent 4 --sort-keys '.' >"$out"; then
      _vscode_commit_tmp "$out" "$dst"
    else
      rm -f "$out"
      return 1
    fi
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
  _merge_hook_tmp_for "$dst" || return 1
  out="$REPLY"
  if ! jq -n --indent 4 --sort-keys --slurpfile s "$src_clean" --slurpfile d "$dst_clean" \
    '$d[0] * $s[0]' >"$out"; then
    _warn "    warning: settings merge failed for $(basename "$(dirname "$(dirname "$dst")")") — skipping"
    rm -f "$out"
  else
    _vscode_commit_tmp "$out" "$dst"
  fi
}

_vscode_checkrun_capabilities() {
  local out="$1"

  printf '{}\n' >"$out"
  command -v checkrun >/dev/null 2>&1 || return 0
  checkrun capabilities --json >"$out" 2>/dev/null || printf '{}\n' >"$out"
}

_vscode_checkrun_schema_config() {
  local out="$1" schema_policy

  printf '{}\n' >"$out"
  if command -v shdeps >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    schema_policy=$(shdeps dep-file cgraf78/checkrun lib/checkrun/schemas/schema_policy.py 2>/dev/null || true)
    if [[ -n "$schema_policy" && -f "$schema_policy" ]]; then
      # Checkrun owns schema association matching for hooks, CLI diagnostics,
      # and editors. Project that public LSP surface into VS Code settings here
      # rather than duplicating schema globs in dotfiles.
      python3 "$schema_policy" --lsp-schemas --editor-sources >"$out" 2>/dev/null || printf '{}\n' >"$out"
    fi
  fi
}

_vscode_write_checkrun_settings() {
  local cap="$1" schema_config="$2" include_sley="$3" out="$4"

  jq --indent 4 \
    --arg include_sley "$include_sley" \
    --slurpfile schema_config "$schema_config" '
    def first_mapped_language($language_map; $ft):
      first(($language_map[$ft] // [$ft])[] | select(type == "string" and length > 0));

    def mapped_languages($language_map; $ft):
      ($language_map[$ft] // [$ft])[] | select(type == "string" and length > 0);

    def custom_associations($language_map):
      (.filetypes.custom // {}) as $custom |
      (
        [($custom.extension // {}) | to_entries[] | {
          key: ("*." + .key),
          value: first_mapped_language($language_map; .value)
        }]
        + [($custom.filename // {}) | to_entries[] | {
          key: .key,
          value: first_mapped_language($language_map; .value)
        }]
        + [($custom.patterns // [])[] | select(.pattern? and .filetype?) | {
          key: .pattern,
          value: first_mapped_language($language_map; .filetype)
        }]
      )
      | map(select(.value != null))
      | unique_by(.key)
      | from_entries;

    def json_schemas:
      ($schema_config[0].json // [])
      | map(select(type == "object")
        | .fileMatch = ((.fileMatch // [])
          | map(select(type == "string" and (startswith("/") | not)))))
      | map(select((.fileMatch // []) | length > 0));

    def yaml_schemas:
      ($schema_config[0].yaml // {})
      | select(type == "object")
      | with_entries(
        .value = ((.value // [])
          | map(select(type == "string" and (startswith("/") | not))))
        | select((.value // []) | length > 0)
      );

    def toml_schema_associations:
      ($schema_config[0].toml // {})
      | select(type == "object")
      | with_entries(select(.key | startswith("^/") | not));

    def sley_formatter_settings($language_map):
      ([(.filetypes.format // [])[] | mapped_languages($language_map; .)]
      | unique
      | reduce .[] as $language ({};
        .["[" + $language + "]"] = {
          "editor.defaultFormatter": "cgraf.sley-tools",
          "editor.formatOnSave": true
        }
      ));

    (.editorLanguageIds.vscode // {}) as $language_map |
    (if $include_sley == "1" then sley_formatter_settings($language_map) else {} end)
    + (custom_associations($language_map) as $assoc |
      if ($assoc | length) > 0 then
        {"files.associations": $assoc}
      else
        {}
      end)
    + (json_schemas as $json |
      if ($json | length) > 0 then
        {"json.schemas": $json}
      else
        {}
      end)
    + (yaml_schemas as $yaml |
      if ($yaml | length) > 0 then
        {"yaml.schemas": $yaml}
      else
        {}
      end)
    + (toml_schema_associations as $toml |
      if ($toml | length) > 0 then
        {"evenBetterToml.schema.associations": $toml}
      else
        {}
      end)
  ' "$cap" >"$out"
}

# Generate VS Code language and schema settings from Checkrun-owned capability
# and schema projections. Checkrun owns the filetype-to-editor language aliases;
# keeping this hook as a projection prevents VS Code settings from growing a
# second copy of language policy.
_vscode_checkrun_settings() {
  local out="$1" include_sley="${2:-1}"
  printf '{}\n' >"$out"

  command -v checkrun >/dev/null 2>&1 || return 0

  local cap schemas tmp
  cap=$(mktemp)
  schemas=$(mktemp)
  tmp=$(mktemp)

  _vscode_checkrun_capabilities "$cap"
  if ! jq -e '.filetypes | type == "object"' "$cap" >/dev/null 2>&1; then
    rm -f "$cap" "$schemas" "$tmp"
    return 0
  fi
  _vscode_checkrun_schema_config "$schemas"

  if _vscode_write_checkrun_settings "$cap" "$schemas" "$include_sley" "$tmp"; then
    _vscode_commit_tmp "$tmp" "$out"
  else
    rm -f "$tmp"
    printf '{}\n' >"$out"
  fi
  rm -f "$cap" "$schemas" "$tmp"
}

_vscode_sley_settings() {
  _vscode_checkrun_settings "$1" 1
}

_remove_vscode_generated_checkrun_settings() {
  local settings="$1"
  [[ -f "$settings" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --sort-keys '
    # These settings are complete projections from Checkrun schema policy.
    # Recursive settings merges preserve unknown nested object keys, which is
    # right for hand-written user settings but wrong for generated machine-local
    # fileMatch and file:// schema paths. Drop the old projection before writing
    # the current machine projection so VS Code Settings Sync cannot leave a
    # trail of /Users, /home, and /root entries behind.
    del(.["json.schemas"])
    | del(.["yaml.schemas"])
    | del(.["evenBetterToml.schema.associations"])
  ' "$settings" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$settings"
  else
    rm -f "$tmp"
    return 1
  fi

  _remove_vscode_sley_settings "$settings"
}

_vscode_host_label() {
  if [[ -n "${DOT_TEST_VSCODE_HOSTNAME:-}" ]]; then
    printf '%s\n' "$DOT_TEST_VSCODE_HOSTNAME"
    return 0
  fi

  local host=""
  if command -v hostname >/dev/null 2>&1; then
    host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
  fi
  host="${host%%.*}"
  host="${host%$'\r'}"

  if [[ -n "$host" ]]; then
    printf '%s\n' "$host"
  else
    printf 'unknown\n'
  fi
}

_vscode_window_title_settings() {
  local out="$1" host
  host="$(_vscode_host_label)"

  jq -n --indent 4 --arg host "$host" '
    {
      "window.title": (
        $host
        + "${separator}${activeRepositoryBranchName}${separator}${rootNameShort}${separator}${activeEditorShort}"
      )
    }
  ' >"$out"
}

_merge_vscode_window_title() {
  local dst="$1" title_settings rc

  title_settings=$(mktemp)
  if _vscode_window_title_settings "$title_settings"; then
    _merge_vscode_settings "$title_settings" "$dst"
    rc=$?
  else
    rm -f "$title_settings"
    return 1
  fi
  rm -f "$title_settings"
  return "$rc"
}

_vscode_mcp_auth_token_path() {
  _dot_xdg_path state "dot/vscode-mcp-auth-token"
}

# Only variants that can actually run nabheet.vscode-ide-mcp (declared under
# editor = "vscode" in the extension manifest family) should receive the
# secret. Cursor variants share this file's discovery/merge plumbing but never
# install that extension, so writing the token there is pure unnecessary secret
# exposure.
# Path substring matching mirrors how _vscode_variants() already identifies
# Cursor (".cursor/extensions", "Cursor/User", ".cursor-server").
_vscode_mcp_auth_applicable() {
  case "$1" in
    *[Cc]ursor*) return 1 ;;
    *) return 0 ;;
  esac
}

# Both openssl and the /dev/urandom fallback must produce non-empty output to
# count as success; a broken openssl invocation (nonzero exit, empty stdout)
# falls through to /dev/urandom instead of failing outright.
_vscode_mcp_auth_generate_token() {
  local token
  if command -v openssl >/dev/null 2>&1; then
    token="$(openssl rand -hex 32 2>/dev/null)" || token=""
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  fi
  if [[ -r /dev/urandom ]]; then
    token="$(od -An -tx1 -N32 /dev/urandom | tr -d ' \n')"
    if [[ -n "$token" ]]; then
      printf '%s\n' "$token"
      return 0
    fi
  fi
  return 1
}

# A crash or disk-full mid-write can leave a short, non-empty, garbage token
# that a bare non-empty check would accept forever. Both generators always
# emit exactly 64 lowercase hex chars, so anything else is corrupt and
# triggers regeneration rather than silently persisting a weak secret.
_vscode_mcp_auth_token_is_valid() {
  local path="$1" contents
  [[ -s "$path" ]] || return 1
  contents="$(<"$path")"
  [[ "$contents" =~ ^[0-9a-f]{64}$ ]]
}

# mkdir is atomic on every POSIX filesystem this repo targets, so it doubles
# as a lock: only one racer can mkdir the same path. A lock left behind by a
# killed/crashed dot update (Ctrl-C, SSH drop, suspend mid-run) would
# otherwise wedge every future run behind it forever, so anything older than
# a minute is treated as abandoned and cleared.
_vscode_mcp_auth_lock_stale() {
  local lock="$1" mtime now
  mtime=$(stat -c '%Y' "$lock" 2>/dev/null || stat -f '%m' "$lock" 2>/dev/null) || return 1
  now=$(date +%s)
  ((now - mtime > 60))
}

# Bearer token for the vscode-ide-mcp extension's local HTTP server, which
# otherwise accepts unauthenticated requests (it treats a missing Origin
# header as a trusted non-browser client). Generated once per machine and
# persisted outside the dotfiles tree so `dot update` keeps re-applying the
# same value without ever committing a secret. This mirrors the
# bearer_token_env_var pattern in codex/config.d: dotfiles own the
# policy of setting a token, not the token itself.
#
# Both first-run creation and corrupt-file recovery are racy across
# concurrent `dot update` invocations (e.g. cron + interactive), so the
# whole generate-and-install step runs inside an mkdir-based mutex: whichever
# process gets the lock first writes the token, and every other racer
# re-checks validity after acquiring (or timing out on) the lock and adopts
# whatever is actually on disk rather than blindly writing its own value —
# otherwise different settings.json files could end up with different
# tokens depending on which process's write landed last.
_vscode_mcp_auth_token() {
  local path
  _vscode_mcp_auth_token_path || return 1
  path="$REPLY"

  if ! _vscode_mcp_auth_token_is_valid "$path"; then
    mkdir -p "$(dirname "$path")" || return 1
    local lock="$path.lock" attempt=0 acquired=1
    until mkdir "$lock" 2>/dev/null; do
      if _vscode_mcp_auth_lock_stale "$lock"; then
        rmdir "$lock" 2>/dev/null
        continue
      fi
      attempt=$((attempt + 1))
      # Give up waiting after ~2s and proceed unlocked rather than hang
      # forever; the only cost is reopening the same narrow race this lock
      # exists to close, not a broken merge. Do NOT rmdir below in this
      # case — the lock is still held by whoever we're waiting on, and
      # removing it out from under them would break their own mutex.
      if ((attempt >= 20)); then
        acquired=0
        break
      fi
      sleep 0.1
    done

    if ! _vscode_mcp_auth_token_is_valid "$path"; then
      local token tmp
      token="$(_vscode_mcp_auth_generate_token)"
      if [[ -n "$token" ]] && _merge_hook_tmp_for "$path"; then
        tmp="$REPLY"
        if (umask 077 && printf '%s\n' "$token" >"$tmp"); then
          mv -f "$tmp" "$path"
        else
          rm -f "$tmp"
        fi
      fi
    fi
    ((acquired)) && rmdir "$lock" 2>/dev/null
  fi

  _vscode_mcp_auth_token_is_valid "$path" || return 1
  REPLY="$(<"$path")"
}

_vscode_mcp_auth_settings() {
  local out="$1"
  printf '{}\n' >"$out"

  if ! _vscode_mcp_auth_token; then
    _warn "    warning: could not generate vscode-mcp-server auth token — nabheet.vscode-ide-mcp will run unauthenticated on 127.0.0.1 until this is resolved"
    return 0
  fi
  jq -n --indent 4 --arg token "$REPLY" '{"vscode-mcp-server.authToken": $token}' >"$out"
}

_merge_vscode_mcp_auth() {
  local dst="$1" auth_settings rc
  _vscode_mcp_auth_applicable "$dst" || return 0
  auth_settings=$(mktemp)
  if _vscode_mcp_auth_settings "$auth_settings"; then
    _merge_vscode_settings "$auth_settings" "$dst"
    rc=$?
  else
    rm -f "$auth_settings"
    return 1
  fi
  rm -f "$auth_settings"
  return "$rc"
}

_remove_vscode_sley_settings() {
  local settings="$1"
  [[ -f "$settings" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --sort-keys '
    with_entries(
      if ((.key | test("^\\[.*\\]$")) and (.value | type == "object") and
          .value["editor.defaultFormatter"] == "cgraf.sley-tools") then
        .value |= del(.["editor.defaultFormatter"])
        | .value |= (if .["editor.formatOnSave"] == true then del(.["editor.formatOnSave"]) else . end)
      else
        .
      end
    )
    | with_entries(select(
        ((.key | test("^\\[.*\\]$")) | not) or
        (.value | type != "object") or
        ((.value | length) > 0)
      ))
  ' "$settings" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$settings"
  else
    rm -f "$tmp"
  fi
}

_vscode_opts_contains() {
  local opts="$1" wanted="$2"
  case ",$opts," in
    *",$wanted,"*) return 0 ;;
    *) return 1 ;;
  esac
}

_vscode_settings_sources() {
  # The settings family keeps VS Code's native JSON shape per fragment while
  # centralizing ordering and optional .replace behavior in dot core. This hook
  # only cares that it receives an ordered stream of JSON settings layers.
  _merge_hook_family_files_matching vscode/settings.d '*.json' '*.replace/*.json'
}

# Print the stable platform key used by keybinding families.
_vscode_keybinding_platform() {
  # _vscode_platform is the canonical host classifier used by variant
  # selection. Map its display vocabulary once so family paths cannot drift
  # into an independent uname/WSL policy.
  case "$(_vscode_platform)" in
    Darwin) printf 'macos\n' ;;
    Linux) printf 'linux\n' ;;
    WSL | Windows) printf 'windows\n' ;;
    *) return 1 ;;
  esac
}

# Print the keybinding families that apply to the current platform.
#
# Keybindings have two independent policies: the shared family mechanism orders
# fragments inside a family, while this hook still owns VS Code's platform
# split. Keeping the platform choice here avoids turning dot core family names
# into semantic concepts like mac/windows/linux.
#
# Args: $1 = optional stable platform key
#       $2 = optional comma-separated variant options
# Returns merge-hook family names on stdout: common, enabled capabilities, then
# platform-specific policy.
_vscode_keybinding_families() {
  local platform="${1:-}" opts="${2:-}"
  if [[ -z "$platform" ]]; then
    platform=$(_vscode_keybinding_platform) || return 1
  fi

  printf '%s\n' vscode/keybindings/all.d
  if ! _vscode_opts_contains "$opts" "no-termnav"; then
    printf '%s\n' vscode/keybindings/termnav.d
  fi
  printf 'vscode/keybindings/%s.d\n' "$platform"
}

# Merge both settings and keybindings into a VS Code config dir.
# $1 = target config dir (e.g., ~/Library/Application Support/Code/User)
# $2 = optional comma-separated variant options.
_merge_vscode_config() {
  local cfg_dir="$1" opts="${2:-}"

  local settings_src
  while IFS= read -r settings_src; do
    _merge_vscode_settings "$settings_src" "$cfg_dir/settings.json"
  done < <(_vscode_settings_sources)

  local checkrun_settings
  checkrun_settings=$(mktemp)
  if _vscode_opts_contains "$opts" "no-sley"; then
    _vscode_checkrun_settings "$checkrun_settings" 0
    _remove_vscode_generated_checkrun_settings "$cfg_dir/settings.json"
    _merge_vscode_settings "$checkrun_settings" "$cfg_dir/settings.json"
    _remove_vscode_sley_settings "$cfg_dir/settings.json"
  else
    _vscode_checkrun_settings "$checkrun_settings" 1
    _remove_vscode_generated_checkrun_settings "$cfg_dir/settings.json"
    _merge_vscode_settings "$checkrun_settings" "$cfg_dir/settings.json"
  fi
  rm -f "$checkrun_settings"
  _merge_vscode_window_title "$cfg_dir/settings.json"
  _merge_vscode_mcp_auth "$cfg_dir/settings.json"

  # Aggregate every applicable source before reconciliation. This keeps
  # two current fragments with the same action but distinct conditions from
  # mistaking each other for stale output, while preserving the existing
  # later-fragment-first output precedence.
  local kb_family kb_source kb_layer kb_aggregate kb_next kb_platform
  kb_platform=$(_vscode_keybinding_platform) || return 1
  kb_aggregate=$(mktemp)
  printf '[]\n' >"$kb_aggregate"
  while IFS= read -r kb_family; do
    while IFS= read -r kb_source; do
      kb_layer=$(mktemp)
      kb_next=$(mktemp)
      if ! _strip_jsonc "$kb_source" |
        jq -s -e 'if length == 1 and (.[0] | type == "array") then .[0] else error("expected one array") end' \
          >"$kb_layer" ||
        ! jq -n --slurpfile layer "$kb_layer" --slurpfile current "$kb_aggregate" \
          '$layer[0] + $current[0]' >"$kb_next"; then
        rm -f "$kb_layer" "$kb_next" "$kb_aggregate"
        _warn "    warning: keybindings source aggregation failed for $cfg_dir — skipping"
        return 1
      fi
      if ! mv -f -- "$kb_next" "$kb_aggregate"; then
        rm -f "$kb_layer" "$kb_next" "$kb_aggregate"
        _warn "    warning: keybindings source aggregation failed for $cfg_dir — skipping"
        return 1
      fi
      rm -f "$kb_layer"
    done < <(_merge_hook_family_files_matching "$kb_family" '*.jsonc' '*.replace/*.jsonc')
  done < <(_vscode_keybinding_families "$kb_platform" "$opts")
  if ! _merge_vscode_keybindings \
    "$kb_aggregate" \
    "$cfg_dir/keybindings.json" \
    "$kb_platform"; then
    rm -f "$kb_aggregate"
    return 1
  fi
  rm -f "$kb_aggregate"
}

# Ensure a local extension is registered in an extensions.json.
# Existing local entries are refreshed so path corrections take effect.
# $1 = extension ID (e.g., cgraf.sley-tools)
# $2 = extension dir name (e.g., sley-tools-0.0.1)
# $3 = extensions.json path
# $4 = optional location.path override
_ensure_vscode_extension() {
  local ext_id="$1" ext_dir="$2" ext_json="$3" location_path="${4:-}"

  local ext_base ext_version
  ext_base="$(dirname "$ext_json")"
  mkdir -p "$ext_base"
  [[ -d "$ext_base/$ext_dir" ]] || return 0
  [[ -n "$location_path" ]] || location_path="$ext_base/$ext_dir"
  ext_version=$(jq -r '.version // empty | select(type == "string")' \
    "$ext_base/$ext_dir/package.json" 2>/dev/null || true)
  [[ -n "$ext_version" ]] || ext_version="0.0.1"

  if [[ ! -f "$ext_json" ]]; then
    printf '[]\n' >"$ext_json"
  fi

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --arg id "$ext_id" --arg dir "$ext_dir" \
    --arg path "$location_path" --arg version "$ext_version" '
    def local_extension_entry: {
      identifier: {id: $id},
      version: $version,
      location: {"\u0024mid": 1, path: $path, scheme: "file"},
      relativeLocation: $dir,
      metadata: {source: "local"}
    };

    if any(.[]; (.identifier.id // "") == $id) then
      map(if (.identifier.id // "") == $id then local_extension_entry else . end)
    else
      . + [local_extension_entry]
    end
  ' "$ext_json" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$ext_json"
  else
    rm -f "$tmp"
  fi
}

_remove_vscode_extension() {
  local ext_id="$1" ext_dir="$2" ext_json="$3"

  local ext_base
  ext_base="$(dirname "$ext_json")"
  if [[ -L "$ext_base/$ext_dir" ]]; then
    rm -f "$ext_base/$ext_dir"
  fi

  [[ -f "$ext_json" ]] || return 0

  local tmp
  tmp=$(mktemp)
  if jq --indent 4 --arg id "$ext_id" \
    'map(select((.identifier.id // "") != $id))' "$ext_json" >"$tmp"; then
    _vscode_commit_tmp "$tmp" "$ext_json"
  else
    rm -f "$tmp"
  fi
}

# Remove older symlinked generations of one dot-managed local extension. Limit
# ownership to links whose name and target stay under the declared source
# family, which also identifies a managed generation after its target vanishes
# without claiming same-ID development links elsewhere.
_prune_vscode_extension_versions() {
  local ext_id="$1" managed_source="$2" keep_dir="$3" ext_json="$4"
  local ext_base managed_parent extension_name
  local candidate candidate_dir target target_dir target_name version_suffix
  ext_base="$(dirname "$ext_json")"
  managed_parent="$(dirname "$managed_source")"
  extension_name="${ext_id#*.}"

  for candidate in "$ext_base"/*; do
    [[ -L "$candidate" ]] || continue
    candidate_dir="${candidate##*/}"
    [[ -z "$keep_dir" || "$candidate_dir" != "$keep_dir" ]] || continue
    target=$(readlink "$candidate") || continue
    [[ "$target" == /* ]] || target="$ext_base/$target"
    target_dir="$(dirname "$target")"
    target_name="${target##*/}"
    [[ "$target_dir" == "$managed_parent" ]] || continue
    [[ "$candidate_dir" == "$target_name" ]] || continue
    # Broken managed generations no longer have package metadata, so the name
    # is the remaining ownership proof. Require the complete suffix to be a
    # dotted semver (with optional prerelease/build tails); a first-digit check
    # would still claim a sibling such as termnav-2-tools-*.
    if [[ "$target_name" != "$extension_name" ]]; then
      [[ "$target_name" == "${extension_name}-"* ]] || continue
      version_suffix="${target_name#"$extension_name"-}"
      [[ "$version_suffix" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)*$ ]] || continue
    fi
    rm -f "$candidate"
  done
}

# Remove dot-managed local extensions whose source has been retired. A deleted
# source leaves the installed symlink dangling; metadata.source distinguishes
# these registrations from gallery extensions without claiming ownership of
# unrelated local directories.
_prune_vscode_local_extensions() {
  local ext_json="$1" ext_base ext_id ext_dir
  [[ -f "$ext_json" ]] || return 0

  ext_base="$(dirname "$ext_json")"
  while IFS=$'\t' read -r ext_id ext_dir; do
    [[ -n "$ext_id" && -n "$ext_dir" ]] || continue
    [[ "$ext_dir" == "${ext_dir##*/}" && "$ext_dir" != "." && "$ext_dir" != ".." ]] || continue
    if [[ -L "$ext_base/$ext_dir" && ! -e "$ext_base/$ext_dir" ]]; then
      _remove_vscode_extension "$ext_id" "$ext_dir" "$ext_json"
    fi
  done < <(jq -r '.[] | select(.metadata.source == "local") |
    [(.identifier.id // ""), (.relativeLocation // "")] | @tsv' "$ext_json")
}

_vscode_wsl_appdata_dirs() {
  # Every Linux account on this WSL distro can ask Windows for the same
  # profile. Only the account paired with it (dot_wsl_is_paired_windows_account)
  # may resolve it here — checked first, ahead of the test overrides below, so
  # DOT_TEST_WINDOWS_APPDATA can't be used to bypass it in tests either.
  dot_wsl_is_paired_windows_account || return 0

  if [[ -n "${DOT_TEST_WINDOWS_APPDATA:-}" ]]; then
    printf '%s\n' "$DOT_TEST_WINDOWS_APPDATA"
    return 0
  fi

  if [[ "${DOT_TEST:-0}" = 1 ]]; then
    # WSL exposes the real Windows profile even when tests replace HOME.
    # Tests must opt in with DOT_TEST_WINDOWS_APPDATA to avoid host writes.
    return 0
  fi

  # Query %APPDATA% directly rather than deriving it from
  # dot_wsl_windows_home()'s USERPROFILE (as WezTerm does): a profile with
  # Windows folder redirection can have %APPDATA% pointed somewhere other
  # than %USERPROFILE%\AppData\Roaming, and VS Code itself follows %APPDATA%.
  local cmd_appdata=""
  if command -v cmd.exe >/dev/null 2>&1; then
    cmd_appdata="$(cmd.exe /C 'echo %APPDATA%' </dev/null 2>/dev/null | tr -d '\r')" || true
  elif [[ -x /mnt/c/Windows/System32/cmd.exe ]]; then
    cmd_appdata="$(/mnt/c/Windows/System32/cmd.exe /C 'echo %APPDATA%' </dev/null 2>/dev/null | tr -d '\r')" || true
  fi
  if [[ -n "$cmd_appdata" && "$cmd_appdata" != "." ]]; then
    local converted
    converted="$(wslpath "$cmd_appdata" 2>/dev/null)" || true
    if [[ -n "$converted" && "$converted" == */AppData/Roaming ]]; then
      printf '%s\n' "$converted"
      return 0
    fi
  fi
}

_vscode_applications_dir() {
  printf '%s\n' "${DOT_TEST_VSCODE_APPLICATIONS_DIR:-/Applications}"
}

# Expand path fragments in variant data files without evaluating arbitrary shell.
_vscode_expand_path() {
  local path="$1"
  local app_ref="\${VSCODE_APPLICATIONS_DIR}"
  local app_dir
  app_dir="$(_vscode_applications_dir)"
  path="${path//"$app_ref"/$app_dir}"
  path="${path//\$VSCODE_APPLICATIONS_DIR/$app_dir}"

  local appdata_ref="\${APPDATA}"
  if [[ "$path" == *"$appdata_ref"* || "$path" == *"\$APPDATA"* ]]; then
    [[ -n "${APPDATA:-}" ]] || {
      printf '\n'
      return 0
    }
    path="${path//"$appdata_ref"/$APPDATA}"
    path="${path//\$APPDATA/$APPDATA}"
  fi

  local braced_home="\${HOME}"
  if [[ "$path" == "$braced_home" ]]; then
    printf '%s\n' "$HOME"
    return 0
  fi
  if [[ "$path" == "$braced_home/"* ]]; then
    printf '%s/%s\n' "$HOME" "${path:$((${#braced_home} + 1))}"
    return 0
  fi

  case "$path" in
    "" | "-") printf '\n' ;;
    \$HOME) printf '%s\n' "$HOME" ;;
    \$HOME/*) printf '%s/%s\n' "$HOME" "${path#\$HOME/}" ;;
    # \~ (escaped) keeps this a literal-tilde pattern. An unescaped ~ here
    # would undergo bash's own tilde expansion to the current $HOME before
    # matching, so it would also match any already-absolute path that simply
    # happens to live under $HOME (e.g. "$HOME/.vscode/extensions" written
    # out literally) and double-prefix it with $HOME again.
    \~) printf '%s\n' "$HOME" ;;
    \~/*) printf '%s/%s\n' "$HOME" "${path#\~/}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}

_vscode_platform() {
  case "$(uname -s)" in
    Darwin) printf 'Darwin\n' ;;
    Linux)
      if _vscode_is_wsl; then
        printf 'WSL\n'
      else
        printf 'Linux\n'
      fi
      ;;
    MINGW* | MSYS*) printf 'Windows\n' ;;
    *) printf '%s\n' "$(uname -s)" ;;
  esac
}

_vscode_platform_matches() {
  local wanted="$1" current="$2"
  [[ "$wanted" == "*" || "$wanted" == "$current" ]]
}

_vscode_substitute_wsl_appdata() {
  local value="$1" appdata="$2"
  local appdata_ref="\${WSL_APPDATA}"
  value="${value//"$appdata_ref"/$appdata}"
  value="${value//\$WSL_APPDATA/$appdata}"
  printf '%s\n' "$value"
}

_vscode_variant_uses_wsl_appdata() {
  local braced_wsl_appdata="\${WSL_APPDATA}"
  local plain_wsl_appdata="\$WSL_APPDATA"
  case "$1	$2	$3" in
    *"$braced_wsl_appdata"* | *"$plain_wsl_appdata"*) return 0 ;;
    *) return 1 ;;
  esac
}

_vscode_record_variant() {
  local marker="$1" ext_dir="$2" cfg_dir="$3" opts="${4:-}"
  marker="$(_vscode_expand_path "$marker")"
  ext_dir="$(_vscode_expand_path "$ext_dir")"
  cfg_dir="$(_vscode_expand_path "$cfg_dir")"

  [[ -n "$marker" && -e "$marker" ]] || return 0
  [[ -n "$ext_dir" ]] || return 0

  # Config-bearing variants are active only after the app has created its user
  # config dir. Extension-only variants, such as remote VS Code server profiles,
  # are active when their extension dir already exists.
  if [[ -n "$cfg_dir" ]]; then
    [[ -d "$cfg_dir" ]] || return 0
  else
    [[ -d "$ext_dir" ]] || return 0
  fi

  if [[ -n "$opts" ]]; then
    printf '%s\t%s\t%s\n' "$ext_dir" "$cfg_dir" "$opts"
  else
    printf '%s\t%s\n' "$ext_dir" "$cfg_dir"
  fi
}

_vscode_variant_sources() {
  # Variant files are another overlay extension point. Keep the family contract
  # named here so discovery, docs, and tests can drift together less.
  _merge_hook_family_files_matching vscode/variants.d '*.tsv' '*.replace/*.tsv'
}

_vscode_local_extension_sources() {
  _merge_hook_family_files_matching vscode/local-extensions.d '*.tsv' '*.replace/*.tsv'
}

_vscode_extension_manifest_sources() {
  # Extension manifests are TOML fragments. Each file may be incomplete; the
  # Python helper validates the aggregate after dot core has selected the family
  # stream and any .replace winners.
  _merge_hook_family_files_matching vscode/extensions.d '*.toml' '*.replace/*.toml'
}

_vscode_install_declared_extensions() {
  # Broader merge tests focus on settings/keybindings/local-extension behavior
  # and should not accidentally call a developer's real VS Code CLI. Production
  # dot updates leave this unset; the dedicated vscode-extensions-test exercises
  # this helper with fake CLIs.
  [[ "${DOT_VSCODE_EXTENSIONS_SKIP:-0}" = 1 ]] && return 0

  command -v python3 >/dev/null 2>&1 || return 0

  local helper
  helper="$(_merge_hook_dir)/vscode/extensions.py"
  [[ -f "$helper" ]] || return 0

  local -a args=()
  local manifest
  while IFS= read -r manifest; do
    args+=(--manifest "$manifest")
  done < <(_vscode_extension_manifest_sources)

  ((${#args[@]} > 0)) || return 0

  # Runtime extension installation is advisory, but malformed manifest fragments
  # are dotfiles configuration errors. The helper keeps network/gallery failures
  # at exit 0 after warning; exit 2 is reserved for invalid aggregate policy.
  local rc=0
  python3 "$helper" "${args[@]}" || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    _warn "    warning: invalid VS Code extension manifest"
    return "$rc"
  elif [[ "$rc" -ne 0 ]]; then
    _warn "    warning: VS Code extension install failed — skipping"
  fi
}

_vscode_remote_settings_dirs() {
  local root

  for root in \
    "$HOME/.vscode-server" \
    "$HOME/.vscode-server-insiders" \
    "$HOME/.vscode-remote" \
    "$HOME/.cursor-server"; do
    [[ -d "$root" ]] || continue
    printf '%s/data/Machine\n' "$root"
  done
}

_merge_vscode_remote_window_titles() {
  local remote_settings_dir

  while IFS= read -r remote_settings_dir; do
    _merge_vscode_window_title "$remote_settings_dir/settings.json"
  done < <(_vscode_remote_settings_dirs)
}

_merge_vscode_remote_mcp_auth() {
  local remote_settings_dir

  while IFS= read -r remote_settings_dir; do
    _merge_vscode_mcp_auth "$remote_settings_dir/settings.json"
  done < <(_vscode_remote_settings_dirs)
}

_vscode_variant_file_records() {
  local current
  current="$(_vscode_platform)"

  # WSL is called out as its own platform value here specifically so overlay
  # rows can declare extra config dirs under the native Windows profile (see
  # the merge-hooks README) — the same single-shared-file hazard as the
  # built-in WSL appdata variant below, so gate every row the same way rather
  # than trusting each future overlay author to remember it per row.
  if [[ "$current" == "WSL" ]]; then
    dot_wsl_is_paired_windows_account || return 0
  fi

  local file platform marker ext_dir cfg_dir opts _rest appdata
  while IFS= read -r file; do
    while IFS=$'\t' read -r platform marker ext_dir cfg_dir opts _rest || [[ -n "${platform:-}" ]]; do
      [[ -n "${platform:-}" ]] || continue
      [[ "$platform" == \#* ]] && continue
      _vscode_platform_matches "$platform" "$current" || continue
      if _vscode_variant_uses_wsl_appdata "$marker" "$ext_dir" "$cfg_dir"; then
        while IFS= read -r appdata; do
          [[ -n "$appdata" ]] || continue
          _vscode_record_variant \
            "$(_vscode_substitute_wsl_appdata "$marker" "$appdata")" \
            "$(_vscode_substitute_wsl_appdata "$ext_dir" "$appdata")" \
            "$(_vscode_substitute_wsl_appdata "$cfg_dir" "$appdata")" \
            "$opts"
        done < <(_vscode_wsl_appdata_dirs)
      else
        _vscode_record_variant "$marker" "$ext_dir" "$cfg_dir" "$opts"
      fi
    done <"$file"
  done < <(_vscode_variant_sources)
}

# Discover installed VS Code variants.  Each entry is a pair of tab-separated
# paths: extensions_dir<TAB>config_dir.  The config dir may be empty for remote
# extension-host profiles that need local extensions registered but do not own a
# user settings/keybindings file on this machine.
_vscode_variants() {
  _vscode_variant_file_records
}

_vscode_opts_intersect() {
  local opts="$1" disabled_opts="$2" disabled
  [[ -n "$disabled_opts" && "$disabled_opts" != "-" ]] || return 1

  local IFS=','
  for disabled in $disabled_opts; do
    [[ -n "$disabled" ]] || continue
    _vscode_opts_contains "$opts" "$disabled" && return 0
  done
  return 1
}

_vscode_local_extensions() {
  local file ext_id source_dir disabled_opts _rest
  while IFS= read -r file; do
    while IFS=$'\t' read -r ext_id source_dir disabled_opts _rest || [[ -n "${ext_id:-}" ]]; do
      [[ -n "${ext_id:-}" ]] || continue
      [[ "$ext_id" == \#* ]] && continue
      if [[ -z "${source_dir:-}" || -n "${_rest:-}" ]]; then
        _warn "    warning: malformed VS Code local extension row in $file"
        continue
      fi
      source_dir="$(_vscode_expand_path "$source_dir")"
      [[ -n "$source_dir" ]] || continue
      printf '%s\t%s\t%s\n' "$ext_id" "$source_dir" "${disabled_opts:-}"
    done <"$file"
  done < <(_vscode_local_extension_sources)
}

# Main: deploy extensions, settings, and keybindings to all VS Code variants.
merge() {
  _vscode_install_declared_extensions || return $?

  command -v jq &>/dev/null || return 0

  local -a variants=()
  local line
  while IFS= read -r line; do
    variants+=("$line")
  done < <(_vscode_variants)

  _merge_vscode_remote_window_titles
  _merge_vscode_remote_mcp_auth

  ((${#variants[@]} > 0)) || return 0

  local _ext_spec _ext_id _ext_src _ext_disabled_opts _ext_name
  local ext_dir cfg_dir opts rest merge_rc=0
  for line in "${variants[@]}"; do
    ext_dir="${line%%	*}"
    _prune_vscode_local_extensions "$ext_dir/extensions.json"
  done

  while IFS=$'\t' read -r _ext_id _ext_src _ext_disabled_opts; do
    _ext_name="${_ext_src##*/}"

    for line in "${variants[@]}"; do
      ext_dir="${line%%	*}"
      rest="${line#*	}"
      cfg_dir="${rest%%	*}"
      opts="${rest#*	}"
      [[ "$opts" == "$cfg_dir" ]] && opts=""
      if _vscode_opts_intersect "$opts" "$_ext_disabled_opts"; then
        _prune_vscode_extension_versions \
          "$_ext_id" "$_ext_src" "" "$ext_dir/extensions.json"
        _remove_vscode_extension "$_ext_id" "$_ext_name" "$ext_dir/extensions.json"
        continue
      fi
      # An unavailable payload cannot be installed, but it must not prevent a
      # different variant's explicit opt-out above from cleaning stale copies.
      [[ -d "$_ext_src" ]] || continue
      _prune_vscode_extension_versions \
        "$_ext_id" "$_ext_src" "$_ext_name" "$ext_dir/extensions.json"
      mkdir -p "$ext_dir"
      if [[ ! -e "$ext_dir/$_ext_name" ]]; then
        ln -sf "$_ext_src" "$ext_dir/$_ext_name"
      fi
      _ensure_vscode_extension "$_ext_id" "$_ext_name" "$ext_dir/extensions.json"
    done
  done < <(_vscode_local_extensions)

  # Merge settings and keybindings.
  # Variants are independent, so keep processing after one fails. Preserve the
  # aggregate failure explicitly: the hook runner deliberately invokes merge
  # in a context where Bash errexit is not a reliable error boundary, and a
  # later successful variant must not make a partial deployment look healthy.
  _log "  VS Code"
  for line in "${variants[@]}"; do
    rest="${line#*	}"
    cfg_dir="${rest%%	*}"
    opts="${rest#*	}"
    [[ "$opts" == "$cfg_dir" ]] && opts=""
    if [[ -n "$cfg_dir" ]]; then
      _merge_vscode_config "$cfg_dir" "$opts" || merge_rc=1
    fi
  done
  return "$merge_rc"
}
