# Profile Selectors

Dotfiles profiles choose which overlay repositories are active. The tracked
profiles are `base`, `editor`, and `dev`; without a matching selector, Dot uses
`base`.

Tracked, non-sensitive selectors may live in this directory. Machine-specific
selectors belong in the ignored directory
`~/.config/dot/profile-selectors.local.d/`. Private inventory may also live in
the repository-only `dot/profile-selectors.d/` directory of the optional
personal overlay.

Each file is data, not shell code:

```text
version=1
user=example-user
host=example-host
profile=editor
```

At least one of `user` or `host` is required, and all supplied fields must
match. User matching is exact and case-sensitive. Host matching uses the short
hostname, lowercases ASCII letters, and ignores one trailing dot. Multiple
matching records may agree; conflicting profile choices fail before Dot
changes the final overlay set. Different users on one host can therefore choose
different profiles.

For example, two local files may select `dev` for one user and `editor` for a
second user on the same host:

```text
# 10-primary-user.conf
version=1
user=example-user
host=example-host
profile=dev
```

```text
# 20-secondary-user.conf
version=1
user=example-user-2
host=example-host
profile=editor
```

Use mode `0700` for the local directory and `0600` for its files. Dot rejects
unsafe ownership, writable permissions, and symlinks there.

Resolution is two-phase. Dot first attempts the optional overlays selected by
`base`, then reads eligible selector records from the root, local directory,
and an available personal overlay. It next resolves the final profile and only
then reads and synchronizes that profile's additional overlay descriptors. If
personal is unavailable, a local or root match still applies; otherwise the
result is `base`.

Before an existing installation can receive these tracked definitions, it must
already be running the compatible standalone Dot profile runtime while its
base checkout is still on the pre-profile revision. Operational readiness
records are private and are not tracked here.

There is intentionally no environment override or profile-management command.
See the sanitized executable examples in standalone Dot's
`examples/profile-dotfiles/` directory.
