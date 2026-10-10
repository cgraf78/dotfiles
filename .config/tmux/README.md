# tmux Config

`tmux.conf` is a thin loader that sources `conf.d/*.conf` in lexical order.
The base `conf.d/10-base.conf` owns terminal multiplexing policy: sessions,
status, clipboard, persistence, and the transport-aware tmux side of the
terminal navigation stack. The `dotfiles-nvim` overlay adds
`conf.d/20-editor.conf`, which owns editor-aware pane, tab, and link routing.

## Integration Points

- The default-server Continuum coordinator, its cheap save gate, and
  clipboard-history paste use `tmux-tools`.
- `prefix o` and `prefix O` copy the last one or N command output blocks
  through `cmdblocks`' `tmux-copy-last-output`.
- Automatic session persistence uses TPM, `tmux-resurrect`, and
  `tmux-continuum`, installed as shdeps-managed repository checkouts.
- Alt-Shift-[ and Alt-Shift-] mirror WezTerm tab reordering for tmux windows:
  the bindings forward into nested terminal apps, swap tmux windows only when
  the current window is not already at the edge, and route one-window
  boundaries through Termnav's native one-shot router. The editor overlay
  rebinds them so Neovim/fzf panes also receive the chord.
- Copy-mode clipboard piping uses the dotfiles `clip` command, which falls
  back to platform clipboard tools. `copy-command` is `clip capture`, so
  double-click word selection and triple-click line selection join Enter,
  Ctrl-c, and vi-style `v`/`y`.
- `prefix Tab` opens extrakto, a shdeps-managed checkout sourced directly
  rather than through TPM, to fuzzy-pick a path, URL, hash, or word from the
  pane. Its copies also go through `clip capture` and then OSC 52.

The editor overlay's `20-editor.conf` adds:

- `set -g mouse on`. Base alone leaves tmux mouse mode off, so its copy-mode
  mouse bindings only take effect when the editor overlay is active.
- Neovim pane and tab navigation through Termnav's Lua adapter. Local Neovim
  splits remain process-free, adjacent tmux panes use one guarded tmux command,
  and session-relative or outer routing stays in the shared router.
- Ctrl-click routing, which delegates to `termnav tmux follow-click` from the
  `termnav` dependency when the foreground pane is not already handling mouse
  events.
- File opens through `termnav nvim open` (`prefix e`), also owned by
  `termnav`.
- Ctrl-Tab window switching, which forwards into Neovim/fzf and nested
  terminal apps, switches tmux windows when the current tmux layer owns the
  chord, and sends one-window boundaries through Termnav's native one-shot
  router with exact client identity.
- Ctrl-Shift-V forwarding as a private escape sequence for Neovim's yank
  history.

Keep generic tmux helper commands in their owning dependency repos. This
directory should wire those commands into the user's tmux experience, not own
their implementation.

## Labels and Status

Windows name themselves from what they host, not from the focused pane. Every
pane whose foreground app enables mouse reporting (agents, editors, a nested
tmux over SSH) contributes its name, in pane order; shells and short-lived
commands such as `git`, `make`, or `less` never do, so tabs do not flicker
while a side shell works. A window of plain shells falls back to the active
pane's directory. Sandboxes, SSH transports, and interpreters (`bwrap`,
`termnav`, `ssh`, `node`, `python`) report a wrapper process name, so those
panes use the title the app set itself. tmux's hostname default, or a title
that only repeats the command or directory, does not count as a title.
Titles are untrusted text, so labels escape them and an embedded `#[...]`
style directive renders literally. Shells and pickers (`zsh`, `fzf`, `less`)
never name a window even while a widget such as fzf history search turns
mouse reporting on. A manual rename (`prefix ,`) turns automatic naming off
for that window.

`set-titles` publishes `host:session` as the terminal title. A nested tmux
reached over SSH therefore titles its parent pane, which is how the outer
layer labels that pane and window with the remote host.

A pane title belongs to whichever program last set it, so the shell prompt
(`.config/shell/interactive.d/60-prompt.*`) keeps titles current under tmux or
screen: each command line becomes the title as it starts (`ssh metro`), and
every prompt resets it. A title left by an exited program, such as a previous
SSH session's remote tmux, therefore never mislabels the next one. A plain
SSH shell on a host with these dotfiles titles itself `user@host: dir`.

Pane borders use the same rules: interactive panes show the app and its own
title (an agent's task, Neovim's file), and shells show a home-relative
directory. `ds` strips host literals such as `#{host}` from
`pane-border-format`, so host comparisons live in the `@pane_*` user options
rather than in that option itself.

The status bar has its own background so the window list reads as a tab
strip. The current tab is highlighted, a background window that rang the
bell turns orange until selected, and tabs show `[Z]` for a zoomed pane and
`[COPY]` while the active pane is in copy mode. `ds` sessions replace
`status-left` with their own host-labelled copy, so shared indicators belong
in the window tabs rather than in `status-left`.

