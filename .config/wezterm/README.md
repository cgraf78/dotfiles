# WezTerm Config

`wezterm.lua` is tracked directly. On WSL, `dot update` copies it to the
Windows home directory so Windows-native WezTerm sees the same config.

## Terminal Bell

Terminal notifications use the standard BEL byte end to end. Local commands,
SSH sessions, and tmux panes therefore use the same transport, and the terminal
client owns sound playback. WezTerm handles its documented `bell` event and
plays a client-local sound with `afplay` on macOS, `paplay` on Linux, or
PowerShell system sounds on Windows. Its native `SystemBeep` renderer is
disabled on those platforms to prevent duplicate playback; that renderer is
silent on Wayland and is retained only as the fallback for unknown platforms.

This is deliberately separate from OSC user variables: remote hosts only emit
BEL and never need access to the workstation audio system.

## Ctrl-Click File Opening

Ctrl-click file opening is split across the tools that each own a piece of
state:

`termnav-module.lua` first uses companion modules copied beside the config for
native Windows startup. On Unix it resolves Termnav through Shdeps' stable
`$SHDEPS_LUA_DIR/shdeps/bootstrap.lua` entrypoint (default
`~/.local/lib/shdeps/shdeps/bootstrap.lua`), leaving install-selection policy
in Shdeps and dependency behavior in Termnav. The loader registers the exact
resolved asset with WezTerm's configuration reload watcher so a Termnav update
cannot leave callbacks using an older in-memory module until the next unrelated
config edit.

1. Termnav classifies the active terminal or attached tmux client. The shell
   aliases choose plain `eza`/`rg` output when native linkification is required,
   or `termnav eza` and semantic `rg` links when a Termnav-capable router is
   present. Local listings keep hostless `file://` OSC-8 targets; SSH sessions
   inside tmux rewrite those targets to `file://host/path`.
2. `rg` uses `--hyperlink-format=file://{host}{path}:{line}:{column}` with the
   dotfiles-owned `ripgrep-link-host` adapter so search results carry absolute
   local or remote targets while Termnav retains an explicit command grammar.
3. tmux advertises `hyperlinks` in `terminal-features` so it re-emits OSC-8
   targets to WezTerm.
4. Termnav's shell and nvim integrations publish pane-local cwd and tmux context
   through its private WezTerm user-var protocol, so fallback regex links and
   key routing resolve against the producing pane.
5. WezTerm routes local `file://`, `nvim-open://`, and `lazygit-edit://` links
   to `~/.local/bin/termnav nvim open` when it owns the mouse event.
6. In tmux/nvim mouse-reporting panes, WezTerm intentionally does not steal
   Ctrl-click. tmux forwards the raw event into nvim so LSP gets the click
   coordinates, and routes terminal-pane hyperlinks through `termnav tmux follow-click`.
7. Remote `file://host/path` links call the same helper with the `link` mode
   and `remote` source label. It skips local Neovim sockets, tries an existing
   SSH ControlMaster connection for hosts listed in
   `TERMNAV_SSH_CONTROL_HOSTS`, and otherwise falls back to sending a remote
   tmux command through an existing host-matched SSH pane.
8. The local `nvim` launcher delegates its conservative pane-reuse decision to
   Termnav and retains only real-editor discovery. `termnav nvim open` then prefers
   Neovim RPC sockets published by Termnav's nvim integration; old tmux
   keystrokes are only used for sessions without the RPC publisher.

Ctrl-click never starts a new SSH authentication flow.

## Overlay Extensions

Environment overlays can add local token policy without shadowing the base
WezTerm or tmux helpers:

- WezTerm loads hyperlink rule modules from `~/.config/wezterm/hyperlink-rules.d/*.lua` after the base fallback rules.
- `termnav tmux follow-click` loads token detectors from `${XDG_CONFIG_HOME:-~/.config}/termnav/tmux-follow/extensions.d/*.sh` before path fallback.

Keep rules that mention private services or workplace-specific URL shapes in an
overlay, not in the base dotfiles repo.

## Tab Bubbling

WezTerm owns `Ctrl-Tab` only when the active pane is not controlled by Neovim
or tmux. A one-window tmux gives Termnav's native one-shot navigation router the
exact triggering client and source scope. The router walks local tmux ancestry
before the SSH relay and finally emits the direct `DOT_SWITCH_TAB` request at
the terminal boundary.
Pane navigation uses the same traversal but stops at the outermost tmux edge;
Termnav does not assume WezTerm panes share tmux's directional semantics.
Ctrl-backslash needs no WezTerm key assignment: WezTerm's normal terminal
encoding sends the C0 file-separator byte (`0x1c`), and each tmux/Neovim layer
either forwards it inward or consumes it as that scope's local previous-pane
operation. Keeping it out of the boundary router avoids inventing a global
history across unrelated nested scopes.

WezTerm also owns `Alt-Shift-[` and `Alt-Shift-]` tab moves only outside
Neovim/tmux panes. In terminal-owned panes the key is forwarded inward as
Meta-left-brace or Meta-right-brace so Neovim BufferLine or tmux windows can
reorder themselves. One-window tmux sessions route outward through
the shared Termnav router; at the terminal boundary it emits the direct
`DOT_MOVE_TAB` user variable. Multi-window application and tmux scopes own
their first/last no-op, preventing movement from leaking to an ancestor. VS
Code still has no command for reordering terminal tabs, so it safely consumes
that terminal-boundary action.

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
`open-uri` handler, tmux's `termnav tmux follow-click` fallback, and the final
`termnav nvim open` helper. Keep common examples in
`~/.local/lib/dotfiles/tests/fixtures/nvim-link-routes.tsv` so tests can prove those
entry points continue to agree without forcing the Lua and shell implementations
through an awkward shared parser.

`termnav nvim open` has two public modes: `cli` for the local `nvim <file>`
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
