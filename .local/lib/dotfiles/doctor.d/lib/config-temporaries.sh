# shellcheck shell=bash
# dot doctor: temporaries an interrupted write left beside managed config.
#
# Overlay-facing contract (stable; see doctor.d/README.md):
#
#   if dot_doctor_source doctor.d/lib/config-temporaries.sh; then
#     _dr_check_config_temporaries DIR...
#   fi
#
# Merge hooks rewrite config files atomically through a sibling temporary,
# and an update killed mid-write leaves that sibling behind, sometimes with
# secrets in it (~/.ssh/config). Each layer passes the directories its own
# hooks write into; base checks the destinations of base hooks in its
# Managed configuration section, and an overlay checks its own in its
# section. Directories base already checks are dropped from an overlay's
# list, so a directory two layers write is still reported once.
#
# Loads doctor.d/lib/compat.sh itself, so callers need nothing else.

dot_doctor_source doctor.d/lib/compat.sh || return

# Temporaries younger than this many minutes may belong to an update that
# is still running.
_DR_CONFIG_TMP_MINUTES=10

# Report via _DR_CONFIG_TMP_DIRS the directories base's own merge hooks
# write config files into through sibling temporaries: HOME (`.ignore`, the
# shell loaders the grok-rc hook edits), ssh and sshd, Karabiner, Codex
# trust pruning, and every agent-rules target the last update recorded in
# its manifest. Stamps in the cache are left out: a leftover there holds
# nothing worth a warning. A directory that does not exist costs one failed
# test.
_dr_config_temporaries_base_dirs() {
  local state=${XDG_STATE_HOME:-} kind target
  [[ $state == /* ]] || state=$HOME/.local/state
  _DR_CONFIG_TMP_DIRS=(
    "$HOME"
    "$HOME/.ssh"
    /etc/ssh
    "$HOME/.config/karabiner"
    "$HOME/.codex"
  )
  # The agent-rules hook records each policy target it renders; the
  # renderer writes through `<target>.tmp.XXXXXXXX` beside it.
  [[ -r $state/dot/agent-rules-sync-manifest-v1.tsv ]] || return 0
  while IFS=$'\t' read -r kind target _; do
    [[ $kind == target-file && $target == /*/* ]] || continue
    _DR_CONFIG_TMP_DIRS+=("${target%/*}")
  done <"$state/dot/agent-rules-sync-manifest-v1.tsv"
}

# Report via REPLY one directory argument as an absolute path without a
# trailing slash; a relative one is taken relative to HOME.
_dr_config_temporaries_dir() {
  local dir=$1
  [[ $dir == /* ]] || dir=$HOME/$dir
  while [[ $dir == */ && $dir != / ]]; do
    dir=${dir%/}
  done
  REPLY=$dir
}

# List the leftover temporaries in the given directories as one warning,
# or nothing when there are none. Only direct children count, by the names
# the writers use, hidden or not: `<file>.tmp` and `<file>.tmp.<suffix>`
# (mktemp, a PID, or an application's own PID-and-random scheme), plus
# `.<name>.realize.<suffix>`. The first two are the names Dot's family scan
# already ignores as temporaries. Only regular files past the in-flight
# window count, and nothing is deleted: whether a leftover still matters is
# the owner's call. HOME itself is checked for hidden names only: every
# config file written there is a dotfile, and a visible `notes.tmp` is the
# user's own.
_dr_config_temporaries_report() {
  local dir file
  local -a candidates=() stale=() items=() names=()
  local -A seen=()

  for dir; do
    [[ -d $dir ]] || continue
    names=("$dir"/.*.tmp "$dir"/.*.tmp.* "$dir"/.*.realize.*)
    [[ $dir == "$HOME" ]] || names+=("$dir"/*.tmp "$dir"/*.tmp.*)
    for file in "${names[@]}"; do
      [[ -f $file && ! -L $file && -z ${seen[$file]+x} ]] || continue
      seen[$file]=1
      candidates+=("$file")
    done
  done
  ((${#candidates[@]} > 0)) || return 0
  # One find for every candidate. Each path is absolute, so none can be
  # taken for an option.
  while IFS= read -r -d '' file; do
    stale+=("$file")
  done < <(find "${candidates[@]}" -maxdepth 0 -mmin +"$_DR_CONFIG_TMP_MINUTES" -print0 2>/dev/null)
  ((${#stale[@]} > 0)) || return 0
  for file in "${stale[@]}"; do
    items+=("$(_dr_tilde "$file")")
  done
  _dr_list_row warn "${#stale[@]} leftover config temporary file(s)" \
    "an interrupted write left them: delete them once no 'dot update', or the program that owns the file, is running" \
    "${items[@]}"
}

# Base's own check: the destinations of base merge hooks.
_dr_check_base_config_temporaries() {
  _dr_config_temporaries_base_dirs
  _dr_config_temporaries_report "${_DR_CONFIG_TMP_DIRS[@]}"
}

# Overlay-facing: check DIR... (absolute, or relative to HOME) for leftover
# temporaries and file at most one warning row in the caller's section.
# Directories base already checks, and repeats, are dropped first.
_dr_check_config_temporaries() {
  local dir
  local -a dirs=()
  local -A skip=()

  _dr_config_temporaries_base_dirs
  for dir in "${_DR_CONFIG_TMP_DIRS[@]}"; do
    _dr_config_temporaries_dir "$dir"
    skip[$REPLY]=1
  done
  for dir; do
    _dr_config_temporaries_dir "$dir"
    [[ -z ${skip[$REPLY]+x} ]] || continue
    skip[$REPLY]=1
    dirs+=("$REPLY")
  done
  ((${#dirs[@]} > 0)) || return 0
  _dr_config_temporaries_report "${dirs[@]}"
}