A pane is pending when its program asked for attention. Agent notification
hooks call cmdblocks' `term-notify-sound`, which rings the bell and sets the
pane option `@term_notify_pending`, because tmux records a bell against a
window, never against the pane that rang it. A pending pane shows an orange `●`
before its border label, and its window's tab shows `●`, including the current
window, where the waiting agent is often beside the shell you are typing in.
The pane you are focused on never shows as pending, but an agent alone in a
background window, which is that window's active pane, still marks its tab.
`pane-focus-in` and `pane-focus-out` hooks clear the option, so visiting a pane
acknowledges it, and a pane that notified while you were in it does not light
up as you leave. tmux tracks pane focus server-wide, so another attached client
can hold a pane focused and suppress those transitions; `client-focus-in`,
`after-select-pane`, `after-select-window`, and `client-session-changed` hooks
also clear whatever pane a client selects or returns to.
A nested tmux over SSH marks the remote pane in its own border; the outer layer
only sees the bell.

`prefix "`, `prefix %`, and `prefix c` open new panes and windows in the
current pane's directory, and `prefix R` reloads the config.

## Key Handling

The config intentionally enables extended keys, true color, focus events, OSC
passthrough, and hyperlink support. Those settings are part of the contract
between WezTerm, tmux, Neovim, and remote shells. Be careful changing them:
some require a fresh tmux server, not just `tmux source-file`.

Mouse bindings, which are active only with the editor overlay's mouse mode,
should preserve nested behavior. When `#{mouse_any_flag}` is set, tmux forwards
the event inward with `send-keys -M`; only bare terminal panes should be
handled by the outer tmux layer.

The Ctrl-h/j/k/l, Alt-Shift-H/J/K/L, Ctrl-backslash, and Ctrl-Tab bindings
described below live in the editor overlay's `20-editor.conf`; base owns the
ancestor relay keys (`User8`-`User13`) they depend on.

Ctrl-h/j/k/l bindings should follow focused pane ownership across nested tmux
layers. Editors and fzf receive the chord directly. Interactive transports and
nested multiplexers receive it only while their inner content has enabled
mouse reporting; that signal distinguishes a focused remote tmux, screen, or
terminal application from a plain remote shell. A plain SSH/mosh/ET shell keeps
pane navigation at the outer tmux layer, where forwarding Ctrl-h would instead
produce backspace. Foreground-process-group checks prevent stale background
transports or nested clients from stealing the chord. When a remote nested
tmux owns the chord but has no pane in that direction, `termnav relay` sends
the semantic request to the nearest parent tmux scope. The outer terminal
supplies an ordered, read-only DECRQM response as the commit barrier;
`User9`-`User13` cover every legal response state in WezTerm, xterm.js, and
other conforming terminals without a custom extension. Intermediate tmux
layers forward the private `User8` commit key. There is no terminal-specific
parent fallback: unresolved ancestry is consumed instead of guessed.

Alt-Shift-H/J/K/L uses the same ownership detection to move the current
Neovim split or tmux pane one directional step. Termnav owns the guarded tmux
swap and may walk arbitrary same-host tmux ancestry, but it never relays pane
movement across SSH or hands it to an outer terminal layout.

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
triggering client's PID, TTY, terminal type, and source scope to the one-shot
`termnav navigate` router. It switches the first reachable
parent tmux with multiple windows, or uses the outer client's per-window VS
Code socket or WezTerm TTY. Every selected client is revalidated before
dispatch; unresolved ties and stale identities fail closed.

Alt-Shift-bracket tab-move bindings follow the same ownership rule, except edge
handling stops at the tmux layer when a multi-window tmux session is already at
the first or last window. A one-window tmux routes outward through the same
arbitrary-depth Termnav traversal used by pane and tab selection.

When no scope can take a gesture, such as moving a pane past the outermost
edge, `termnav navigate` exits 3 (declined). Every route ends with base's
`navigate_declined_ok` so that expected no-op stays quiet while real failures
still report their status.

Boundary router commands run in tmux's foreground through Termnav's native
one-shot dispatcher. The Neovim adapter serializes those short jobs and passes
a bounded continuation token between adjacent gestures, preserving rapid key
order without a resident worker or subprocesses on the native adjacent-pane
and multi-window fast paths.

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

Keep the TPM block at the end of `conf.d/10-base.conf` and keep continuum
last in the plugin list. Continuum injects autosave through `status-right`, so
a later plugin or status assignment, including one in a later overlay
fragment, would silently disable periodic saves. The older
manual save/restore commands and their prefix+S/prefix+R bindings were retired
(prefix+R now reloads the config): this configuration uses tmux-resurrect as
the single persistence mechanism.

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
