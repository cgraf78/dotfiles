# GStack Merge Hook

This directory declares dotfiles' `gstack` activation policy. It has no
declarative source fragments: every `dot update` asks the shdeps-installed
[`gstack-register`](https://github.com/cgraf78/gstack-register) provider to
reconcile the current checkout with installed agents.

The ownership boundary is intentionally narrow:

- `gstack-register` owns discovery, generated skill transforms, Claude,
  Codex, Gemini, and OpenCode target shapes, caching, migration, and cleanup;
- dotfiles owns the `cgraf78/gstack-register` and `garrytan/gstack` dependency
  declarations, the actual exclusion choices in
  `~/.config/gstack-register/skills-exclude`, and activation timing; and
- the upstream gstack shdeps hook runs the same provider after checkout
  changes, while this merge hook also catches policy edits and agents installed
  since the last upstream update.

The executable merge adapter lives at
`~/.local/lib/dotfiles/merge-hooks.d/gstack.sh`. It deliberately contains no
registration fallback: if a partial install or isolated merge-hook run lacks
the provider, it is a no-op. The upstream post-install hook performs the first
reconciliation once shdeps installs both dependencies.
