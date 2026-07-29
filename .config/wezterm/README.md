# WezTerm Config

`wezterm.lua` is tracked directly. On WSL, `dot update` copies it to the
Windows home directory so Windows-native WezTerm sees the same config.

## Ctrl-Click File Opening

Ctrl-click file opening is split across the tools that each own a piece of
state:

1. `eza-nvim-links` runs `eza --hyperlink`, preserving real paths for commands
   such as `ll some/dir`. Local listings keep hostless `file://` OSC-8 targets.
   SSH sessions inside tmux rewrite those targets to `file://host/path`.
2. `rg` uses `--hyperlink-format=file://{host}{path}:{line}:{column}` with
   `nvim-link-host` so search results carry absolute local or remote targets.
3. tmux advertises `hyperlinks` in `terminal-features` so it re-emits OSC-8
   targets to WezTerm.
4. Shell and nvim sessions publish pane-local cwd context with WezTerm user
   vars so fallback regex links resolve relative paths from the clicked pane.
5. WezTerm routes local `file://`, `nvim-open://`, and `lazygit-edit://` links
   to `~/.local/bin/nvim-tmux-open` when it owns the mouse event.
6. In tmux/nvim mouse-reporting panes, WezTerm intentionally does not steal
   Ctrl-click. tmux forwards the raw event into nvim so LSP gets the click
   coordinates, and routes terminal-pane hyperlinks through `tmux-follow-click`.
7. Remote `file://host/path` links call the same helper with the `link` mode
   and `remote` source label. It skips local Neovim sockets, tries an existing
   SSH ControlMaster connection for hosts listed in
   `TERMNAV_SSH_CONTROL_HOSTS`, and otherwise falls back to sending a remote
   tmux command through an existing host-matched SSH pane.
8. `nvim-tmux-open` prefers Neovim RPC sockets published by
   `~/.config/nvim/lua/config/nvim-tmux-open.lua`; old tmux keystrokes are only
   used for sessions without the RPC publisher.

Ctrl-click never starts a new SSH authentication flow.

## Overlay Extensions

Environment overlays can add local token policy without shadowing the base
WezTerm or tmux helpers:

- WezTerm loads hyperlink rule modules from `~/.config/wezterm/hyperlink-rules.d/*.lua` after the base fallback rules.
- `tmux-follow-click` loads token detectors from `${XDG_CONFIG_HOME:-~/.config}/termnav/tmux-follow/extensions.d/*.sh` before path fallback.

Keep rules that mention private services or workplace-specific URL shapes in an
overlay, not in the base dotfiles repo.

## Tab Bubbling

WezTerm owns `Ctrl-Tab` only when the active pane is not controlled by Neovim or
tmux. When a top-level tmux session has only one window left to switch to,
`wezterm-switch-tab` from `termnav` emits the `DOT_SWITCH_TAB` user-var escape,
and WezTerm handles that as a parent tab switch. When a tmux session attached
inside another tmux has only one window, it emits `DOT_PARENT_SWITCH_TAB`;
WezTerm translates that into a private tmux `User0`/`User1` key so the parent
tmux layer can switch its own windows.

WezTerm also owns `Alt-Shift-[` and `Alt-Shift-]` tab moves only outside
Neovim/tmux panes. In terminal-owned panes the key is forwarded inward as
Meta-left-brace or Meta-right-brace so Neovim BufferLine or tmux windows can
reorder themselves. A top-level tmux session with one window can bubble the
move directly to WezTerm through `wezterm-move-tab`, which emits the
`DOT_MOVE_TAB` user-var escape. A one-window tmux attached inside another tmux
emits `DOT_PARENT_MOVE_TAB`; WezTerm translates that into a private tmux
`User2`/`User3` key so the parent tmux layer can move its own windows.
Multi-window tmux sessions stop at their own first and last windows to match
WezTerm's edge behavior.

This parent fallback is WezTerm-specific. VS Code terminal keybindings can
forward `Ctrl-Tab` and `Alt-Shift-[`/`Alt-Shift-]` into tmux and Neovim, but
this dotfiles setup does not currently provide a terminal-output bridge that
asks VS Code to switch or move editor tabs when a nested tmux session bubbles
past its own tab/window layer. The `DOT_PARENT_*` bridge also depends on
WezTerm receiving OSC 1337 user-var escapes from the nested session.

## Clipboard Ownership

The terminal frontend owns paste because only it can read the workstation
clipboard reliably across SSH, WSL, and VS Code Remote boundaries. WezTerm
handles `Ctrl-V` directly; VS Code installs the equivalent terminal-focused
binding from the shared keybinding layer. Both frontends copy their own text
selection, while an unselected `Ctrl-C` continues into the pty as interrupt.

Selections made inside tmux copy mode take the other path: tmux stores them in
its buffer and publishes them to a capable outer terminal with OSC 52. The
`clip capture` pipe also keeps clipboard history and mirrors to a native
`pbcopy`, `wl-copy`, or `xclip` backend when tmux is local. Plain `Ctrl-V` in a
non-WezTerm/non-VS Code local terminal remains supported through `clip paste`.

## Routing Contracts

The same link shapes are recognized in three places: WezTerm's Lua
`open-uri` handler, tmux's `tmux-follow-click` fallback, and the final
`nvim-tmux-open` helper. Keep common examples in
`~/.local/lib/dot/tests/fixtures/nvim-link-routes.tsv` so tests can prove those
entry points continue to agree without forcing the Lua and shell implementations
through an awkward shared parser.

`nvim-tmux-open` has two public modes: `cli` for the local `nvim <file>`
launcher path, and `link` for hyperlinks, tmux clicks, and WezTerm routes.
The important `link` source labels are:

- `terminal`: output came from a local pane; relative paths use the clicked
  pane cwd.
- `nvim`: output came from a known nvim pane; WezTerm passes that pane's exact
  RPC socket first so another recently active nvim instance does not steal the
  open.
- `remote`: output refers to another host; local nvim sockets are skipped and
  the helper tries ControlMaster before tmux pane fallback.

Check whether a configured host has a reusable master:

```bash
ssh -O check example-host
```

If this fails, Ctrl-click falls back to the tmux transport. `ControlPersist`
keeps an authenticated SSH master available after an interactive session exits,
which improves ergonomics but extends the window in which local processes can
reuse that SSH connection.

`wezterm.lua` exports `TERMNAV_SSH_CONTROL_HOSTS` for the GUI route helper and
shells spawned by WezTerm. Set the environment variable before starting
WezTerm, or add a local/overlay-managed
`~/.config/wezterm/termnav-ssh-control-hosts` file containing a comma-separated
host list. If neither exists, no remote host is allowlisted for ControlMaster
reuse.
