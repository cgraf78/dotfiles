# Base Shell Configuration

The top-level shell files are thin loaders. Ordered fragments under `env.d/`
and `interactive.d/` contain the always-active shell policy, while selected
overlays add editor, development, or private fragments at their own ordering
points.

Base owns PATH construction, platform detection, aliases, prompt setup,
terminal navigation, SSH helpers, Dot helpers, marks, and cached loading of
base dependency APIs. Overlay fragments choose a prefix relative to the base
fragments they must follow or precede: private overlays usually use `80-` or
later, editor and development overlays interleave with base at deliberate
points (for example `57-`, `60-`, and `70-`), and early bootstrap fragments
may use a low prefix such as `05-` or `10-`.

Files ending in `.sh` are shell-neutral, `.bash` files load only in Bash, and
`.zsh` files load only in Zsh. Keep startup work cheap and use the shared
tool-initialization cache for generated shell code.
