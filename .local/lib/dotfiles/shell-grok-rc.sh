# shellcheck shell=bash
# Remove the Grok vendor installer block from tracked thin loaders.
# install.sh appends a marked PATH/fpath/compinit block to ~/.zshrc or
# ~/.bashrc. Those files stay loaders; PATH and completions live under
# ~/.config/shell/. Strip after grok update/doctor rather than while the
# loader is still being sourced, so an in-flight source does not rewrite
# the file it is reading.

dot_grok_strip_installer_rc() {
  local f tmp
  for f in "$HOME/.zshrc" "$HOME/.bashrc"; do
    [ -f "$f" ] || continue
    grep -q 'grok installer' "$f" 2>/dev/null || continue
    tmp=$(mktemp "${TMPDIR:-/tmp}/grok-rc.XXXXXX") || return 1
    awk '
      /^$/ {
        pending = pending $0 "\n"
        next
      }
      /# >>> grok installer >>>/ {
        skip = 1
        pending = ""
        next
      }
      /# <<< grok installer <<</ {
        skip = 0
        next
      }
      !skip {
        printf "%s%s\n", pending, $0
        pending = ""
      }
    ' "$f" >"$tmp" || {
      rm -f "$tmp"
      return 1
    }
    if cmp -s "$f" "$tmp"; then
      rm -f "$tmp"
    else
      mv "$tmp" "$f" || {
        rm -f "$tmp"
        return 1
      }
    fi
  done
  return 0
}
