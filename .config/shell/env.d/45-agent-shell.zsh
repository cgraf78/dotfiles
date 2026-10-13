# 45-agent-shell.zsh — parse agent command strings the way agents write them.
# Claude Code runs each Bash-tool command as `zsh -c '<snapshot>; eval ...'`
# with CLAUDECODE=1, and agents write bash-flavored commands. Two zsh defaults
# break them: EQUALS expands a word that starts with `=` to a command path
# (`echo =====` fails with "not found"), and NOMATCH aborts the whole command
# line when a glob matches nothing, even under `2>/dev/null`. Agent hook
# telemetry attributed about a third of agent Bash failures to these two.
#
# Scope is any non-interactive `zsh -c` under CLAUDECODE, chiefly the Bash
# tool (a `zsh -c` that a git alias or helper starts inside an agent session
# matches too): zsh sets ZSH_EXECUTION_STRING before ~/.zshenv runs, and these
# shells reach this file through ~/.zshenv -> env-noninteractive.sh. Human
# shells keep zsh semantics, and zsh script files an agent runs (CLAUDECODE is
# inherited) keep their own globbing contract. An unmatched glob now passes
# through literally, as in bash. Never use NULL_GLOB here: it turns `rm *.tmp`
# with no match into a bare `rm`.
if [[ -n "${CLAUDECODE:-}" && -n "${ZSH_EXECUTION_STRING:-}" && ! -o interactive ]]; then
  unsetopt equals nomatch
fi
