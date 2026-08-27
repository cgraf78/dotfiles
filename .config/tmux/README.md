# tmux Config

`tmux.conf` owns terminal multiplexing policy and the tmux side of the
terminal navigation stack.

## Integration Points

- Neovim pane and tab navigation use Termnav's Lua adapter. Local Neovim
  splits remain process-free, adjacent tmux panes use one guarded tmux command,
  and session-relative or outer routing stays in the shared router.
- Ctrl-click routing delegates to `tmux-follow-click` from the `termnav`
  dependency when the foreground pane is not already handling mouse events.
- File opens route through `nvim-tmux-open`, also owned by `termnav`.
- The default-server Continuum coordinator, its cheap save gate, and
  clipboard-history paste use `tmux-tools`.
- Automatic session persistence uses TPM, `tmux-resurrect`, and
  `tmux-continuum`, installed as shdeps-managed repository checkouts.
- Ctrl-Tab window switching forwards into Neovim/fzf and nested terminal apps,
  switches tmux windows when the current tmux layer owns the chord, and sends
  one-window boundaries through Termnav's warmed relay dispatcher with exact
  client identity.
- Alt-Shift-[ and Alt-Shift-] mirror WezTerm tab reordering for tmux windows:
  the bindings forward into Neovim/fzf and nested terminal apps, swap tmux
  windows only when the current window is not already at the edge, and route
  one-window boundaries through the same Termnav entry point.
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

Ctrl-h/j/k/l bindings should follow focused pane ownership across nested tmux
layers. Editors and fzf receive the chord directly. Interactive transports and
nested multiplexers receive it only while their inner content has enabled
mouse reporting; that signal distinguishes a focused remote tmux, screen, or
terminal application from a plain remote shell. A plain SSH/mosh/ET shell keeps
pane navigation at the outer tmux layer, where forwarding Ctrl-h would instead
produce backspace. Foreground-process-group checks prevent stale background
transports or nested clients from stealing the chord. When a remote nested
tmux owns the chord but has no pane in that direction, `termnav-relay` sends
the semantic request to the nearest parent tmux scope. The outer terminal
supplies an ordered, read-only DECRQM response as the commit barrier;
`User9`-`User13` cover every legal response state in WezTerm, xterm.js, and
other conforming terminals without a custom extension. Intermediate tmux
layers forward the private `User8` commit key. There is no terminal-specific
parent fallback: unresolved ancestry is consumed instead of guessed.

Ctrl-backslash is the local previous-pane companion to directional navigation.
It follows the same inward ownership test, so Neovim can choose its previous
split and a focused nested tmux can choose its own previous pane. A bare pane is
handled by the nearest tmux with `select-pane -l`. It deliberately does not use
the boundary router: “previous” is history belonging to one tmux or editor
scope, and choosing an ancestor's history would be ambiguous in nested or
shared-client topologies. Neovim terminal mode keeps Ctrl-backslash available
as the first half of its native Ctrl-backslash, Ctrl-N escape sequence.

Ctrl-Tab bindings share pane-navigation's focus ownership. Forward the key into
Neovim/fzf when those programs own the pane, and through interactive remote
transports such as `ssh`, `mosh`, and ET only when propagated mouse reporting
proves that a tmux, screen, Neovim, or other mouse-aware application is active
on the remote host. A plain remote shell remains at the current tmux layer, so the
chord switches its windows instead of reaching the shell as an unusable escape
sequence. The transport detector only trusts the pane's foreground process
group; stale SSH helper processes can remain attached to a tty after the shell
is foreground again and must not steal the chord. Also forward when the
foreground process is itself a bare nested tmux/screen client with
`#{mouse_any_flag}` set — that combination means some inner layer we can't
inspect via `ps` wants raw input. `#{mouse_any_flag}` alone is not enough:
plain TUIs (Claude Code, codex, `htop -m`, ...) can enable mouse reporting for
their own scrolling/clicking without wanting to own Ctrl-Tab, so the flag is
only trusted when paired with the nested-wrapper check. Switch tmux windows
when the current tmux layer owns the chord. A one-window session passes its
triggering client's PID, TTY, terminal type, and source scope to
the warmed `termnav-relay navigate` router. It switches the first reachable
parent tmux with multiple windows, or uses the outer client's per-window VS
Code socket or WezTerm TTY. Every selected client is revalidated before
dispatch; unresolved ties and stale identities fail closed.

Alt-Shift-bracket tab-move bindings follow the same ownership rule, except edge
handling stops at the tmux layer when a multi-window tmux session is already at
the first or last window. A one-window tmux routes outward through the same
arbitrary-depth Termnav traversal used by pane and tab selection.

Boundary router commands run in tmux's foreground through Termnav's warmed
dispatcher, and the Neovim adapter keeps its ordered worker alive. This
preserves rapid key order without adding subprocesses to the native
adjacent-pane or multi-window fast paths.

## Session Persistence

The default tmux server runs continuum's native save script every 5 minutes,
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

Keep the TPM block at the end of `tmux.conf` and keep continuum last in the
plugin list. Continuum injects autosave through `status-right`, so a later
plugin or status assignment would silently disable periodic saves. The older
manual save/restore commands and their prefix+S/prefix+R bindings were retired:
this configuration uses tmux-resurrect as the single persistence mechanism.

Upstream continuum normally gives persistence ownership to the first tmux
server for the user. This config loads continuum with saving and restoring
disabled, then invokes the generic `tmux-continuum-default-server` provider
from `tmux-tools`. Dotfiles supplies only the policy options: the provider
enables the native save script and resurrect restore for the normal default
server, and publishes a generic restore signal that DS can consume without the
provider depending on DS. That keeps ownership stable even when an isolated
socket was already running. Additional servers started with `tmux -L` or
`tmux -S` do not auto-save or auto-restore, and this host-specific snapshot
directory is not socket-scoped. Use additional servers only for isolated
temporary work.
