# shellcheck shell=bash
# commands.sh - pull, reexec, update, and dirty-worktree coverage.

# shellcheck disable=SC2154
# Shard booleans are assigned by core-test before this sourced module runs.

dot_core_test_commands() {
  echo ""
  echo "=== Update lock ==="

  UPDATE_LOCK_MODULE="$TEST_HOME/.local/lib/dot/core/update-lock.sh"
  UPDATE_LOCK_STATE="$TEST_HOME/.local/state"
  UPDATE_LOCK_DIR="$UPDATE_LOCK_STATE/dot/update.lock.d"
  UPDATE_LOCK_READY="$TEST_HOME/update-lock-ready"

  # A re-exec stays in the same process, so it must retain its original owner
  # token rather than releasing and racing to reacquire the lock.
  result=$(HOME="$TEST_HOME" XDG_STATE_HOME="$UPDATE_LOCK_STATE" bash -c '
    . "$1"
    _dot_update_lock_acquire
    first="$DOT_UPDATE_LOCK_TOKEN"
    _dot_update_lock_acquire --cron
    printf "%s/%s" "$first" "$DOT_UPDATE_LOCK_TOKEN"
  ' _ "$UPDATE_LOCK_MODULE" 2>&1)
  _assert_eq "update lock: re-entry retains owner token" \
    "${result%%/*}/${result%%/*}" "$result"
  if [[ ! -e "$UPDATE_LOCK_DIR" ]]; then
    _pass "update lock: exit trap removes re-entered lock"
  else
    _fail "update lock: exit trap removes re-entered lock"
  fi

  # Hold a real lock in another process. The launcher must check it before
  # bootstrapping shdeps or performing any repository/configuration mutation.
  HOME="$TEST_HOME" XDG_STATE_HOME="$UPDATE_LOCK_STATE" bash -c '
    . "$1"
    _dot_update_lock_acquire
    : >"$2"
    while :; do sleep 1; done
  ' _ "$UPDATE_LOCK_MODULE" "$UPDATE_LOCK_READY" &
  UPDATE_LOCK_HOLDER_PID=$!
  for ((UPDATE_LOCK_WAIT = 0; UPDATE_LOCK_WAIT < 50; UPDATE_LOCK_WAIT++)); do
    [[ -f "$UPDATE_LOCK_READY" ]] && break
    sleep 0.1
  done
  if [[ ! -f "$UPDATE_LOCK_READY" ]]; then
    _fail "update lock: holder acquires lock"
    kill "$UPDATE_LOCK_HOLDER_PID" 2>/dev/null || true
    wait "$UPDATE_LOCK_HOLDER_PID" 2>/dev/null || true
  else
    _pass "update lock: holder acquires lock"

    result=$("$BIN_DIR/dot" update --skip-pull 2>&1 || printf 'status=%s' "$?")
    _assert_contains "update lock: interactive update reports active owner" \
      "already running" "$result"
    _assert_contains "update lock: interactive update preserves lock status" "status=75" "$result"

    result=$("$BIN_DIR/dot" update --cron 2>&1)
    _assert_eq "update lock: cron contention stays silent" "" "$result"

    kill -TERM "$UPDATE_LOCK_HOLDER_PID"
    wait "$UPDATE_LOCK_HOLDER_PID" 2>/dev/null || true
    if [[ ! -e "$UPDATE_LOCK_DIR" ]]; then
      _pass "update lock: TERM cleanup removes lock"
    else
      _fail "update lock: TERM cleanup removes lock"
    fi
  fi
  rm -f "$UPDATE_LOCK_READY"

  # SIGKILL bypasses traps. It may leave the directory behind, but the next
  # update must reclaim it only after validating the owner is no longer alive.
  HOME="$TEST_HOME" XDG_STATE_HOME="$UPDATE_LOCK_STATE" bash -c '
    . "$1"
    _dot_update_lock_acquire
    : >"$2"
    while :; do sleep 1; done
  ' _ "$UPDATE_LOCK_MODULE" "$UPDATE_LOCK_READY" &
  UPDATE_LOCK_HOLDER_PID=$!
  for ((UPDATE_LOCK_WAIT = 0; UPDATE_LOCK_WAIT < 50; UPDATE_LOCK_WAIT++)); do
    [[ -f "$UPDATE_LOCK_READY" ]] && break
    sleep 0.1
  done
  kill -KILL "$UPDATE_LOCK_HOLDER_PID" 2>/dev/null || true
  wait "$UPDATE_LOCK_HOLDER_PID" 2>/dev/null || true
  if [[ -d "$UPDATE_LOCK_DIR" ]]; then
    _pass "update lock: SIGKILL leaves recoverable state"
  else
    _fail "update lock: SIGKILL leaves recoverable state"
  fi
  rm -f "$UPDATE_LOCK_READY"

  result=$(HOME="$TEST_HOME" XDG_STATE_HOME="$UPDATE_LOCK_STATE" bash -c '
    . "$1"
    _dot_update_lock_acquire
    printf "reclaimed"
  ' _ "$UPDATE_LOCK_MODULE" 2>&1)
  _assert_eq "update lock: stale owner is reclaimed" "reclaimed" "$result"
  if [[ ! -e "$UPDATE_LOCK_DIR" ]]; then
    _pass "update lock: reclaimed state is removed on exit"
  else
    _fail "update lock: reclaimed state is removed on exit"
  fi

  # A process can be killed between mkdir and its owner write. That empty
  # directory must not become a permanent lock after the initialization grace.
  mkdir -p "$UPDATE_LOCK_DIR"
  touch -t 200001010000 "$UPDATE_LOCK_DIR"
  result=$(HOME="$TEST_HOME" XDG_STATE_HOME="$UPDATE_LOCK_STATE" bash -c '
    . "$1"
    _dot_update_lock_acquire
    printf "reclaimed-empty"
  ' _ "$UPDATE_LOCK_MODULE" 2>&1)
  _assert_eq "update lock: abandoned initialization is reclaimed" "reclaimed-empty" "$result"
  if [[ ! -e "$UPDATE_LOCK_DIR" ]]; then
    _pass "update lock: abandoned initialization is removed on exit"
  else
    _fail "update lock: abandoned initialization is removed on exit"
  fi

  echo ""
  echo "=== Pull command ==="

  dot_fixture_remote_from_base REMOTE_BARE
  dot_fixture_shdeps_tool_origin TEST_TOOL_ORIGIN
  dot_fixture_shdeps_hook_pack_origin HOOK_PACK_ORIGIN
  dot_fixture_shdeps_overlay_tool_origin OVERLAY_TOOL_ORIGIN

  _saved_deps=$(cat "$TEST_HOME/.config/shdeps/deps.conf")
  _saved_overlay_conf="$TEST_HOME/.config/dot/overlays.d/10-work.conf"

  if { $_core_run_pull || $_core_run_reexec; }; then
    # Pull tests don't need shdeps — empty deps.conf avoids the cost.
    # The update tests below verify shdeps integration.
    : >"$TEST_HOME/.config/shdeps/deps.conf"

    # Remove overlay conf so pull doesn't try to clone from example.com over SSH
    # (which hangs waiting for connection timeout). Overlay pull is tested above.
    mv "$_saved_overlay_conf" "$_saved_overlay_conf.bak"

    if $_core_run_pull; then
      _republished_base_fixture() {
        local remote_tree="${1:-matching}" dirty="${2:-clean}"
        local repo_state="${3:-normal}"
        local attempt_mode="${4:-once}"
        local fixture_home fixture_dotfiles fixture_git branch local_branch
        local old_origin new_origin remote_work operation_path pull_log pull_output
        local pull_invoked_file
        local old_head old_tree new_root remote_tip root_one root_two raced_root
        local rc=0 first_rc=0 first_status='' rebase_state=no clean=yes
        fixture_home=$(_tmpdir)
        fixture_dotfiles="$fixture_home/.dotfiles"
        fixture_git="git --git-dir=$fixture_dotfiles --work-tree=$fixture_home"
        old_origin=$(_tmpdir)
        new_origin=$(_tmpdir)

        git init --bare "$fixture_dotfiles" >/dev/null 2>&1
        # shellcheck disable=SC2086  # fixture_git is an intentional command prefix.
        _git_set_test_identity $fixture_git
        printf '%s\n' initial >"$fixture_home/managed-file"
        $fixture_git add managed-file
        $fixture_git commit -m "old root" >/dev/null 2>&1
        printf '%s\n' final >"$fixture_home/managed-file"
        $fixture_git commit -am "old update" >/dev/null 2>&1
        old_head=$($fixture_git rev-parse HEAD)
        old_tree=$($fixture_git rev-parse 'HEAD^{tree}')
        branch=$($fixture_git branch --show-current)
        local_branch="$branch"
        if [[ "$repo_state" == "feature" ]]; then
          local_branch="feature/cutover"
          $fixture_git branch -m "$local_branch"
        fi

        git init --bare "$old_origin" >/dev/null 2>&1
        $fixture_git push "$old_origin" "$old_head:refs/heads/$branch" >/dev/null 2>&1
        git --git-dir="$old_origin" symbolic-ref HEAD "refs/heads/$branch"
        $fixture_git remote add origin "$old_origin"
        $fixture_git config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
        $fixture_git fetch origin >/dev/null 2>&1
        $fixture_git config "branch.$local_branch.remote" origin
        $fixture_git config "branch.$local_branch.merge" "refs/heads/$branch"
        if [[ "$repo_state" == "prefetched" ]]; then
          HOME="$fixture_home" GIT="$fixture_git" _seed_republished_base_anchor
        fi
        if [[ "$repo_state" == "ahead" ]]; then
          $fixture_git commit --allow-empty -m "unpushed local commit" >/dev/null 2>&1
          old_head=$($fixture_git rev-parse HEAD)
        fi

        git init --bare "$new_origin" >/dev/null 2>&1
        if [[ "$remote_tree" == "matching" || "$remote_tree" == "matching-update" ]]; then
          new_root=$(printf '%s\n' "new public root" | $fixture_git commit-tree "$old_tree")
          $fixture_git push "$new_origin" "$new_root:refs/heads/$branch" >/dev/null 2>&1
        elif [[ "$remote_tree" == "multiple" ]]; then
          root_one=$(printf '%s\n' "first public root" | $fixture_git commit-tree "$old_tree")
          root_two=$(printf '%s\n' "second public root" | $fixture_git commit-tree "$old_tree")
          new_root=$(printf '%s\n' "join public roots" |
            $fixture_git commit-tree "$old_tree" -p "$root_one" -p "$root_two")
          $fixture_git push "$new_origin" "$new_root:refs/heads/$branch" >/dev/null 2>&1
        else
          remote_work=$(_tmpdir)
          git -C "$remote_work" init -b "$branch" >/dev/null 2>&1
          _git_set_test_identity git -C "$remote_work"
          printf '%s\n' different >"$remote_work/managed-file"
          git -C "$remote_work" add managed-file
          git -C "$remote_work" commit -m "different public root" >/dev/null 2>&1
          new_root=$(git -C "$remote_work" rev-parse HEAD)
          git -C "$remote_work" remote add origin "$new_origin"
          git -C "$remote_work" push origin "$branch" >/dev/null 2>&1
        fi
        git --git-dir="$new_origin" symbolic-ref HEAD "refs/heads/$branch"
        if [[ "$remote_tree" == "matching-update" ]]; then
          remote_work=$(_tmpdir)
          dot_fixture_clone_repo "$new_origin" "$remote_work"
          printf '%s\n' "public update" >"$remote_work/managed-file"
          git -C "$remote_work" commit -am "update public history" >/dev/null 2>&1
          git -C "$remote_work" push >/dev/null 2>&1
        fi
        remote_tip=$(git --git-dir="$new_origin" rev-parse "refs/heads/$branch")
        $fixture_git remote set-url origin "$new_origin"
        if [[ "$repo_state" == "prefetched" ]]; then
          $fixture_git fetch origin >/dev/null 2>&1
        fi
        $fixture_git config pull.rebase true
        $fixture_git config rebase.autoStash true
        if [[ "$dirty" == "dirty" ]]; then
          printf '%s\n' "local edit" >"$fixture_home/managed-file"
        fi
        if [[ "$repo_state" == "rebase" ]]; then
          operation_path=$($fixture_git rev-parse --git-path rebase-merge)
          mkdir -p "$operation_path"
        fi

        local HOME="$fixture_home" GIT="$fixture_git"
        # shellcheck disable=SC2034  # read dynamically by _pull_cmd.
        local DOT_QUIET=0
        pull_log="$fixture_home/pull.log"
        pull_invoked_file="$fixture_home/pull-invoked"
        if [[ "$repo_state" == "race" ]]; then
          eval "$(declare -f _pull_repo | sed '1s/_pull_repo/_fixture_pull_repo/')"
          # shellcheck disable=SC2329  # invoked dynamically by _pull_base.
          _pull_repo() {
            raced_root=$(printf '%s\n' "raced public root" |
              $fixture_git commit-tree "$old_tree")
            $fixture_git push --force "$new_origin" \
              "$raced_root:refs/heads/$branch" >/dev/null 2>&1
            _fixture_pull_repo "$@"
          }
        fi
        if [[ "$repo_state" == "fetch-failure" ]]; then
          $fixture_git remote set-url origin "$fixture_home/missing-origin"
          # shellcheck disable=SC2329  # invoked dynamically by _pull_base.
          _pull_repo() {
            : >"$pull_invoked_file"
            return 0
          }
        elif [[ "$repo_state" == "merge-failure" ]]; then
          # shellcheck disable=SC2329  # invoked dynamically by _pull_base.
          _pull_repo() { return 1; }
        fi
        if [[ "$attempt_mode" == "retry" ]]; then
          _pull_base >"$pull_log" 2>&1 || first_rc=$?
          pull_output=$(cat "$pull_log")
          first_status="$REPLY_STATUS"
          printf '%s\n' final >"$fixture_home/managed-file"
          $fixture_git update-index --refresh >/dev/null 2>&1
        fi
        _pull_base >"$pull_log" 2>&1 || rc=$?
        pull_output=$(cat "$pull_log")

        [[ ! -d "$($fixture_git rev-parse --git-path rebase-merge)" &&
        ! -d "$($fixture_git rev-parse --git-path rebase-apply)" ]] || rebase_state=yes
        $fixture_git diff-index --quiet HEAD -- || clean=no
        printf 'rc=%s\nstatus=%s\nfirst_rc=%s\nfirst_status=%s\nold=%s\nroot=%s\ntip=%s\nhead=%s\nrebase=%s\nclean=%s\ncontent=%s\npull_invoked=%s\ncandidate_refs=%s\noutput=%s\n' \
          "$rc" "$REPLY_STATUS" "$first_rc" "$first_status" \
          "$old_head" "$new_root" "$remote_tip" \
          "$($fixture_git rev-parse HEAD)" "$rebase_state" "$clean" \
          "$(cat "$fixture_home/managed-file")" \
          "$([[ -e "$pull_invoked_file" ]] && printf yes || printf no)" \
          "$($fixture_git for-each-ref --format='%(refname)' refs/dot/republished-candidate | wc -l | tr -d '[:space:]')" \
          "$pull_output"
      }

      republished_result=$(_republished_base_fixture)
      _assert_contains "pull republished base: succeeds" "rc=0" "$republished_result"
      _assert_contains "pull republished base: reports changed" \
        "status=changed" "$republished_result"
      republished_root=$(sed -n 's/^root=//p' <<<"$republished_result")
      _assert_contains "pull republished base: adopts new root" \
        "head=$republished_root" "$republished_result"
      _assert_contains "pull republished base: leaves no rebase" \
        "rebase=no" "$republished_result"
      _assert_contains "pull republished base: leaves worktree clean" \
        "clean=yes" "$republished_result"
      _assert_contains "pull republished base: removes candidate ref" \
        "candidate_refs=0" "$republished_result"

      republished_fetch_failure=$(_republished_base_fixture matching clean fetch-failure)
      fetch_failure_old=$(sed -n 's/^old=//p' <<<"$republished_fetch_failure")
      _assert_contains "pull republished base fetch failure: blocks" \
        "status=blocked" "$republished_fetch_failure"
      _assert_contains "pull republished base fetch failure: skips ordinary pull" \
        "pull_invoked=no" "$republished_fetch_failure"
      _assert_contains "pull republished base fetch failure: preserves old head" \
        "head=$fetch_failure_old" "$republished_fetch_failure"

      republished_mismatch=$(_republished_base_fixture different)
      mismatch_old=$(sed -n 's/^old=//p' <<<"$republished_mismatch")
      _assert_contains "pull republished base mismatch: fails" \
        "rc=1" "$republished_mismatch"
      _assert_contains "pull republished base mismatch: reports bridge refusal" \
        "root tree differs from HEAD" "$republished_mismatch"
      _assert_contains "pull republished base mismatch: preserves old head" \
        "head=$mismatch_old" "$republished_mismatch"
      _assert_contains "pull republished base mismatch: starts no rebase" \
        "rebase=no" "$republished_mismatch"
      _assert_contains "pull republished base mismatch: leaves worktree clean" \
        "clean=yes" "$republished_mismatch"

      republished_dirty=$(_republished_base_fixture matching dirty)
      dirty_old=$(sed -n 's/^old=//p' <<<"$republished_dirty")
      _assert_contains "pull republished base dirty: fails" "rc=1" "$republished_dirty"
      _assert_contains "pull republished base dirty: preserves old head" \
        "head=$dirty_old" "$republished_dirty"
      _assert_contains "pull republished base dirty: starts no rebase" \
        "rebase=no" "$republished_dirty"
      _assert_contains "pull republished base dirty: preserves local edit" \
        "clean=no" "$republished_dirty"

      republished_retry=$(_republished_base_fixture matching dirty normal retry)
      retry_root=$(sed -n 's/^root=//p' <<<"$republished_retry")
      _assert_contains "pull republished base retry: first attempt fails" \
        "first_rc=1" "$republished_retry"
      _assert_contains "pull republished base retry: succeeds after cleanup" \
        "rc=0" "$republished_retry"
      _assert_contains "pull republished base retry: adopts new root" \
        "head=$retry_root" "$republished_retry"

      republished_prefetched=$(_republished_base_fixture matching clean prefetched)
      prefetched_root=$(sed -n 's/^root=//p' <<<"$republished_prefetched")
      _assert_contains "pull republished base prefetched: succeeds" \
        "rc=0" "$republished_prefetched"
      _assert_contains "pull republished base prefetched: adopts new root" \
        "head=$prefetched_root" "$republished_prefetched"

      republished_update=$(_republished_base_fixture matching-update)
      update_tip=$(sed -n 's/^tip=//p' <<<"$republished_update")
      _assert_contains "pull republished base update: succeeds" "rc=0" "$republished_update"
      _assert_contains "pull republished base update: reaches public tip" \
        "head=$update_tip" "$republished_update"
      _assert_contains "pull republished base update: applies public content" \
        "content=public update" "$republished_update"
      _assert_contains "pull republished base update: leaves worktree clean" \
        "clean=yes" "$republished_update"

      republished_race=$(_republished_base_fixture matching clean race)
      race_tip=$(sed -n 's/^tip=//p' <<<"$republished_race")
      _assert_contains "pull republished base race: succeeds" "rc=0" "$republished_race"
      _assert_contains "pull republished base race: integrates validated tip" \
        "head=$race_tip" "$republished_race"
      _assert_contains "pull republished base race: starts no rebase" \
        "rebase=no" "$republished_race"

      republished_merge_failure=$(_republished_base_fixture matching clean merge-failure)
      _assert_contains "pull republished base merge failure: blocks cron" \
        "status=blocked" "$republished_merge_failure"

      republished_multiple=$(_republished_base_fixture multiple)
      multiple_old=$(sed -n 's/^old=//p' <<<"$republished_multiple")
      _assert_contains "pull republished base multiple roots: fails" \
        "rc=1" "$republished_multiple"
      _assert_contains "pull republished base multiple roots: preserves old head" \
        "head=$multiple_old" "$republished_multiple"
      _assert_contains "pull republished base multiple roots: starts no rebase" \
        "rebase=no" "$republished_multiple"

      republished_feature=$(_republished_base_fixture matching clean feature)
      feature_old=$(sed -n 's/^old=//p' <<<"$republished_feature")
      _assert_contains "pull republished base feature branch: fails" \
        "rc=1" "$republished_feature"
      _assert_contains "pull republished base feature branch: preserves old head" \
        "head=$feature_old" "$republished_feature"
      _assert_contains "pull republished base feature branch: starts no rebase" \
        "rebase=no" "$republished_feature"

      republished_ahead=$(_republished_base_fixture matching clean ahead)
      ahead_old=$(sed -n 's/^old=//p' <<<"$republished_ahead")
      _assert_contains "pull republished base unpushed commit: fails" \
        "rc=1" "$republished_ahead"
      _assert_contains "pull republished base unpushed commit: preserves old head" \
        "head=$ahead_old" "$republished_ahead"
      _assert_contains "pull republished base unpushed commit: starts no rebase" \
        "rebase=no" "$republished_ahead"

      republished_rebase=$(_republished_base_fixture matching clean rebase)
      rebase_old=$(sed -n 's/^old=//p' <<<"$republished_rebase")
      _assert_contains "pull republished base active rebase: fails" \
        "rc=1" "$republished_rebase"
      _assert_contains "pull republished base active rebase: reports bridge refusal" \
        "another Git operation is in progress" "$republished_rebase"
      _assert_contains "pull republished base active rebase: preserves old head" \
        "head=$rebase_old" "$republished_rebase"
      unset -f _republished_base_fixture

      quiet_policy_rc=0
      (
        # shellcheck disable=SC2329  # invoked dynamically by _repo_pull_all.
        _ensure_repo_config() { :; }
        # shellcheck disable=SC2329  # invoked dynamically by _repo_pull_all.
        _normalize_filtered() { :; }
        # shellcheck disable=SC2329  # invoked dynamically by _repo_pull_all.
        _unstash_overlay_overrides() { return 0; }
        # shellcheck disable=SC2329  # invoked dynamically by _repo_pull_all.
        _pull_overlay_count() { printf '0\n'; }
        # shellcheck disable=SC2329  # invoked dynamically by _repo_pull_all.
        _pull_base() {
          REPLY_STATUS=blocked
          return 1
        }
        # shellcheck disable=SC2034,SC2329  # outputs are read dynamically by the caller.
        _pull_overlays() {
          DOT_PULL_OVERLAY_CURRENT=0
          DOT_PULL_OVERLAY_CHANGED=0
          DOT_PULL_OVERLAY_FAILED=0
          DOT_PULL_OVERLAY_SKIPPED=0
          return 0
        }
        DOT_QUIET=1 DOT_VERBOSE=0 _repo_pull_all >/dev/null 2>&1
      ) || quiet_policy_rc=$?
      _assert_eq "pull republished base policy refusal: fails in quiet mode" \
        "1" "$quiet_policy_rc"

      reexec_seed_marker=$(_tmpdir)/seeded
      (
        # shellcheck disable=SC2329  # invoked dynamically by _dot_update_sync_repos.
        _seed_republished_base_anchor() { : >"$reexec_seed_marker"; }
        DOT_REEXEC=1 _dot_update_sync_repos 1 1
      )
      _assert_file_exists "pull republished base reexec: seeds history anchor" \
        "$reexec_seed_marker"

      result=$(DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 SHELL=/bin/bash "$BIN_DIR/dot" pull 2>&1)
      _assert_contains "pull: shows repos dashboard row" "[1/5] Repos" "$result"
      _assert_contains "pull: shows repos status" "ok" "$result"
      _assert_contains "pull: repos progress names base repo" \
        "dotfiles           [########] 1/1" "$result"
      _assert_contains "pull: summarizes repos numerically" "1 repo current" "$result"
      _assert_not_contains "pull: avoids named repo summary" "dotfiles current" "$result"
      _assert_not_contains "pull: hides raw git current output" "Current branch" "$result"
      _assert_not_contains "pull: hides raw git up-to-date output" "Already up to date" "$result"
      _assert_contains "pull: shows done message" "Done" "$result"
      _assert_contains "pull: mentions shell activation hint" "Reload your shell: source ~/.bashrc" "$result"

      PULL_REMOTE_WORK=$(_tmpdir)
      dot_fixture_clone_repo "$REMOTE_BARE" "$PULL_REMOTE_WORK"
      printf '%s\n' "remote update" >>"$PULL_REMOTE_WORK/.testrc"
      git -C "$PULL_REMOTE_WORK" add .testrc
      git -C "$PULL_REMOTE_WORK" commit -m "update testrc" >/dev/null 2>&1
      git -C "$PULL_REMOTE_WORK" push >/dev/null 2>&1

      result=$(DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 SHELL=/bin/bash "$BIN_DIR/dot" pull 2>&1)
      _assert_contains "pull changed: marks repos stage changed" \
        "Repos      changed" "$result"
      _assert_contains "pull changed: summarizes changed repo count" \
        "1 repo changed" "$result"
      _assert_contains "pull changed: prints changed repo detail" \
        "changed  dotfiles updated" "$result"

      # Exercise verbose repo-row rendering without another full `dot pull -v`
      # subprocess. The end-to-end verbose parser path is already covered by
      # the reexec test below; this keeps the full suite runtime stable while
      # still guarding the moved `_repo_pull_all` verbose behavior.
      result=$(
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _ensure_repo_config() { :; }
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _normalize_filtered() { :; }
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _unstash_overlay_overrides() { :; }
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _pull_overlay_count() { printf '0'; }
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _pull_base() {
          # shellcheck disable=SC2034  # read by _repo_pull_all in the runtime.
          REPLY_STATUS=current
          return 0
        }
        # shellcheck disable=SC2329  # invoked indirectly by _repo_pull_all.
        _pull_overlays() {
          REPLY=""
        }
        DOT_VERBOSE=1 DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 _ui_begin 5
        DOT_VERBOSE=1 DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 _repo_pull_all 2>&1
      )
      _assert_contains "pull verbose: shows base repo running status" \
        "dotfiles: pulling" "$result"
      _assert_contains "pull verbose: shows base repo current status" \
        "dotfiles current" "$result"

      FEATURE_BRANCH="feature/no-upstream"
      $GIT checkout -b "$FEATURE_BRANCH" >/dev/null 2>&1
      result=$(DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 SHELL=/bin/bash "$BIN_DIR/dot" pull 2>&1)
      $GIT checkout "$DEFAULT_BRANCH" >/dev/null 2>&1
      _assert_contains "pull feature branch: keeps update running" "[3/5] Tools" "$result"
      _assert_contains "pull feature branch: reports skipped repo numerically" \
        "1 repo skipped" "$result"
      _assert_not_contains "pull feature branch: hides missing upstream error" \
        "There is no tracking information" "$result"
      _assert_not_contains "pull feature branch: does not fail repos stage" \
        "Repos      failed" "$result"

      dot_fixture_file_origin PULL_OVERLAY_BARE "work-file" "pull overlay content"
      PULL_OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
      rm -rf "$PULL_OVERLAY_DIR"
      dot_fixture_clone_repo "$PULL_OVERLAY_BARE" "$PULL_OVERLAY_DIR"
      cat >"$_saved_overlay_conf" <<CONF
url=$TEST_HOME/missing-overlay-origin
CONF
      git -C "$PULL_OVERLAY_DIR" remote set-url origin "$TEST_HOME/missing-overlay-origin"
      result=$(DOT_UI_FORCE_LIVE=1 DOT_UI_ASCII=1 SHELL=/bin/bash "$BIN_DIR/dot" pull 2>&1 || true)
      _assert_contains "pull overlay failure: marks repos stage failed" \
        "Repos      failed" "$result"
      _assert_contains "pull overlay failure: reports failed repo count" \
        "1 repo failed" "$result"
      rm -f "$_saved_overlay_conf"
      rm -rf "$PULL_OVERLAY_DIR" "$PULL_OVERLAY_BARE"

      # Upstream starts tracking a file that exists locally as untracked → backup and continue.
      REMOTE_WORK=$(_tmpdir)
      dot_fixture_clone_repo "$REMOTE_BARE" "$REMOTE_WORK"
      mkdir -p "$REMOTE_WORK/.config/nvim"
      printf '%s\n' "remote-lock" >"$REMOTE_WORK/.config/nvim/lazy-lock.json"
      git -C "$REMOTE_WORK" add .config/nvim/lazy-lock.json
      git -C "$REMOTE_WORK" commit -m "track lazy lock" >/dev/null 2>&1
      git -C "$REMOTE_WORK" push >/dev/null 2>&1

      mkdir -p "$TEST_HOME/.config/nvim"
      printf '%s\n' "local-lock" >"$TEST_HOME/.config/nvim/lazy-lock.json"

      result=$("$BIN_DIR/dot" pull 2>&1)
      _assert_contains "pull: backs up tracked-file adoption conflict" "backed up 1 conflicting untracked files" "$result"
      _assert_file_content "pull: installs tracked file after backup" "remote-lock" "$TEST_HOME/.config/nvim/lazy-lock.json"

      backup_lock=$(find "$TEST_HOME/.dotfiles-backup" -path '*/.config/nvim/lazy-lock.json' -print | head -1)
      if [[ -n "$backup_lock" ]]; then
        _assert_file_content "pull: preserves local untracked file in backup" "local-lock" "$backup_lock"
      else
        _fail "pull: preserves local untracked file in backup (backup file not found)"
      fi
    fi

    if $_core_run_reexec; then
      _seed_infra_update() {
        local _stamp="$1" _work
        _work=$(_tmpdir)
        dot_fixture_clone_repo "$REMOTE_BARE" "$_work"
        mkdir -p "$_work/.local/bin"
        printf '%s\n' "#!/usr/bin/env bash" "# $_stamp" >"$_work/.local/bin/dot"
        git -C "$_work" add .local/bin/dot
        git -C "$_work" commit -m "touch dot infrastructure $_stamp" >/dev/null 2>&1
        git -C "$_work" push >/dev/null 2>&1
      }

      _seed_infra_update nonverbose
      result=$("$BIN_DIR/dot" update 2>&1)
      _assert_not_contains "update reexec: suppresses raw infrastructure banner" \
        "==> Dot infrastructure updated" "$result"
      _assert_not_contains "update reexec: hides skipped second pull implementation detail" \
        "pull skipped after infrastructure update" "$result"
      _repo_row_count=$(printf '%s\n' "$result" | grep -c '^\[1/5\] Repos[[:space:]]\+\(ok\|changed\)[[:space:]]')
      _assert_eq "update reexec: only prints one repos row" "1" "$_repo_row_count"
      _assert_contains "update reexec: reports updated base repo" \
        "changed  dotfiles updated" "$result"
      _assert_contains "update reexec: keeps later stage numbers stable" \
        "[3/5] Tools" "$result"

      _seed_infra_update verbose
      result=$("$BIN_DIR/dot" update -v 2>&1)
      _assert_not_contains "update reexec verbose: suppresses raw infrastructure banner" \
        "==> Dot infrastructure updated" "$result"
      _assert_not_contains "update reexec verbose: hides skipped second pull implementation detail" \
        "pull skipped after infrastructure update" "$result"
      _assert_contains "update reexec verbose: uses a status row" \
        "changed  dot infrastructure updated, re-running" "$result"
    fi

    # Restore deps.conf for update tests (overlay conf stays removed —
    # update/push don't test overlay behavior and the example.com URL hangs).
    printf '%s\n' "$_saved_deps" >"$TEST_HOME/.config/shdeps/deps.conf"
    if ! $_core_run_update && [[ -f "$_saved_overlay_conf.bak" ]]; then
      mv "$_saved_overlay_conf.bak" "$_saved_overlay_conf"
    fi
  fi

  if $_core_run_update; then
    # ---------------------------------------------------------------------------
    # Tests: simple multi-repo commands
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Simple repo commands ==="

    # These commands should operate on the base repo plus overlays that already
    # exist locally. Missing overlays are intentionally skipped here; only
    # pull/update may clone an overlay.
    dot_fixture_file_origin SIMPLE_OVERLAY_BARE "work-file" "work content"
    SIMPLE_OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
    rm -rf "$SIMPLE_OVERLAY_DIR"
    dot_fixture_clone_repo "$SIMPLE_OVERLAY_BARE" "$SIMPLE_OVERLAY_DIR"
    cat >"$_saved_overlay_conf" <<CONF
url=$SIMPLE_OVERLAY_BARE
CONF
    _discover_overlays

    result=$("$BIN_DIR/dot" fetch 2>&1)
    _assert_contains "fetch: shows base repo" "Fetching dotfiles" "$result"
    _assert_contains "fetch: shows cloned overlay" "Fetching work dotfiles" "$result"

    result=$("$BIN_DIR/dot" push 2>&1)
    _assert_contains "push: shows base repo" "Pushing dotfiles" "$result"
    _assert_contains "push: shows cloned overlay" "Pushing work dotfiles" "$result"

    printf '%s\n' "changed" >>"$SIMPLE_OVERLAY_DIR/work-file"
    result=$("$BIN_DIR/dot" status --short 2>&1)
    _assert_contains "status: shows base repo" "==> dotfiles" "$result"
    _assert_contains "status: shows cloned overlay" "==> work dotfiles" "$result"
    _assert_contains "status: includes overlay status" " M work-file" "$result"

    result=$("$BIN_DIR/dot" diff 2>&1)
    _assert_contains "diff: shows base repo" "==> dotfiles" "$result"
    _assert_contains "diff: shows cloned overlay" "==> work dotfiles" "$result"
    _assert_contains "diff: includes overlay diff" "+changed" "$result"

    rm -rf "$SIMPLE_OVERLAY_DIR"
    result=$("$BIN_DIR/dot" status --short 2>&1)
    _assert_contains "status missing overlay: still shows base repo" "==> dotfiles" "$result"
    _assert_not_contains "status missing overlay: skips configured missing overlay" \
      "==> work dotfiles" "$result"

    result=$("$BIN_DIR/dot" push 2>&1)
    _assert_contains "push missing overlay: still shows base repo" "Pushing dotfiles" "$result"
    _assert_not_contains "push missing overlay: skips configured missing overlay" \
      "Pushing work dotfiles" "$result"

    rm -rf "$SIMPLE_OVERLAY_BARE"

    # Update/push tests don't need overlay pulls, and the default example.com URL
    # would otherwise hang waiting for SSH connection timeout.
    if [[ -f "$_saved_overlay_conf" ]]; then
      mv "$_saved_overlay_conf" "$_saved_overlay_conf.bak"
    fi

    # ---------------------------------------------------------------------------
    # Tests: dot push (with mock remote)
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Push command ==="

    result=$("$BIN_DIR/dot" push 2>&1)
    _assert_contains "push: shows pushing" "Pushing dotfiles" "$result"

    # ---------------------------------------------------------------------------
    # Tests: dot update (with mock remote + deps)
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Update command ==="

    # Update with repo: pulls, runs merges, updates deps, shows done
    result=$(
      SHDEPS_TEST_TOOL_REPO="$TEST_TOOL_ORIGIN" \
        SHDEPS_HOOK_PACK_REPO="$HOOK_PACK_ORIGIN" \
        "$BIN_DIR/dot" update 2>&1
    )
    _assert_contains "update: shows repos stage" "[1/5] Repos" "$result"
    _assert_contains "update: shows overlays stage" "[2/5] Overlays" "$result"
    _assert_contains "update: shows tools stage" "[3/5] Tools" "$result"
    _assert_contains "update: shows tools status" "Tools" "$result"
    _assert_not_contains "update: hides raw git current output" "Current branch" "$result"
    _assert_not_contains "update: hides raw git up-to-date output" "Already up to date" "$result"
    _assert_contains "update: shows done" "Done" "$result"
    _assert_file_exists "update: generic tool install dir exists" "$TEST_HOME/.local/share/fixture/test-tool/bin/test-tool"
    _assert_file_exists "update: generic tool linked into PATH" "$TEST_HOME/.local/bin/test-tool"
    _assert_file_content "update: generic hook ran" "$TEST_HOME/.local/share/fixture/hook-pack" "$TEST_HOME/.test-hooks/hook-pack"

    finalize_marker_dir=$(_tmpdir)
    finalize_rc=0
    (
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_repo_config() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _link_overlays() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_shdeps() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_shdeps_update_ui() { return 1; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _shdeps_print_group_summaries() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_merges() { : >"$finalize_marker_dir/merges"; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _normalize_filtered() { : >"$finalize_marker_dir/cleanup"; }
      DOT_QUIET=1 DOT_UI_TOTAL=0 _dot_update_finalize
    ) || finalize_rc=$?
    _assert_exit "update finalize: dependency failure is nonzero" \
      1 "$finalize_rc"
    _assert_file_exists "update finalize: dependency failure still runs merges" \
      "$finalize_marker_dir/merges"
    _assert_file_exists "update finalize: dependency failure still runs cleanup" \
      "$finalize_marker_dir/cleanup"

    overlay_marker_dir=$(_tmpdir)
    overlay_rc=0
    (
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_repo_config() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _link_overlays() { return 1; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_shdeps() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_shdeps_update_ui() { return 0; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _shdeps_print_group_summaries() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_merges() { : >"$overlay_marker_dir/merges"; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _normalize_filtered() { : >"$overlay_marker_dir/cleanup"; }
      DOT_QUIET=1 DOT_UI_TOTAL=0 _dot_update_finalize
    ) || overlay_rc=$?
    _assert_exit "update finalize: overlay link failure is nonzero" \
      1 "$overlay_rc"
    _assert_file_exists "update finalize: overlay failure still runs merges" \
      "$overlay_marker_dir/merges"
    _assert_file_exists "update finalize: overlay failure still runs cleanup" \
      "$overlay_marker_dir/cleanup"

    warning_rc=0
    (
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_repo_config() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _link_overlays() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _ensure_shdeps() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_shdeps_update_ui() {
        # shellcheck disable=SC2034  # consumed dynamically by the finalizer.
        DOT_UI_SHDEPS_STATUS=warning
        # shellcheck disable=SC2034  # consumed dynamically by the finalizer.
        DOT_UI_SHDEPS_SUMMARY="1 warning, 2 current"
        return 0
      }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _shdeps_print_group_summaries() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _run_merges() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update finalization.
      _normalize_filtered() { :; }
      DOT_QUIET=1 DOT_UI_TOTAL=0 _dot_update_finalize
    ) || warning_rc=$?
    _assert_exit "update finalize: dependency warning remains successful" \
      0 "$warning_rc"

    no_base_pull_rc=0
    (
      # shellcheck disable=SC2329  # invoked dynamically by no-base update sync.
      _ensure_repo_config() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by no-base update sync.
      _pull_overlays() {
        # shellcheck disable=SC2034  # consumed dynamically by no-base update sync.
        DOT_PULL_OVERLAY_FAILED=1
        REPLY="1 repo failed"
        return 0
      }
      DOT_QUIET=1 DOT_UI_TOTAL=0 _dot_update_no_base_pull
    ) || no_base_pull_rc=$?
    _assert_exit "update no-base sync: required overlay failure is nonzero" \
      1 "$no_base_pull_rc"

    sync_marker_dir=$(_tmpdir)
    sync_rc=0
    (
      # shellcheck disable=SC2329  # invoked dynamically by update orchestration.
      _merge_overlay_ssh_configs() { :; }
      # shellcheck disable=SC2329  # invoked dynamically by update orchestration.
      _dot_update_sync_repos() { return 1; }
      # shellcheck disable=SC2329  # invoked dynamically by update orchestration.
      _dot_update_finalize() {
        printf '%s' "${1:-missing}" >"$sync_marker_dir/finalize"
        return "${1:-0}"
      }
      DOT_QUIET=1 _dot_update --skip-pull
    ) || sync_rc=$?
    _assert_exit "update orchestration: repository failure is nonzero" \
      1 "$sync_rc"
    _assert_file_exists "update orchestration: repository failure still finalizes" \
      "$sync_marker_dir/finalize"
    _assert_file_content "update orchestration: finalizer receives prior failure" \
      "1" "$sync_marker_dir/finalize"

    mkdir -p "$TEST_HOME/.local/lib/dot/core/merge-hooks"
    cat >"$TEST_HOME/.local/lib/dot/core/merge-hooks/failapp.sh" <<'MERGE'
merge() {
  return 1
}
MERGE
    update_failure_rc=0
    result=$(
      SHDEPS_TEST_TOOL_REPO="$TEST_TOOL_ORIGIN" \
        SHDEPS_HOOK_PACK_REPO="$HOOK_PACK_ORIGIN" \
        "$BIN_DIR/dot" update --skip-pull 2>&1
    ) || update_failure_rc=$?
    rm -f "$TEST_HOME/.local/lib/dot/core/merge-hooks/failapp.sh"
    _assert_exit "update launcher: preserves aggregate failure status" \
      1 "$update_failure_rc"
    _assert_contains "update launcher: reports config hook warning" \
      "Configs    warning" "$result"
    _assert_contains "update launcher: still runs cleanup after config failure" \
      "Cleanup    ok" "$result"
    _assert_contains "update launcher: completion reports errors" \
      "Done with errors in" "$result"

    dot_fixture_file_origin UPDATE_OVERLAY_BARE "work-file" "update overlay content"
    UPDATE_OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
    rm -rf "$UPDATE_OVERLAY_DIR"
    dot_fixture_clone_repo "$UPDATE_OVERLAY_BARE" "$UPDATE_OVERLAY_DIR"
    mkdir -p "$UPDATE_OVERLAY_DIR/home/.config/shdeps"
    cat >"$UPDATE_OVERLAY_DIR/home/.config/shdeps/20-overlay.conf" <<'CONF'
fixture/overlay-tool  github:repo
CONF
    cat >"$_saved_overlay_conf" <<CONF
url=$UPDATE_OVERLAY_BARE
CONF
    _discover_overlays

    result=$(
      SHDEPS_TEST_TOOL_REPO="$TEST_TOOL_ORIGIN" \
        SHDEPS_HOOK_PACK_REPO="$HOOK_PACK_ORIGIN" \
        SHDEPS_OVERLAY_TOOL_REPO="$OVERLAY_TOOL_ORIGIN" \
        "$BIN_DIR/dot" update 2>&1
    )
    _assert_contains "update overlay deps: shows overlays before tools" "[2/5] Overlays" "$result"
    _assert_contains "update overlay deps: shows tools after overlays" "[3/5] Tools" "$result"
    _assert_file_exists "update overlay deps: overlay config linked before tools" "$TEST_HOME/.config/shdeps/20-overlay.conf"
    _assert_file_exists "update overlay deps: overlay tool installed same run" "$TEST_HOME/.local/share/fixture/overlay-tool/bin/overlay-tool"
    _assert_file_exists "update overlay deps: overlay tool linked into PATH" "$TEST_HOME/.local/bin/overlay-tool"
    rm -f "$_saved_overlay_conf" "$TEST_HOME/.config/shdeps/20-overlay.conf"
    rm -rf "$UPDATE_OVERLAY_DIR" "$UPDATE_OVERLAY_BARE"

    # Update without bare repo: no error, no pull, still succeeds
    NO_REPO_HOME=$(_tmpdir)
    mkdir -p "$NO_REPO_HOME/.local/lib/dot/core"
    cp "$REAL_HOME/.local/lib/dot/core/"*.sh "$NO_REPO_HOME/.local/lib/dot/core/"
    cp -R "$REAL_HOME/.local/lib/dot/core/repos" "$NO_REPO_HOME/.local/lib/dot/core/"
    # Non-doctor commands must not require the optional doctor section modules.
    mkdir -p "$NO_REPO_HOME/.config/shdeps"
    cp "$TEST_HOME/.config/shdeps/deps.conf" "$NO_REPO_HOME/.config/shdeps/deps.conf"
    cp -r "$TEST_HOME/.config/shdeps/hooks.d" "$NO_REPO_HOME/.config/shdeps/hooks.d"

    result=$(
      HOME="$NO_REPO_HOME" \
        SHDEPS_TEST_TOOL_REPO="$TEST_TOOL_ORIGIN" \
        SHDEPS_HOOK_PACK_REPO="$HOOK_PACK_ORIGIN" \
        "$BIN_DIR/dot" update 2>&1
    )
    _assert_contains "update no-repo: shows repos stage" "[1/5] Repos" "$result"
    _assert_contains "update no-repo: reports no base repo" "no base repo" "$result"
    _assert_contains "update no-repo: shows overlays stage" "[2/5] Overlays" "$result"
    _assert_contains "update no-repo: shows tools stage" "[3/5] Tools" "$result"
    _assert_contains "update no-repo: shows tools status" "Tools" "$result"
    _assert_contains "update no-repo: shows done" "Done" "$result"
    _assert_file_exists "update no-repo: generic tool installed" "$NO_REPO_HOME/.local/share/fixture/test-tool/bin/test-tool"
    _assert_file_content "update no-repo: generic hook ran" "$NO_REPO_HOME/.local/share/fixture/hook-pack" "$NO_REPO_HOME/.test-hooks/hook-pack"

    # ---------------------------------------------------------------------------
    # Tests: _is_worktree_dirty
    # ---------------------------------------------------------------------------

    # Restore overlay conf for remaining tests (worktree dirty, cron)
    mv "$_saved_overlay_conf.bak" "$_saved_overlay_conf"

    echo ""
    echo "=== Worktree dirty check ==="

    # Clean worktree → not dirty
    if _is_worktree_dirty; then
      _fail "clean worktree: should not be dirty"
    else
      _pass "clean worktree: not dirty"
    fi

    # Modify a tracked file → dirty
    echo "dirty change" >>"$TEST_HOME/.testrc"
    if _is_worktree_dirty; then
      _pass "modified file: is dirty"
    else
      _fail "modified file: should be dirty"
    fi

    # Restore clean state
    $GIT checkout -- .testrc

    # Overlay repo dirty → dirty
    dot_fixture_file_origin OVERLAY_BARE2 "work-file" "work"
    OVERLAY_DIR="$TEST_HOME/.dotfiles-work"
    rm -rf "$OVERLAY_DIR"
    dot_fixture_clone_repo "$OVERLAY_BARE2" "$OVERLAY_DIR"

    # Re-discover with overlay present
    _discover_overlays

    # Clean overlay repo → not dirty
    if _is_worktree_dirty; then
      _fail "clean overlay repo: should not be dirty"
    else
      _pass "clean overlay repo: not dirty"
    fi

    # Modify overlay repo file → dirty
    echo "dirty" >>"$OVERLAY_DIR/work-file"
    if _is_worktree_dirty; then
      _pass "dirty overlay repo: is dirty"
    else
      _fail "dirty overlay repo: should be dirty"
    fi

    git -C "$OVERLAY_DIR" checkout -- work-file
    rm -rf "$OVERLAY_DIR" "$OVERLAY_BARE2"

    # ---------------------------------------------------------------------------
    # Tests: _checkout_dirty_files (auto-repair scopes to the dirty set)
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Dirty-file checkout ==="

    # Reverts a dirty tracked file back to HEAD...
    echo "scratch edit" >>"$TEST_HOME/.testrc"
    # ...while an untracked file must be left untouched (per-file checkout of the
    # tracked dirty set, never `checkout -- .`).
    echo "keep me" >"$TEST_HOME/.untracked-scratch"
    # shellcheck disable=SC2086  # $GIT is intentionally word-split
    _checkout_dirty_files $GIT
    if _is_worktree_dirty; then
      _fail "checkout dirty: tracked file not reverted"
    else
      _pass "checkout dirty: reverts dirty tracked file to HEAD"
    fi
    if [[ -f "$TEST_HOME/.untracked-scratch" ]]; then
      _pass "checkout dirty: leaves untracked files alone"
    else
      _fail "checkout dirty: clobbered an untracked file"
    fi
    rm -f "$TEST_HOME/.untracked-scratch"

    # ---------------------------------------------------------------------------
    # Tests: _normalize_dirty_files (mtime-only normalization is conservative)
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Dirty-file normalization ==="

    # A genuine content edit must NOT be reverted — normalization only refreshes
    # stat-dirty-but-content-clean files, never real local edits.
    echo "genuine local edit" >>"$TEST_HOME/.testrc"
    # shellcheck disable=SC2086  # $GIT is intentionally word-split
    _normalize_dirty_files $GIT
    if _is_worktree_dirty; then
      _pass "normalize: leaves genuinely-edited files untouched"
    else
      _fail "normalize: clobbered a real content edit"
    fi
    $GIT checkout -- .testrc

    # On a clean tree it is a harmless no-op.
    # shellcheck disable=SC2086
    _normalize_dirty_files $GIT
    if _is_worktree_dirty; then
      _fail "normalize: clean tree became dirty"
    else
      _pass "normalize: clean tree is a no-op"
    fi

    # ---------------------------------------------------------------------------
    # Tests: dot update --cron (skip if dirty)
    # ---------------------------------------------------------------------------

    echo ""
    echo "=== Cron mode ==="

    # Remove overlay conf so cron pull doesn't hang on example.com SSH
    mv "$_saved_overlay_conf" "$_saved_overlay_conf.bak"

    # Cron tests don't need shdeps — empty deps to avoid the cost.
    _saved_deps=$(cat "$TEST_HOME/.config/shdeps/deps.conf")
    : >"$TEST_HOME/.config/shdeps/deps.conf"

    # Dirty worktree + --cron → exits immediately (no pull)
    echo "dirty" >>"$TEST_HOME/.testrc"
    result=$("$BIN_DIR/dot" update --cron 2>&1)
    _assert_eq "cron dirty: no output (skipped)" "" "$result"
    $GIT checkout -- .testrc

    # Clean worktree + --cron → runs but stays completely silent on success.
    result=$("$BIN_DIR/dot" update --cron 2>&1)
    _assert_eq "cron clean: no output" "" "$result"

    # Non-cron callers may still request quiet output explicitly: it should
    # suppress success output but still run the normal update path. Keep this next
    # to cron coverage because both flags must be visible before shdeps bootstrap,
    # not only in the late parser.
    result=$("$BIN_DIR/dot" update --skip-pull --quiet 2>&1)
    _assert_eq "quiet update: no output" "" "$result"

    printf '%s\n' "$_saved_deps" >"$TEST_HOME/.config/shdeps/deps.conf"
    mv "$_saved_overlay_conf.bak" "$_saved_overlay_conf"
  fi
}
