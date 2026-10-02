# shellcheck shell=bash
dot_hook_source merge-hooks.d/lib/compat.sh || return
dot_hook_source shell-grok-rc.sh || return

# Strip the Grok vendor installer block from the tracked thin loaders during
# `dot update`. The interactive grok/agent wrapper strips after each launch,
# but a vendor auto-update outside an interactive shell can re-add the block;
# this hook converges those hosts without `dot doctor` rewriting files. The
# block makes the tracked loader dirty, and cron updates skip a dirty client
# before any hook runs, so the repair comes from an interactive `dot update`
# (or the next grok launch); `dot doctor` says so.
#
# Each loader is rewritten only while it still matches the generation read
# here, so an edit landing between read and publish (the installer appending
# again, a user editing the file) is preserved and retried on the next update.

merge() {
  _dot_tool_present grok-rc || return 0
  local rc generation now tmp mode status=0

  while IFS= read -r rc; do
    # A symlinked loader belongs to someone else's layout; never replace it
    # with a regular file.
    [[ -f $rc && ! -L $rc ]] || continue
    dot_grok_rc_has_block "$rc" || continue

    if ! generation=$(dot_file_generation "$rc"); then
      dot_hook_warn "    warning: cannot snapshot $rc; Grok installer block left in place"
      status=1
      continue
    fi
    if ! dot_sibling_tmp_for "$rc"; then
      dot_hook_warn "    warning: cannot stage $rc; Grok installer block left in place"
      status=1
      continue
    fi
    tmp=$REPLY
    # An unclosed block fails the filter: leave the file for a human rather
    # than drop everything after the marker.
    if ! dot_grok_rc_filter "$rc" >"$tmp"; then
      rm -f "$tmp"
      dot_hook_warn "    warning: $rc has an unterminated Grok installer block; edit it by hand"
      status=1
      continue
    fi
    # Nothing to remove (a marker-only match) is not a change to publish.
    if dot_config_files_equal "$rc" "$tmp"; then
      rm -f "$tmp"
      continue
    fi
    # Keep the loader's permissions: the sibling temporary starts private.
    if ! mode=$(dot_grok_rc_mode "$rc") || ! chmod "$mode" "$tmp"; then
      rm -f "$tmp"
      status=1
      continue
    fi
    if dot_commit_tmp_if_generation "$tmp" "$rc" "$generation"; then
      dot_hook_log "  Grok installer block removed from ${rc/#"$HOME"/\~}"
      continue
    fi
    rm -f "$tmp"
    # The helper reports a lost race and a real failure alike. A loader that
    # changed since the snapshot lost the race, which is not a configuration
    # failure: the next update re-reads it and tries again.
    if now=$(dot_file_generation "$rc" 2>/dev/null) && [[ $now != "$generation" ]]; then
      dot_hook_warn "    warning: $rc changed while stripping the Grok installer block; retrying next update"
    else
      dot_hook_warn "    warning: could not rewrite $rc; Grok installer block left in place"
      status=1
    fi
  done < <(dot_grok_rc_files)

  return "$status"
}
