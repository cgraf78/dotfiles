# shellcheck shell=bash
# shellcheck disable=SC2154  # _fzf_preview, _fzf_pick set by 56-dot.sh
# fzf-powered git workflows: branch switch, commit browse, changed-file pick.

# Fuzzy branch switcher with commit log preview.
# Deduplicates local + remote; switches to selected branch.
gbr() {
  _require_git_repo || return

  local branch
  branch=$(
    git branch -a --sort=-committerdate --format='%(refname:short)' |
      sed 's|^origin/||' | awk '!seen[$0]++' |
      fzf "${_fzf_preview[@]}" \
        --prompt="branch> " \
        --preview="git log --oneline --graph --color=always -20 {}"
  ) || return

  [[ -n "$branch" ]] || return
  git switch "$branch" 2>/dev/null || git checkout "$branch"
}

# Fuzzy commit browser with diff preview.
glo() {
  _require_git_repo || return

  local commit
  commit=$(
    git log --oneline --graph --color=always --decorate -200 |
      fzf "${_fzf_preview[@]}" --ansi \
        --prompt="commit> " \
        --preview="echo {} | grep -oE '[0-9a-f]{7,}' | head -1 | xargs git show --color=always --stat -p" |
      grep -oE '[0-9a-f]{7,}' | head -1
  ) || return

  [[ -n "$commit" ]] || return
  git show "$commit"
}

# Fuzzy changed-file picker: opens selection in editor.
gst() {
  _require_git_repo || return

  local file
  file=$(
    git -c color.status=always status --short |
      fzf "${_fzf_preview[@]}" --ansi \
        --prompt="changed> " \
        --preview="
          f=\$(echo {} | sed 's/\x1b\[[0-9;]*m//g; s/^...//')
          git diff --color=always -- \"\$f\" 2>/dev/null
          git diff --cached --color=always -- \"\$f\" 2>/dev/null
        "
  ) || return

  [[ -n "$file" ]] || return
  file=$(echo "$file" | sed 's/\x1b\[[0-9;]*m//g; s/^...//')
  _edit_file "$file"
}

# Fuzzy stash picker with diff preview.
gstash() {
  _require_git_repo || return

  local entry stash_id
  entry=$(
    git stash list --color=always |
      fzf "${_fzf_preview[@]}" --ansi \
        --prompt="stash> " \
        --preview="echo {} | grep -oE 'stash@\{[0-9]+\}' | xargs git stash show -p --color=always"
  ) || return

  stash_id=$(echo "$entry" | grep -oE 'stash@\{[0-9]+\}')
  [[ -n "$stash_id" ]] || return

  printf 'Apply %s? [y/N] ' "$stash_id"
  read -r reply
  [[ "$reply" =~ ^[Yy] ]] && git stash pop "$stash_id"
}
