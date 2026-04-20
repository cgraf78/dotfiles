# shellcheck shell=bash
# Shared helpers for ~/.local/bin/autoformat and ~/.local/bin/autolint.
#
# Kept minimal: the helpers must stay safe to source under `set -u`
# (the defaults used by both callers) and must not define any globals
# beyond the helper functions themselves.
#
# The `_toml_*` helpers require `yq` on PATH. Both autoformat and
# autolint hard-require yq in their own entry points; this file does
# not re-check at source time (the check would run on every edit-hook
# fire and yq is a dotfiles-managed install anyway).

# Walk up from the file's directory looking for a config file.
# Tracks `prev` so the loop terminates even when `dir` is relative
# (e.g. "."), where dirname would otherwise never shrink toward root.
_has_config() {
  local dir="$1" name="$2" root="${3:-/}" prev=""
  while [ "$dir" != "$prev" ]; do
    [ -f "$dir/$name" ] && return 0
    [ "$dir" = "$root" ] && break
    prev="$dir"
    dir=$(dirname "$dir")
  done
  return 1
}

# Like `_has_config`, but prints the absolute path of the found
# config on success. Useful when a tool's own config discovery
# differs from our walk semantics and we need to pass the path
# through explicitly via `--config <path>`.
_find_config() {
  local dir="$1" name="$2" root="${3:-/}" prev=""
  while [ "$dir" != "$prev" ]; do
    if [ -f "$dir/$name" ]; then
      printf '%s\n' "$dir/$name"
      return 0
    fi
    [ "$dir" = "$root" ] && break
    prev="$dir"
    dir=$(dirname "$dir")
  done
  return 1
}

# Classify an extensionless file by dotfile-name or shebang. Prints one
# of: zsh | bash | skip | unknown. Callers decide what to do with each.
# `.profile` is classified as bash because shfmt has no POSIX default
# mode that differs meaningfully, and shellcheck handles sh regardless.
_classify_shell() {
  local file="$1" base first
  base="${file##*/}"

  case "$base" in
    .zshenv | .zshrc | .zprofile | .zlogin | .zlogout)
      printf 'zsh\n'
      return 0
      ;;
    .bashrc | .bash_profile | .profile)
      printf 'bash\n'
      return 0
      ;;
    Makefile | Dockerfile)
      printf 'skip\n'
      return 0
      ;;
  esac

  # Skip binary files before reading — otherwise the builtin `read`
  # on a binary (e.g. `.gif` that fell through to the extensionless
  # path) could leak null bytes. `grep -I` returns non-zero when
  # $file is detected as binary.
  if ! grep -Iq '' "$file" 2>/dev/null; then
    printf 'unknown\n'
    return 0
  fi

  # Read the shebang line via builtin (no fork), then classify with
  # bash's own regex engine (no fork). Patterns stored in variables
  # so bash passes the backslash through to the regex library.
  IFS= read -r first <"$file" 2>/dev/null || first=""
  if [[ "$first" != '#!'* ]]; then
    printf 'unknown\n'
    return 0
  fi
  local zsh_pat='(^|[^[:alnum:]_])zsh($|[^[:alnum:]_])'
  local bash_pat='(^|[^[:alnum:]_])(ba)?sh($|[^[:alnum:]_])'
  if [[ "$first" =~ $zsh_pat ]]; then
    printf 'zsh\n'
  elif [[ "$first" =~ $bash_pat ]]; then
    printf 'bash\n'
  else
    printf 'unknown\n'
  fi
}

# Read multiple keys from a TOML file in a single `yq` invocation.
# Prints one line per requested key, in order; missing/null keys print
# as an empty line so callers can parse with sequential `read` calls.
# Collapsing N lookups into 1 subprocess matters for hook latency.
_toml_read_keys() {
  local file="$1"
  shift
  local expr="" k
  for k in "$@"; do
    [ -n "$expr" ] && expr="$expr, "
    expr="$expr.$k // \"\""
  done
  yq -p toml "$expr" "$file" 2>/dev/null
}

# Walk up from $dir looking for a $filename whose content (parsed by
# yq in the given $format: `toml` or `json`) satisfies the yq
# predicate. Returns 0 on first match. Tracks `prev` to terminate on
# relative paths, same as `_has_config`.
#
# Used to detect per-repo configs that live INSIDE a multi-purpose
# file — pyproject.toml with a `[tool.ruff]` section, package.json
# with a `prettier` key, etc. The caller writes the predicate
# themselves so hyphenated keys / nested paths / `//` coalescing are
# all supported uniformly:
#
#   _walk_config_with_key "$_filedir" pyproject.toml toml \
#     '.tool.ruff // .tool.ruff.format'
#   _walk_config_with_key "$_filedir" package.json json '.prettier'
#   _walk_config_with_key "$_filedir" package.json json \
#     '."markdownlint-cli2"'
_walk_config_with_key() {
  local dir="$1" filename="$2" format="$3" predicate="$4" prev=""
  while [ "$dir" != "$prev" ]; do
    if [ -f "$dir/$filename" ] &&
      yq -p "$format" -e "$predicate" "$dir/$filename" >/dev/null 2>&1; then
      return 0
    fi
    [ "$dir" = "/" ] && break
    prev="$dir"
    dir=$(dirname "$dir")
  done
  return 1
}

# Check whether a file is listed in the user's ignore file. Returns 0
# (ignored) if any non-blank non-comment line in the ignore file is a
# bash glob pattern that matches the file path. Returns 1 otherwise
# (including when the ignore file doesn't exist).
#
# Both autoformat and autolint call this at the top of dispatch so the
# decision applies to formatting and linting uniformly. The default
# location is shared: `$AUTOFORMAT_DIR/ignore` on the format side,
# `$AUTOLINT_DIR/ignore` on the lint side — since AUTOLINT_DIR defaults
# to AUTOFORMAT_DIR, both resolve to `~/.config/autoformat/ignore`
# unless overridden for tests.
#
# Pattern semantics: plain bash globs — `*`, `?`, `[...]` — matched
# against the file path as passed in. No `**`, no negations, no
# gitignore-style directory anchoring. Matching file path (absolute
# or relative) depends on what the caller passed to autoformat.
_ignored() {
  local file="$1" ignorefile="$2" pattern
  [ -f "$ignorefile" ] || return 1
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    case "$pattern" in
      '' | \#*) continue ;;
    esac
    # shellcheck disable=SC2053  # pattern is intentionally unquoted for glob
    [[ "$file" == $pattern ]] && return 0
  done <"$ignorefile"
  return 1
}
