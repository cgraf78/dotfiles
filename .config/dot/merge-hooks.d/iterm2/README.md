# iTerm2 Merge Hook

This directory declares the `iterm2` merge-hook instance. Its declarative
sources are:

- `profiles.d/*.json`: ordered DynamicProfiles source files; numeric filename
  prefixes are stripped from destination filenames
- `defaults.d/*.tsv`: ordered global `defaults write` rows

Each defaults row is tab-separated:

```text
domain<TAB>key<TAB>type<TAB>value
```

Supported types are `bool`, `int`, `string`, and `plist`.

The executable hook implementation lives at
`~/.local/lib/dotfiles/merge-hooks.d/iterm2.sh`.
