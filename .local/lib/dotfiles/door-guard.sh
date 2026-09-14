#!/usr/bin/env bash
# shellcheck shell=bash
# door-guard: pre-update safety net for the dot entry point.
#
# WHY: once the base no longer tracks `.local/bin/dot` (post-cutover), the
# provider-published command is the only `dot`. If a release install fails
# (no release yet, network outage, rate limit), the door is missing and plain
# `dot update` cannot start (exit 127), so the machine can never heal itself.
# The guard detects exactly that state and retries the provider install
# directly; the next cron cycle then converges normally.
#
# SCOPE: missing or unrunnable door only. A present-but-stale door (hand edit
# colliding with the upstream deletion) keeps its bytes untouched for the
# manual runbook: silently replacing user content would destroy evidence.
# Pre-cutover (HEAD still owns the door) this is a pure no-op.
#
# CONTRACT: best-effort, ALWAYS exits 0. It must never block the update it
# protects, and its no-op path is two file tests (safe every 30 minutes).

set -u

door=${HOME:-}/.local/bin/dot

# Fast path: a runnable door needs nothing.
if [[ -x $door && ! -d $door ]]; then
  exit 0
fi

# Only act in the post-cutover world, evidenced positively: a healthy repo
# whose HEAD no longer owns the door. Every other state (pre-cutover HEAD,
# missing repo, broken git) exits silently; the pre-cutover missing-door
# edge stays on the manual runbook rather than risking a wrong-world repair.
git_dir=${HOME:-}/.dotfiles
if [[ -d $git_dir ]] &&
  git --git-dir="$git_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
  if git --git-dir="$git_dir" cat-file -e 'HEAD:.local/bin/dot' 2>/dev/null; then
    exit 0
  fi
else
  exit 0
fi

if ! command -v shdeps >/dev/null 2>&1; then
  exit 0
fi

state_dir=${XDG_STATE_HOME:-${HOME:-}/.local/state}/dot
mkdir -p "$state_dir" 2>/dev/null || true
rc=0
shdeps update >/dev/null 2>&1 || rc=$?
stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown-time')
printf '%s door-guard: missing provider door, shdeps update rc=%s\n' \
  "$stamp" "$rc" >>"$state_dir/door-guard.log" 2>/dev/null || true
exit 0
