# shellcheck shell=bash
# Shared helpers for ~/.local/bin/autoformat and ~/.local/bin/autolint.
#
# Kept minimal: the helpers must stay safe to source under `set -u`
# (the defaults used by both callers) and must not define any globals
# beyond the helper functions themselves.

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

  first=$(head -n1 "$file" 2>/dev/null) || true
  if printf '%s\n' "$first" | grep -qE '^#!.*\bzsh\b'; then
    printf 'zsh\n'
  elif printf '%s\n' "$first" | grep -qE '^#!.*\b(ba)?sh\b'; then
    printf 'bash\n'
  else
    printf 'unknown\n'
  fi
}
