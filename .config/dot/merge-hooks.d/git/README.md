# Git

The Git merge hook keeps `~/.config/git/config` in Git's effective global
configuration stack. Git normally discovers the XDG config directly, but some
hosts with an existing `~/.gitconfig` omit it. On those hosts, the hook adds one
portable include while preserving every host-specific setting already present.
