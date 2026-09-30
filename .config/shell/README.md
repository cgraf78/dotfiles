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

`env.d/` loads in two modes. Interactive and login shells are authoritative
and re-apply every dotfiles value, because a new tmux pane inherits the tmux
server's possibly stale global environment. That covers `~/.zshrc`,
`~/.zprofile`, and `~/.bashrc` in an interactive or login bash, including
login shells such as `bash -lc` and `zsh -lc`. Every other shell is fill-only:
a value the caller passed down, even an empty one, wins, so
`EDITOR=vim bash -c ...` and a venv-first `PATH` survive nested scripts and
hooks. That covers `BASH_ENV` and `~/.zshenv` (through
`env-noninteractive.sh`) and the non-interactive, non-login bash that reads
`~/.bashrc` in place of `BASH_ENV` when its stdin is a socket (agent tool
shells) or sshd started it (`ssh host cmd` with bash as the login shell). With
zsh as the login shell, `ssh host cmd` reads only `~/.zshenv`. Shell-local
state such as functions, `shopt`/`setopt`, and system rc bootstraps loads in
every shell regardless of mode.

Because nested shells load `env.d/` too, the loader suspends `set -u` while
it runs and restores the caller's setting afterwards: a `bash -u` or
`bash -euo pipefail` script would otherwise print "unbound variable" from
system rc code a fragment sources. A child that inherits `BASH_ENV` but runs
with a `HOME` lacking dotfiles (test fixtures) skips `env.d/` silently.

Commands that tmux launches itself (`tmux new-window cmd`, `split-window cmd`,
`display-popup cmd`, `run-shell`, hooks) run under a non-interactive shell, so
they keep tmux's global environment as it was when the server started or last
updated it, stale values included. Run such a command through a login or
interactive shell (`zsh -lc cmd`) when it needs fresh dotfiles values, or
refresh tmux with `tmux set-environment -g NAME VALUE`.

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

`~/.local/lib/dotfiles/tests/shell-loader-test` enforces this for base
fragments and fails on a plain `export NAME=value`; overlay suites should check
their own fragments the same way.

`env.d/90-path.sh` applies the same rule to `PATH`: authoritative shells put
managed directories first, while fill-only shells keep the inherited order,
insert missing managed directories just before the first system or host
package directory (`/usr/local`, Homebrew), append entries fragments added,
drop `.` (like the empty entry, which every shell drops), and never duplicate
entries.
