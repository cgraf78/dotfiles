# Hive Memory Merge Hook

This directory declares the `hive-memory` merge-hook instance. It has no
declarative source fragments: the hook initializes and checks the configured
Hive Memory store when `hm` and its resolved config are present. Config
resolution follows Hive itself: `HIVE_MEMORY_CONFIG`, then an absolute
`XDG_CONFIG_HOME`, then `~/.config/hive-memory/config.toml`.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/hive-memory.sh`.
