# shdeps Config

`dot update` installs and upgrades tools through
[shdeps](https://github.com/cgraf78/shdeps). Dependency declarations live here;
dotfiles-specific install behavior lives in `hooks.d/`.

## Files

- `00-toolchains.conf` declares toolchains and package-manager prerequisites.
- `10-deps.conf` declares normal CLI dependencies.
- `20-local.conf` and similar untracked files may add machine-local deps.
- [`hooks.d/<name>.sh`](hooks.d/README.md) defines post-install and status
  logic for custom or augmented dependencies.
- `hooks.d/owner/repo.sh` handles GitHub dependencies with slash-delimited
  names.

All `.conf` files are loaded in numeric order.

## Declaration Format

```text
# name               method           cmd          aliases                  filter
jq                   pkg
bat                  pkg              apt:batcat
fd                   pkg              apt:fdfind   apt:fd-find,dnf:fd-find
cgraf78/ds           github
neovim/neovim        github           nvim
direnv/direnv        github
nerd-fonts           custom
dust                 pkg              -            -                        os:macos
```

## Methods

- `pkg` installs through the system package manager and batches packages into
  one install command where possible.
- `github` lets shdeps choose the best GitHub-backed install shape for the
  dependency and host: a compatible release asset when one exists, or a repo
  checkout otherwise.
- `github:repo` and `github:release` are still available when a dependency
  needs to force one shape, but dotfiles should prefer the unified `github`
  method unless the distinction is required.
- `cargo`, `go`, and `uv` install through their language ecosystems.
- `custom` is managed entirely by a hook, including platform detection and
  idempotency.

Package aliases map package managers to platform-specific names. Use `NONE` to
skip a package for a specific package manager.

## Filters

The optional filter column supports `os:` and `host:` values. Prefix with `!`
to exclude:

```text
os:linux,os:macos
os:!wsl
host:nas
```

Omit the filter or use `-` for all machines.

## Hooks

Each hook file may define:

- `post()` to run after install or update
- `status()` to report dependency state

Hooks run only for their matching dependency. They are the right place for
cross-platform gaps that package managers do not cover cleanly, such as PHAR,
JAR, RubyGem, release-asset, or `uv` wrappers.

Optional tools that require an already-installed language runtime should skip
themselves when that runtime is absent instead of installing the runtime as a
hidden dependency.

Formatter and linter tools prefer package-manager installs when the package is
available. Custom hooks fill cross-platform gaps with upstream release assets,
PHAR or JAR wrappers, RubyGems, or `uv` as appropriate.

## Existence Checks

`pkg` dependencies check `command -v` first, then fall back to package-manager
queries such as `brew list` or `dpkg -s`. That keeps dependencies without a
binary, such as fonts, from reinstalling every run.
