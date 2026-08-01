# tmux Config

`tmux.conf` owns terminal multiplexing policy and the tmux side of the
terminal navigation stack.

## Integration Points

- Neovim pane navigation uses `vim-tmux-navigator`-style Ctrl-h/j/k/l bindings.
- Ctrl-click routing delegates to `tmux-follow-click` from the `termnav`
  dependency when the foreground pane is not already handling mouse events.
- File opens route through `nvim-tmux-open`, also owned by `termnav`.
- Manual session export/restore and clipboard-history paste use `tmux-tools`.
- Automatic session persistence uses TPM, `tmux-resurrect`, and
  `tmux-continuum`, installed as shdeps-managed repository checkouts.
- Ctrl-Tab window switching forwards into Neovim/fzf and nested terminal apps,
  switches tmux windows when the current tmux layer owns the chord, and bubbles
  one-window sessions upward through `termnav-switch-tab`. The helper
  walks locally nested tmux parents, then targets the originating VS Code or
  WezTerm client rather than relying on session-global host state.
- Alt-Shift-[ and Alt-Shift-] mirror WezTerm tab reordering for tmux windows:
  the bindings forward into Neovim/fzf and nested terminal apps, swap tmux
  windows only when the current window is not already at the edge, and bubble
  one-window sessions upward through `wezterm-move-tab` from `termnav`.
- Copy-mode clipboard piping prefers the dotfiles `clip` command and falls
  back to platform clipboard tools.

Keep generic tmux helper commands in their owning dependency repos. This
directory should wire those commands into the user's tmux experience, not own
their implementation.

## Key Handling

The config intentionally enables extended keys, true color, focus events, OSC
passthrough, and hyperlink support. Those settings are part of the contract
between WezTerm, tmux, Neovim, and remote shells. Be careful changing them:
some require a fresh tmux server, not just `tmux source-file`.

Mouse bindings should preserve nested behavior. When `#{mouse_any_flag}` is
set, tmux forwards the event inward with `send-keys -M`; only bare terminal
panes should be handled by the outer tmux layer.

Ctrl-Tab bindings should preserve nested tab ownership. Forward the key into
Neovim/fzf when those programs own the pane, and through interactive remote
transports such as `ssh` and `mosh` so a tmux or Neovim session on the remote
host gets the first chance to handle it. The transport detector only trusts the
pane's foreground process group; stale SSH helper processes can remain attached
to a tty after the shell is foreground again and must not steal the chord. Also
forward when the foreground process is itself a bare nested tmux/screen client
with `#{mouse_any_flag}` set — that combination means some inner layer we can't
inspect via `ps` wants raw input. `#{mouse_any_flag}` alone is not enough:
plain TUIs (Claude Code, codex, `htop -m`, ...) can enable mouse reporting for
their own scrolling/clicking without wanting to own Ctrl-Tab, so the flag is
only trusted when paired with the nested-wrapper check. Switch tmux windows
when the current tmux layer owns the chord. A one-window session passes its
triggering client's PID, TTY, and shell-quoted terminal type to
`termnav-switch-tab`. That helper switches the first reachable parent tmux
with multiple windows, or uses the outer client's per-window VS Code socket or
WezTerm TTY. Only clients actively showing the parent pane are eligible; a
unique focused client breaks an activity tie, and unresolved ties fail closed.
The private `User0`/`User1` loopback remains for remote nested tmux chains
whose parent server is not locally reachable.

Alt-Shift-bracket tab-move bindings follow the same ownership rule, except edge
handling stops at the tmux layer when a multi-window tmux session is already at
the first or last window. A one-window nested tmux bubbles the move to the
parent tmux layer through private `User2`/`User3` keys; a one-window top-level
tmux bubbles the move to WezTerm.

## Session Persistence

The default tmux server runs continuum's native save script every 15 minutes,
and its default-server helper asks resurrect to restore the latest snapshot at
startup. On remote hosts, the normal SSH `ds` auto-attach starts that server;
elsewhere, the first `ds` or tmux command does. This restores each machine's
local sessions across tmux server restarts and machine reboots without making
tmux start a terminal at login.

Tmux uses zsh as its explicit default shell when zsh is installed, falling
back to the account shell otherwise. Resurrect creates restored panes from
that tmux default, while the ds metadata hook restores each session's selected
shell for future windows.

Resurrect restores session names, windows, panes, layouts, working directories,
and its conservative default process list. The config deliberately does not
restart every foreground command or persist pane scrollback: agent processes
can carry stale work, and scrollback snapshots can contain sensitive output.
Resurrect still records each pane's working directory and full foreground
command line, including arguments, so snapshots can contain sensitive paths or
command arguments even with scrollback capture disabled. Its rolling history
keeps at least five snapshots and otherwise removes files older than 30 days.
Snapshots use a private host-specific directory so machines sharing a home
directory do not overwrite one another's state.

The existing prefix+S and prefix+R bindings remain available for explicit
`tmux-tools` exports and restores. Keep the TPM block at the end of `tmux.conf`
and keep continuum last in the plugin list. Continuum injects autosave through
`status-right`, so a later plugin or status assignment would silently disable
periodic saves.

Upstream continuum normally gives persistence ownership to the first tmux
server for the user. This config loads continuum with saving and restoring
disabled, then synchronously enables the native save script and resurrect
restore only for the normal default `ds` server. That keeps ownership stable
even when an isolated socket was already running. Additional servers started
with `tmux -L` or `tmux -S` do not auto-save or auto-restore, and this
host-specific snapshot directory is not socket-scoped. Use additional servers
only for isolated temporary work.
