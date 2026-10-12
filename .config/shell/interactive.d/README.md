# Base Interactive Shell Layer

These fragments load only for interactive Bash and Zsh sessions after the
environment layer. Base owns aliases, terminal navigation, SSH and Dot helpers,
marks, prompts, and completion caching.

Use `_tool_init` for generated initialization and dependency-owned shell APIs.
It caches output below `XDG_CACHE_HOME` and keeps an unavailable optional tool
from preventing a recovery shell. Selected overlays may contribute fragments
before, between, or after the base fragments, choosing prefixes relative to the
base layers they depend on.

The prompt also notifies about long commands. Inside tmux, a command that ran
for `PROMPT_NOTIFY_SECONDS` (default 30; `0` turns it off) rings the terminal
and marks its pane pending through cmdblocks' `term-notify-sound`, the same
`●` an agent waiting for you shows, unless you were looking at that pane when
it finished. Interactive programs (an editor, a pager, an fzf picker, ssh) are
used from the pane you are looking at, so they do not notify. Commands stopped
with Ctrl-C or suspended with Ctrl-Z, and shells outside tmux, never notify.
