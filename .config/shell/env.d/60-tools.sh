# shellcheck shell=bash
# Tool environment bootstraps. Final PATH priority is owned by 90-path.sh.

if [ -d "$HOME/.bun/bin" ]; then
  export BUN_INSTALL="$HOME/.bun"
fi

# Opt into Sley's optional bare-repo fallback for the base dotfiles worktree.
# Sley owns the generic API; this dotfiles layer supplies the local bare repo
# path so plain `sley status` from HOME still behaves like the git launcher.
if [ -z "${SLEY_BARE_REPO_GIT_DIR+x}" ] && [ -d "$HOME/.dotfiles" ]; then
  export SLEY_BARE_REPO_GIT_DIR="$HOME/.dotfiles"
  export SLEY_BARE_REPO_WORK_TREE="$HOME"
fi

# Agentguard owns the generic protected bare-Git guard; dotfiles supplies the
# local bare-repo convention and user-facing remediation text through env.
if [ -z "${AGENTGUARD_PROTECTED_BARE_GIT_DIR+x}" ] && [ -d "$HOME/.dotfiles" ]; then
  export AGENTGUARD_PROTECTED_BARE_GIT_DIR="$HOME/.dotfiles"
  export AGENTGUARD_PROTECTED_BARE_GIT_WORK_TREE="$HOME"
  export AGENTGUARD_PROTECTED_BARE_GIT_ALIASES="DOTFILES"
  export AGENTGUARD_PROTECTED_BARE_GIT_LAUNCHER="$HOME/.local/bin/git"
  export AGENTGUARD_PROTECTED_BARE_GIT_STATUS_MESSAGE="do not run base dotfiles git status with untracked files enabled. Use dot status, or inspect a scoped path with git ls-files --others --exclude-standard -- <path>."
  export AGENTGUARD_PROTECTED_BARE_GIT_LS_FILES_MESSAGE="do not list every untracked file in the base dotfiles repo. Use git ls-files --others --exclude-standard -- <path> for a scoped check."
  export AGENTGUARD_PROTECTED_BARE_GIT_CLEAN_MESSAGE="do not run unscoped git clean in the base dotfiles repo. Inspect a scoped path with git clean --dry-run -- <path>."
fi

# Agentguard edit-churn thresholds. Defaults (warn=5, block=10) are tuned for
# focused coding tasks where many edits to one file usually mean an agent is
# patching in circles. Multi-section review skills (plan-eng-review,
# plan-design-review, etc.) legitimately land 8-12 distinct edits to one
# normative spec doc, so raise the thresholds to leave room for that work
# while still catching genuine churn.
export AGENTGUARD_EDIT_CHURN_WARN="${AGENTGUARD_EDIT_CHURN_WARN:-10}"
export AGENTGUARD_EDIT_CHURN_BLOCK="${AGENTGUARD_EDIT_CHURN_BLOCK:-20}"

# The gstack-register provider installs an OpenCode-native gstack tree. Leaving
# OpenCode's Claude skill compatibility enabled would discover the same gstack
# workflows a second time from ~/.claude/skills, mostly under different names,
# and make model routing ambiguous. This is consumer policy, not registration
# machinery: disable only the Claude skill fallback while keeping CLAUDE.md
# compatibility for projects that have not adopted AGENTS.md.
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS="${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS:-1}"

# shellcheck disable=SC1091  # optional local tool bootstrap script
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"
# shellcheck disable=SC1091  # optional local rust bootstrap script
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
true
