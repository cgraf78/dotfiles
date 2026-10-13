# 45-agent-shell.zsh — parse `=word` in agent command strings as bash does.
# Claude Code runs each Bash-tool command as `zsh -c '<snapshot>; eval ...'`
# with CLAUDECODE=1, and agents write bash-flavored commands. zsh's EQUALS
# option expands a word that starts with `=` to a command path, so
# `echo =====` fails with "not found"; agent hook telemetry attributed about
# a fifth of agent Bash failures to it. EQUALS has no safety value here.
#
# NOMATCH stays on deliberately. Its unmatched-glob errors are loud and cheap
# to fix, while passing the literal pattern through (bash behavior) lets a git
# pathspec match recursively: with no top-level `*.c`, `git checkout -- *.c`
# would silently discard changes to `sub/x.c`.
#
# Scope is any non-interactive `zsh -c` under CLAUDECODE, chiefly the Bash
# tool (a `zsh -c` that a git alias or helper starts inside an agent session
# matches too): zsh sets ZSH_EXECUTION_STRING before ~/.zshenv runs, and these
# shells reach this file through ~/.zshenv -> env-noninteractive.sh. Human
# shells keep zsh semantics, and zsh script files an agent runs (CLAUDECODE is
# inherited) keep their own contract.
if [[ -n "${CLAUDECODE:-}" && -n "${ZSH_EXECUTION_STRING:-}" && ! -o interactive ]]; then
  unsetopt equals
fi
