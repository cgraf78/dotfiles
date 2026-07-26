# ds Config

This directory contains local configuration for `ds` tmux development sessions.
The `ds` tool itself is installed through shdeps; these files are dotfiles-owned
inputs that shape how sessions connect, share terminals, and select profiles.

## Files

- `connect*.conf` files define connection behavior for remote sessions.
- `share-upterm.conf` defines defaults for shared upterm sessions when an
  overlay or local machine config provides it.
- `profile-*.sh` files are shell snippets for named session profiles.
- `profile*.conf` files define single-command profiles as data.
- `upterm_authorized_keys` and `upterm_known_hosts` hold upterm SSH trust data
  when an overlay or local machine config provides them.

Keep profile snippets small and profile-specific. Shared shell behavior belongs
under `~/.config/shell`; reusable command behavior belongs in its owning
dependency repo, with dotfiles-specific glue kept thin.
