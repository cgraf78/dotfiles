# shellcheck shell=bash
# A newer provider revision can supersede an unpublished consumer repin even
# when neither commit ancestry nor patch identity proves a consumer merge.

# Return success only when every branch edit is an obsolete Actions pin and
# the current base uses a descendant provider. The retained local branch keeps
# history available; this proves obsolete checkout intent, not a code merge.
# Every Git read and the GitHub query run through _worktree_gc_batch (from
# worktree-gc.sh): in a blobless or partial clone a blob read lazily fetches
# from the remote, which must fail rather than prompt in an unattended sweep.
_worktree_gc_actions_superseded() (
  # Scope pipefail to the proof: failed Git reads must never compare as empty.
  set -o pipefail
  local dir=$1 target=$2 base=$3 ancestor old pin current files file entry oid expression source content expected counts
  [[ ${_WORKTREE_GC_NO_FETCH:-0} != 1 ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  ancestor=$(_worktree_gc_batch git -C "$dir" merge-base "$target" "$base" 2>/dev/null) || return 1
  old=$(_worktree_gc_batch git -C "$dir" show "$ancestor:.github/cgraf78-actions.lock" 2>/dev/null) || return 1
  pin=$(_worktree_gc_batch git -C "$dir" show "$target:.github/cgraf78-actions.lock" 2>/dev/null) || return 1
  current=$(_worktree_gc_batch git -C "$dir" show "$base:.github/cgraf78-actions.lock" 2>/dev/null) || return 1
  [[ $old =~ ^[0-9a-f]{40}$ && $pin =~ ^[0-9a-f]{40}$ && $current =~ ^[0-9a-f]{40}$ ]] || return 1
  [[ $old != "$pin" ]] || return 1
  files=$(_worktree_gc_batch git -C "$dir" diff --name-only "$ancestor" "$target" 2>/dev/null) || return 1
  [[ -n $files ]] || return 1
  while IFS= read -r file; do
    case $file in
      .github/cgraf78-actions.lock | .github/workflows/*.yml | .github/workflows/*.yaml) ;;
      *) return 1 ;;
    esac
    [[ $file == .github/cgraf78-actions.lock || ${file#.github/workflows/} != */* ]] || return 1
    # Bash cannot represent NUL bytes. Reject binary diffs before capturing
    # blobs so removing those bytes cannot disguise an independent edit.
    counts=$(_worktree_gc_batch git -C "$dir" diff --numstat "$ancestor" "$target" -- "$file" 2>/dev/null) || return 1
    [[ $counts =~ ^[0-9]+$'\t'[0-9]+$'\t' ]] || return 1
    # Additions, removals, symlinks and executable-mode changes are independent
    # work. Only ordinary pre-existing provider reference files qualify.
    for oid in "$ancestor" "$target"; do
      entry=$(_worktree_gc_batch git -C "$dir" ls-tree "$oid" -- "$file" 2>/dev/null) || return 1
      [[ $entry == '100644 blob '* ]] || return 1
    done
    if [[ $file == .github/cgraf78-actions.lock ]]; then
      expression="s/^$old\$/$pin/"
    else
      # A coincidental SHA in product commands, comments or another provider
      # does not become disposable just because it matches our lock value.
      expression="s#\\(uses: *cgraf78/actions/[^[:space:]]*@\\)$old\\([[:space:]]*\\)\$#\\1$pin\\2#"
    fi
    # Explicitly check producer statuses. A sentinel preserves trailing newlines
    # through command substitution so whole-file comparison remains exact.
    source=$(if _worktree_gc_batch git -C "$dir" show "$ancestor:$file" 2>/dev/null; then printf '.'; else return 1; fi) || return 1
    content=$(if _worktree_gc_batch git -C "$dir" show "$target:$file" 2>/dev/null; then printf '.'; else return 1; fi) || return 1
    expected=$(if printf '%s' "${source%.}" | sed "$expression"; then printf '.'; else return 1; fi) || return 1
    [[ $expected == "$content" ]] || return 1
  done <<<"$files"
  # Require full SHA identities in the response, rather than trusting a status
  # produced for an abbreviated ref or an unrelated merge base.
  _worktree_gc_batch gh api --hostname github.com "repos/cgraf78/actions/compare/$pin...$current" 2>/dev/null |
    jq -se --arg pin "$pin" \
      'length == 1 and (.[0] | type == "object" and
       (.status == "ahead" or .status == "identical") and
       .base_commit.sha == $pin and .merge_base_commit.sha == $pin)' \
      >/dev/null 2>&1 || return 1
)
