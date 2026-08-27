# Base Interactive Shell Layer

These fragments load only for interactive Bash and Zsh sessions after the
environment layer. Base owns aliases, terminal navigation, SSH and Dot helpers,
marks, prompts, and completion caching.

Use `_tool_init` for generated initialization and dependency-owned shell APIs.
It caches output below `XDG_CACHE_HOME` and keeps an unavailable optional tool
from preventing a recovery shell. Selected overlays contribute their editor or
development integrations as later fragments.
