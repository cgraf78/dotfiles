# iTerm2 merge hook

During `dot update` on macOS, this hook publishes the managed **Dotfiles**
Dynamic Profile and explicitly selects it through `Default Bookmark Guid`.
It preserves the old Windows (Dotfiles) profile's GUID and output filename so
saved references continue to work while the profile is renamed in place.
Other profiles and unrelated application preferences remain unchanged.

`~/.config/terminal/settings.json` is shared with WezTerm and Terminal. It owns
the font, palette, dimensions, spacing, cursor, scrollback, terminal type, and
portable key sequences. WezTerm is the reference behavior. The native profile
fragment here contains only iTerm2-specific policy and shortcuts. Native Cmd
shortcuts are retained; app-owned Ctrl+F/G/W reach the terminal application.
The modified-key sequences replace older conflicting mappings.

Sources:

- `profiles.d/*.json`: ordered Dynamic Profile inputs; numeric prefixes are
  stripped from destination filenames. Custom profiles are validated and
  copied unchanged. `Dotfiles Appearance: true` applies the shared settings;
  `Dotfiles Default: true` selects that profile as default. Metadata is removed
  from the published JSON. The last default-marked source wins; duplicate
  GUIDs or multiple defaults within one source are errors. In a keyboard
  action, `Dotfiles Profile: true` fills its Text with that profile's GUID.
- `defaults.d/*.tsv`: ordered global preference rows, formatted as
  `domain<TAB>key<TAB>type<TAB>value`. Supported types are `bool`, `int`,
  `string`, and `plist`. Independent preference writes still run when profile
  publication fails, but the managed default selector is not changed.

The hook creates DynamicProfiles before first launch. It renders and validates
hidden staging files, then atomically publishes them so iTerm2's watcher sees
complete JSON. Matching files are not rewritten. Default selection happens
only after successful publication and is read back for verification.

A running iTerm2 reloads dynamic profile data. Relaunch when convenient if it
retains a previous default selection; existing sessions are never closed.
The managed profile is regenerated on the next update, so make durable changes
in the source or use a separate unmanaged profile.

Implementation: `~/.local/lib/dotfiles/merge-hooks.d/iterm2.sh`.

See the [iTerm2 Dynamic Profiles reference](https://iterm2.com/documentation-dynamic-profiles.html) for native profile attributes and reload behavior.
