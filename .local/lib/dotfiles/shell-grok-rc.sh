# shellcheck shell=bash
# Remove the Grok vendor installer block from tracked thin loaders.
# install.sh appends a marked PATH/fpath/compinit block to ~/.zshrc or
# ~/.bashrc. Those files stay loaders; PATH and completions live under
# ~/.config/shell/. Strip after a grok/agent launch (72-grok.sh) and during
# `dot update` (the grok-rc merge hook) rather than while the loader is still
# being sourced, so an in-flight source does not rewrite the file it is
# reading. `dot doctor` only reports the block through the predicate below:
# diagnostics must never rewrite tracked files.
#
# Sourced by interactive bash and zsh, so this stays POSIX-shaped.

# The thin loaders the vendor installer appends to, in strip order.
dot_grok_rc_files() {
  printf '%s\n' "$HOME/.zshrc" "$HOME/.bashrc"
}

# Succeed when FILE carries the start of a vendor installer block.
dot_grok_rc_has_block() {
  [ -f "$1" ] || return 1
  grep -qF '# >>> grok installer >>>' "$1" 2>/dev/null
}

# Print FILE without the marked vendor block or the blank lines that
# introduced it. Other blank lines between content survive; trailing blank
# lines at end of file and stray end markers are dropped. Fails when a block
# never closes: everything after an unmatched start marker would otherwise
# vanish, including the user's own lines.
dot_grok_rc_filter() {
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
    END { exit skip }
  ' "$1"
}

# Print FILE's permission bits; GNU and BSD stat spellings.
dot_grok_rc_mode() {
  # `command` skips zsh's optional stat builtin, which takes other flags.
  command stat -c '%a' "$1" 2>/dev/null || command stat -f '%Lp' "$1" 2>/dev/null
}

# Strip the block in place after an interactive grok/agent launch. The
# temporary is a sibling carrying the loader's mode, so the rename is atomic
# and keeps permissions; a symlinked loader belongs to someone else's layout
# and is left alone. One loader that cannot be stripped does not stop the
# other. The loop's status (it runs in a subshell under bash) carries any
# failure out as this function's status.
dot_grok_strip_installer_rc() {
  local f tmp mode failed
  dot_grok_rc_files | {
    failed=0
    while IFS= read -r f; do
      [ -L "$f" ] && continue
      dot_grok_rc_has_block "$f" || continue
      if ! tmp=$(mktemp "$f.tmp.XXXXXX"); then
        failed=1
        continue
      fi
      if ! dot_grok_rc_filter "$f" >"$tmp" ||
        ! mode=$(dot_grok_rc_mode "$f") ||
        ! chmod "$mode" "$tmp"; then
        rm -f "$tmp"
        failed=1
        continue
      fi
      if cmp -s "$f" "$tmp"; then
        rm -f "$tmp"
      elif ! mv -f "$tmp" "$f"; then
        rm -f "$tmp"
        failed=1
      fi
    done
    [ "$failed" = 0 ]
  }
}
