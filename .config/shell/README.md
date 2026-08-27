# Base Shell Configuration

The top-level shell files are thin loaders. Ordered fragments under `env.d/`
and `interactive.d/` contain the always-active shell policy, while selected
overlays add later fragments for editor or development behavior.

Base owns PATH construction, platform detection, aliases, prompt setup,
terminal navigation, SSH helpers, Dot helpers, marks, and cached loading of
base dependency APIs. Editor and development fragments use the `80-` range or
later unless they intentionally need an earlier documented ordering point.

Files ending in `.sh` are shell-neutral, `.bash` files load only in Bash, and
`.zsh` files load only in Zsh. Keep startup work cheap and use the shared
tool-initialization cache for generated shell code.
