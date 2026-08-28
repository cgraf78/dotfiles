# Profile Selectors

Dotfiles profiles choose which overlay repositories are active. The tracked
profiles are `base`, `editor`, and `dev`. During the initial compatibility
cutover, `00-default.conf` is a tracked root-global selector for `dev`, so a
machine without a more-specific selector retains the full pre-refactor
environment. A later rollout may remove it and use Dot's built-in `base`
fallback after explicit selectors are in place.

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

Only a selector tracked in this root directory may omit both `user` and `host`;
that form supplies a fleet-wide compatibility default. Machine-local and
personal selectors require at least one identity field. All supplied fields
must match. User matching is exact and case-sensitive. Host matching uses the
short hostname, lowercases ASCII letters, and ignores one trailing dot. A
user-only or host-only selector overrides the root-global choice, and a
selector with both fields overrides either broader match. Multiple matches at
the winning specificity may agree; conflicting choices at that same
specificity fail before Dot changes the final overlay set. Different users on
one host can therefore choose different profiles, and a user-wide default can
have per-host exceptions.

For example, `root` may default to `editor` everywhere:

```text
version=1
user=root
profile=editor
```

while a more-specific record chooses `dev` on one host:

```text
version=1
user=root
host=example-host
profile=dev
```

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
configured `default_profile` applies, or `base` when that key is omitted.

Changing the winning selector, removing the root-global selector, or changing
`default_profile` takes effect on the next successful `dot update`. Newly
selected overlays are activated. Exact managed links from deselected overlays
are removed and lower-layer files are restored, while cached repositories,
native packages, and unmanaged files are preserved.

The compatibility selector and pre-sync hook are intentionally readable by an
old installation without requiring the old client to understand profiles. The
same `dot update -f` invocation can update and re-exec Dot, then converge the
selected overlays. Operational readiness records are private and are not
tracked here.

There is intentionally no environment override or profile-management command.
See the sanitized executable examples in standalone Dot's
`examples/profile-dotfiles/` directory.
