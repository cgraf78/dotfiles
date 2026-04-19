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

  # Skip binary files before reading — otherwise `head -n1` on a
  # binary (e.g. `.gif` that fell through to the extensionless path)
  # leaks null bytes through command substitution, and bash warns.
  # `grep -I` returns non-zero when $file is detected as binary.
  if ! grep -Iq '' "$file" 2>/dev/null; then
    printf 'unknown\n'
    return 0
  fi

  first=$(head -n1 "$file" 2>/dev/null) || true
  if printf '%s\n' "$first" | grep -qE '^#!.*\bzsh\b'; then
    printf 'zsh\n'
  elif printf '%s\n' "$first" | grep -qE '^#!.*\b(ba)?sh\b'; then
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

# Return 0 when a TOML file contains any of the listed non-null keys.
_toml_has_any() {
  local file="$1"
  shift
  local expr="" k
  for k in "$@"; do
    [ -n "$expr" ] && expr="$expr // "
    expr="$expr.$k"
  done
  yq -p toml -e "$expr" "$file" >/dev/null 2>&1
}
