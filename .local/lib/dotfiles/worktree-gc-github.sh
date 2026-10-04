# shellcheck shell=bash
# Optional GitHub evidence for removing a checkout while retaining its branch.
# All reads are advisory: unavailable tools, partial pages and invalid data
# yield no proof. The caller owns removal gates and pinned Git identities.

# Print an observed PR state and number for an exact commit member on the
# selected repository/base, or none and a dash after a complete observation.
# Errors produce no record. Subshell scope protects caller shell state.
_worktree_gc_github() (
  local dir=$1 target_oid=$2 base_oid=$3 base_ref=$4
  local remote ref url repo pages candidates number state merged merge_oid
  local branch owner named associated
  local members verified merged_number='' closed_number='' open_number=''
  export LC_ALL=C
  [[ ${_WORKTREE_GC_NO_FETCH:-0} == 0 ]] || return 1
  command -v gh >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  [[ $target_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ && $base_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] || return 1
  base_ref=${base_ref#refs/remotes/}
  [[ $base_ref == */* ]] || return 1
  remote=${base_ref%%/*}
  ref=${base_ref#*/}
  [[ -n $remote && -n $ref ]] || return 1
  url=$(git -C "$dir" remote get-url -- "$remote" 2>/dev/null) || return 1
  # Parse only explicit github.com transports, never substring host matches.
  case $url in
    https://github.com/*) repo=${url#https://github.com/} ;;
    ssh://git@github.com/*) repo=${url#ssh://git@github.com/} ;;
    git@github.com:*) repo=${url#git@github.com:} ;;
    *) return 1 ;;
  esac
  repo=${repo%.git}
  [[ $repo =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]] || return 1
  [[ ${repo#*/} != . && ${repo#*/} != .. ]] || return 1
  owner=${repo%%/*}
  branch=$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null) || return 1

  # gh must finish every page successfully before any record is considered.
  # --hostname prevents ambient GH_HOST from selecting a different service.
  if ! associated=$(gh api --hostname github.com --paginate --slurp \
    "repos/$repo/commits/$target_oid/pulls" 2>/dev/null); then
    # An unpublished local SHA has no server commit object. That endpoint's
    # structured 422 response permits branch-name observation, while other
    # transport/API failures must keep the checkout. Do not parse error prose.
    jq -se 'length == 1 and (.[0] | type == "array" and length == 1
      and (.[0] | type == "object" and (.status == "422" or .status == 422)
        and .errors == null))' <<<"$associated" >/dev/null 2>&1 || return 1
    associated='[[]]'
  fi
  named=$(gh api --hostname github.com --method GET --paginate --slurp \
    "repos/$repo/pulls" -f state=all -f "head=$owner:$branch" \
    -f per_page=100 2>/dev/null) || return 1
  named=$(jq -sce --arg repo "$repo" --arg branch "$branch" '
    if length != 1 then error("response") else .[0] end
    | if type != "array" or any(.[]; type != "array") then error("pages") else . end
    | add // []
    | if any(.[]; type != "object" or (.head.ref | type != "string") or
        (.head.repo.full_name | type != "string")) then error("head shape") else . end
    | [.[] | select(.head.ref == $branch and
        (.head.repo.full_name | ascii_downcase) == ($repo | ascii_downcase))]
    | [.]
  ' <<<"$named" 2>/dev/null) || return 1
  pages=$(jq -sc --argjson named "$named" '
    if length != 1 or (.[0] | type != "array" or any(.[]; type != "array"))
    then error("pages") else .[0] + $named end
  ' <<<"$associated" 2>/dev/null) || return 1
  candidates=$(jq --slurp --raw-output --arg repo "$repo" --arg ref "$ref" '
    if length != 1 then error("response") else .[0] end
    | if type != "array" or any(.[]; type != "array") then error("pages") else . end
    | add // []
    | if any(.[]; type != "object" or
        (.number | type != "number") or .number < 1 or (.number | floor) != .number or
        (.state != "open" and .state != "closed") or
        (.base.ref | type != "string") or (.base.repo.full_name | type != "string") or
        (.merged_at != null and (.merged_at | type != "string")) or
        (.merge_commit_sha != null and (.merge_commit_sha | type != "string")))
      then error("pull request shape") else . end
    | .[] | select((.base.repo.full_name | ascii_downcase) == ($repo | ascii_downcase)
        and .base.ref == $ref)
    | [.number, .state, (.merged_at != null), (.merge_commit_sha // "-")] | @tsv
  ' <<<"$pages" 2>/dev/null) || return 1
  while IFS=$'\t' read -r number state merged merge_oid; do
    [[ -n $number ]] || continue
    # An open PR on the actual branch protects later unpublished local work.
    # Associated PRs on other branches still require exact membership below.
    if [[ $state == open ]] && jq -e --argjson number "$number" \
      'any(.[][]; .number == $number)' <<<"$named" >/dev/null 2>&1; then
      open_number=$number
      continue
    fi
    members=$(gh api --hostname github.com --paginate --slurp \
      "repos/$repo/pulls/$number/commits" 2>/dev/null) || return 1
    verified=$(jq --slurp --exit-status --raw-output --arg oid "$target_oid" '
      if length != 1 then error("response") else .[0] end
      | if type != "array" or any(.[]; type != "array") then error("pages") else . end
      | add // []
      | if any(.[]; type != "object" or (.sha | type != "string") or
          (.sha | test("^([0-9a-f]{40}|[0-9a-f]{64})$") | not)) then error("commit shape") else . end
      | any(.[]; .sha == $oid) | tostring
    ' <<<"$members" 2>/dev/null) || return 1
    [[ $verified == true ]] || continue
    if [[ $state == open ]]; then
      open_number=$number
    elif [[ $merged == true ]]; then
      # A server merge record proves landing only on this pinned local base.
      # Never fetch an unknown merge or substitute the current remote HEAD.
      if [[ $merge_oid =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] &&
        git -C "$dir" merge-base --is-ancestor "$merge_oid" "$base_oid" 2>/dev/null; then
        merged_number=$number
      fi
    else
      closed_number=$number
    fi
  done <<<"$candidates"
  # An exact commit still under review in another PR is live work even if
  # an earlier PR landed it. Keep both merged and abandoned proofs gated.
  if [[ -n $open_number ]]; then
    printf 'open\t%s\n' "$open_number"
  elif [[ -n $merged_number ]]; then
    printf 'merged\t%s\n' "$merged_number"
  elif [[ -n $closed_number ]]; then
    printf 'closed\t%s\n' "$closed_number"
  else
    printf 'none\t-\n'
  fi
)
