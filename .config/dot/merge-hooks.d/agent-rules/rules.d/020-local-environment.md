# Local Environment

<!-- agent-rule-id: global-local-environment -->

- `~/git` is the default location for locally cloned git repos.
- gstack's checkout lives in `~/.local/share/garrytan/gstack`; dotfiles register
  its skills for installed agents without running gstack's heavier setup/build
  path. `~/.gstack` is gstack's state directory, not a checkout alias.
