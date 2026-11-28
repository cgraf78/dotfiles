# GitHub Transport Merge Hook

This directory declares the `github-transport` merge-hook instance. It decides,
per account, whether Git reaches `github.com` over SSH or over HTTPS. Its
declarative source family is `policy.d/` in this directory; the executable
hook lives at `~/.local/lib/dotfiles/merge-hooks.d/github-transport.sh`.

## Transports

- `ssh` leaves Git untouched: remotes such as `git@github.com:owner/repo.git`
  use the account's SSH key. This is the base default.
- `https` adds a managed block to `~/.gitconfig` that rewrites
  `git@github.com:` and `ssh://` remotes for `github.com` to
  `https://github.com/`, and answers GitHub credential requests with the first
  line of `~/.config/gh/github-pat` through
  `~/.local/lib/dotfiles/git-credential-github-pat`. The account then needs no
  SSH key registered with GitHub. Give it a fine-grained token with only the
  access it needs, typically `Contents: read` on the private repositories it
  clones; public repositories are always readable.

Switching an account back to `ssh` removes the block, and removes
`~/.gitconfig` only when the block was its sole content. Writing the block sets
`~/.gitconfig` to mode 600.

The hook leaves Git unchanged, and fails so `dot update` reports it, when:

- the policy selects `https` but `~/.config/gh/github-pat` is missing or
  empty: without a token every private fetch would fail, so the account keeps
  SSH until the token exists;
- `~/.gitconfig` is a symlink: set the transport in its target by hand.

Not covered: SSH host aliases from `~/.ssh/config` (such as `github-work:`),
and tools that ignore the global config (`GIT_CONFIG_GLOBAL=/dev/null`, or a
forced `GIT_SSH_COMMAND`). Check for those before removing a host's key from
GitHub.

## Fresh hosts

Policy records usually live in a private overlay, which a host without GitHub
credentials cannot clone, so a fresh host starts on the base `ssh` default and
gets only public repositories. To start a host directly on HTTPS, write its
token to `~/.config/gh/github-pat`, add a local record such as
`policy.d/host-<name>.conf` here, and run `dot update` twice: the first run
installs the block, the second fetches private overlays through it. Delete the
local record once an overlay carries one.

## Policy records

Each `*.conf` file in `policy.d/` is one record in the profile-selector
grammar (see `~/.config/dot/profile-selectors.d/README.md`), with `transport`
in place of `profile`:

```text
version=1
user=root
transport=https
```

- `user` matches `id -un` exactly; `host` matches Dot's short, lowercased
  host name, the same identity profile selectors use, so write `myhost`, not
  `myhost.lan`.
- A record with both `user` and `host` beats a record with one of them, which
  beats the default. Disagreeing records at the winning level fail the hook
  and leave Git unchanged.
- The default is the only record without `user` or `host`, and it must live in
  `policy.d/default.replace/`. Base ships `00-base.conf` (`transport=ssh`); an
  overlay that adds a later file there replaces it rather than conflicting.
- Unknown keys, a missing `version=1`, or a `transport` other than `ssh` or
  `https` fail the hook without changing Git.

Overlays add their records to this same directory. Keep host inventories in
the overlay that owns them; this public tree holds only the base default.

## Flipping the default

To make HTTPS the default and keep SSH for a few accounts, an overlay adds
`policy.d/default.replace/50-<overlay>.conf` with `transport=https` and one
`transport=ssh` record per account that should keep SSH, and drops records that
only restated HTTPS. No hook change is needed.

To retire the hook, remove the overlay records first and let one `dot update`
strip the block everywhere; removing the hook first would leave blocks that
name a helper that no longer exists.
