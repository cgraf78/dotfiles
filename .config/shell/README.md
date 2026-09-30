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

## Environment Ownership

`env.d/` loads in two modes. Shells that read `~/.bashrc`, `~/.zshrc`, or
`~/.zprofile` are authoritative and re-apply every dotfiles value, because a
new tmux pane inherits the tmux server's possibly stale global environment.
That covers interactive shells, login shells such as `bash -lc` and `zsh -lc`
(common for agent tool shells), and `ssh host cmd` when the account's login
shell is bash, which reads `~/.bashrc` for sshd commands; with zsh as the login
shell, `ssh host cmd` reads only `~/.zshenv` and is fill-only. Other
non-interactive shells (`BASH_ENV` and `~/.zshenv`, through
`env-noninteractive.sh`) are fill-only: a value the caller passed down, even an
empty one, wins, so `EDITOR=vim bash -c ...` and a venv-first `PATH` survive
nested scripts and hooks. Shell-local state such as functions, `shopt`/`setopt`,
and system rc bootstraps loads in every shell regardless of mode.

Export dotfiles-owned values with `_shell_env_set NAME VALUE` from
`shell-loader.sh` instead of `export`. It tracks the names it exported during
the load, so a later fragment can still replace an earlier fragment's value;
every env.d writer of a managed name must therefore use it, because a plain
export from an earlier fragment looks inherited. Keep `${NAME:-default}` for
values that should yield to an existing value in every mode. For custom logic,
`_shell_env_inherited NAME` succeeds only in a fill-only load when the caller
passed NAME down. Overlay fragments must also work on a base checkout without
the helpers:

```sh
command -v _shell_env_set >/dev/null 2>&1 ||
  _shell_env_set() { export "$1=$2"; }
```

`env.d/90-path.sh` applies the same rule to `PATH`: authoritative shells put
managed directories first, while fill-only shells keep the inherited order,
insert missing managed directories just before the first system directory,
append entries fragments added, and never duplicate entries.
