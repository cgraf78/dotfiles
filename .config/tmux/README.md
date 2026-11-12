# tmux Config

`tmux.conf` is a thin loader that sources `conf.d/*.conf` in lexical order.
The base `conf.d/10-base.conf` owns terminal multiplexing policy: sessions,
status, clipboard, persistence, mouse mode, and the tmux side of the terminal
navigation stack (pane, tab, and link routing across editor, nested-tmux, and
remote layers). Recognizing Vim, Neovim, and fzf as the owner of a key belongs
here too, so tmux hands them their chords instead of taking them; base never
runs Neovim commands itself. The `dotfiles-nvim` overlay adds
`conf.d/20-editor.conf` for the keys that only make sense with Neovim on the
other end.

## Integration Points

- The default-server Continuum coordinator, its cheap save gate, and
  clipboard-history paste use `tmux-tools`.
- Option-Space opens `tmux-tools`' `tmux-command-palette`, an fzf picker
  over every key binding that has a note; until `tmux-tools` provides it, the
  key says so.
- `prefix o` and `prefix O` copy the last one or N command output blocks
  through `tmux-tools`' `tmux-copy-last-output`, and `prefix A` pastes the
  last block into the window's agent through its `--print` mode.
- Automatic session persistence uses TPM, `tmux-resurrect`, and
  `tmux-continuum`, installed as shdeps-managed repository checkouts.
- Alt-Shift-[ and Alt-Shift-] mirror WezTerm tab reordering for tmux windows:
  the bindings forward into nested terminal apps, swap tmux windows only when
  the current window is not already at the edge, and route one-window
  boundaries through Termnav's native one-shot router. Vim, Neovim, and fzf
  panes receive the chord too.
- Copy-mode clipboard piping uses the dotfiles `clip` command, which falls
  back to platform clipboard tools. `copy-command` is `clip capture --history-only`, so
  double-click word selection and triple-click line selection join Enter,
  Ctrl-c, and vi-style `v`/`y`.
- `prefix Tab` opens extrakto, a shdeps-managed checkout sourced directly
  rather than through TPM, to fuzzy-pick a path, URL, hash, or word from the
  pane. Enter uses stock `tmux_osc52` mode to pass the selected text atomically
  to tmux; Ctrl-t cycles between that and buffer-only mode. These extracted
  copies bypass `clip` history. Stock extrakto still selects its client
  implicitly, so it does not have the explicit-client guarantee of last-output
  copying.

Base also owns:

- `set -g mouse on`, which its copy-mode mouse bindings rely on.
- Ctrl-Tab and Ctrl-Shift-Tab window switching, which forwards into Vim,
  Neovim, fzf, and nested terminal apps, switches tmux windows when the
  current tmux layer owns the chord, and sends one-window boundaries through
  Termnav's native one-shot router with exact client identity.
- Ctrl-h/j/k/l, Alt-Shift-H/J/K/L, and Ctrl-backslash pane navigation, with
  the same ownership rules (described below).
- Ctrl-click routing, which delegates to `termnav tmux follow-click`: URLs
  open in the browser on the desktop running the terminal, and file paths open
  in a running Neovim, or Termnav says it cannot. A pane whose app has mouse
  reporting on keeps the click, except for a known agent (`@pane_agent`), a
  pane in a mode such as copy mode, and an OSC 8 `http`, `https`, or `mailto`
  link under the pointer, which Termnav takes.

The editor overlay's `20-editor.conf` adds only what needs Neovim:

- File opens through `termnav nvim open` (`prefix e`).
- Ctrl-Shift-V forwarding as a private escape sequence for Neovim's yank
  history; without Neovim, a shell would receive it as garbage.

The Neovim side of navigation (Termnav's Lua adapter, where local Neovim
splits stay process-free and edges hand back to tmux) lives in the overlay's
Neovim config, not in tmux. Without it, Ctrl-h/j/k/l into a Vim or Neovim pane
stay there: the editor receives them, but nothing hands them back at its edge.

Keep generic tmux helper commands in their owning dependency repos. This
directory should wire those commands into the user's tmux experience, not own
their implementation.

## Labels and Status

Long-running shell commands use the existing attention path: successful
completion shows a green dot, while failure shows a red dot in the window tab
and a red dot followed by `exit N` in the pane border. Each state present in a
window adds its own dot, so failure never hides other agents' dots. Visiting
the pane clears the mark and exit status; `prefix a` reaches failed commands
through the same navigation as agent notifications, ahead of other kinds. The shell
keeps its existing duration threshold and suppresses notifications for watched
panes, Ctrl-C, and Ctrl-Z.

Windows name themselves from what they host, not from the focused pane. Every
pane whose foreground app enables mouse reporting (agents, editors, a nested
tmux over SSH) contributes its name, in pane order; shells and short-lived
commands such as `git`, `make`, or `less` never do, so tabs do not flicker
while a side shell works. A window of plain shells falls back to the active
pane's directory. The agents AgentGuard integrates (`claude`, `codex`,
`gemini`, `grok`, `muse`, `opencode`) always count by name, because some,
such as muse, draw inline without mouse reporting. A versioned binary such
as `muse-bin-1.4.3-R5018.1`, whose name changes on every upgrade, is shown as
the bare agent name; names that merely start with one, such as `museum`, are not. Sandboxes, SSH transports, and interpreters (`bwrap`,
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

Pane borders lead with the pane's command targets, `window.pane` and the stable
`%pane_id` in parentheses, as in `2.1 (%42)` followed by two spaces, so a pane
can be named in `tmux` commands at a glance. In a nested tmux over SSH, the
inner border's targets name panes on the remote server. The rest of the label
uses the same rules as window names: interactive panes show the app and its own
title (an agent's task, Neovim's file), and shells show a home-relative
directory. `ds` strips host literals such as `#{host}` from
`pane-border-format`, so host comparisons live in the `@pane_*` user options
rather than in that option itself.

The status bar has its own background so the window list reads as a tab
strip. Only the current tab is highlighted; a background window that wants
attention shows it through its dots, not a tab color. Tabs show `[Z]` for a
zoomed pane and `[COPY]` while the active pane is in copy mode. `ds` sessions replace
`status-left` with their own host-labelled copy, so shared indicators belong
in the window tabs rather than in `status-left`.

Window tabs and pane borders show static colored dots that say what each
agent needs. A tab shows one dot for each state present among its panes, most
severe first; a pane's border shows its own dot. Nothing animates: a dot
changes only when a pane's state changes.

| Dot | State | Meaning | Clears when |
| --- | --- | --- | --- |
| red | blocked | an agent turn died (API error, rate limit) | the agent resumes or ends |
| red | failed | a long shell command failed (`exit N` follows the dot on the border) | you look |
| yellow | waiting | the agent needs an answer: permission prompt, question, plan approval | the agent resumes or ends |
| green | done | a turn finished and you have not looked | you look |
| blue | working | a turn is running and nothing else needs you | the turn ends |

The current tab is shown in bright, bold text with no fill, and its label is
underlined without the padding spaces on either side. The dots follow each
tab's label and badges on the status-bar background, never underlined, so
every color stays visible.

A pane needs attention when its program asked for it. Agent notification
hooks call tmux-tools' `term-notify-sound`, which rings the bell and sets the
pane option `@term_notify_pending`, because tmux records a bell against a
window, never against the pane that rang it. The option's value is the kind:
`done`, `waiting` or `blocked` (the legacy value `1` means `done`), and
`@term_notify_exit_status` marks a failed shell command. The pane you are
focused on never shows its own dot, but an agent alone in a background window,
which is that window's active pane, still marks its tab.

A glance acknowledges only informational dots. `pane-focus-in` and
`pane-focus-out` hooks clear done and failed marks, so visiting a pane
acknowledges it, and a pane that notified while you were in it does not light
up as you leave. tmux tracks pane focus server-wide, so another attached
client can hold a pane focused and suppress those transitions;
`client-focus-in`, `after-select-pane`, `after-select-window`, and
`client-session-changed` hooks also clear whatever pane a client selects or
returns to. Waiting and blocked marks need an action, so they stay through a
visit until AgentGuard clears them on the agent's next activity: a prompt, a
tool call, a turn that ends, or the session ending. After you answer a
permission prompt, yellow therefore stays until the agent's next tool call or
turn end. A sticky mark never outlives its agent: a pane back at a shell
prompt shows none, and a visit clears it once the pane runs neither a known
agent nor a wrapper (sandbox, interpreter, SSH) that could host one.

The client-scoped snapshot publisher aggregates every window in the attached
session, counting each pane once by its dot. Termnav forwards leased child
summaries one parent at a time through same-host tmux and existing SSH
relays, with the waiting count in its own lease beside them. The containing
tmux window and WezTerm tab therefore show a nested layer's dots without
parsing colored titles or polling each pane in a separate process.

A pane is busy while its agent works on a request. AgentGuard's lifecycle hooks
set the pane option `@term_busy` through tmux-tools' `term-pane-mark` when a
prompt is submitted and clear it when the turn ends: on Stop or session end,
and on an Interrupt or failed-request event for runtimes that report one
(Codex, Muse, OpenCode, and Claude's StopFailure) while AgentGuard telemetry is
enabled. Claude reports no event for an Esc interrupt. When Esc dismisses a
prompt, its idle notification about 60 seconds later clears the busy mark; when
Esc interrupts a running tool, no hook fires at all, so the pane stays busy
until the next prompt or turn. Gemini and
Grok report no interrupt or other turn-ending event, so after an Esc their
panes stay busy until the next turn or the session ends. A busy pane is blue
only while it shows no other dot.
Only the pane terminal's foreground agent changes the mark, so an agent it
launches (a reviewer, a memory classifier), which inherits the pane but not its
terminal, cannot set or clear it, nor mark the pane pending; Codex's
transcript-less background sessions are ignored. A pane back at a shell prompt
never shows as busy, which hides a mark left by an agent killed mid-turn; it
shows again under the next program in that pane until the next agent's turn
ends.

`prefix a` jumps to the next pane needing attention in the current session,
most severe first (red, then yellow, then green), each in tab then pane order.
Arriving acknowledges a done or failed pane; waiting and blocked panes stay
marked, so repeated presses cycle through them. With nothing else left it says
nothing else is waiting.

`prefix A`, pressed in a shell pane, pastes that pane's last command and its
output into the window's agent (its first agent pane) as one bracketed paste
and focuses the agent, the usual step after a test fails in a side shell.

The shell prompt marks where each prompt and each command's output start
(OSC 133), but only inside tmux, so a terminal's own shell integration never
sees a second set. tmux 3.4+ moves between those marks: `prefix k` opens copy
mode on the last command's prompt, and `[` and `]` in copy mode step to the
previous or next prompt. Older releases ignore the marks.

`prefix n` opens a window for a new task in the current pane's directory: a
menu picks the agent in a fixed order (`c` claude, `x` codex, `m` muse, `s`
shell only, `o` any other command line, such as `codex resume`), and the
window is named automatically like any other. The agent starts in the left
pane (60%) beside a shell; it is typed into that pane's shell, so quitting it
leaves a shell rather than closing the pane. This replaces tmux's default
`prefix n` (next window), and `prefix p` (previous window) is unbound with it;
C-Tab and C-S-Tab switch windows.

`prefix g` opens a throwaway shell in a popup over the current pane, starting
in its directory, for a quick check without splitting the window; exiting the
shell closes it. `prefix G` opens `lazygit` there the same way, or says it is
not installed. Keys typed in a popup go only to the popup, so the navigation
bindings never reach the pane behind it, and nothing persists afterwards.

`prefix "`, `prefix %`, and `prefix c` open new panes and windows in the
current pane's directory, and `prefix R` reloads the config.

`prefix X` closes the current window and every pane in it after asking, the
way `prefix x` closes one pane (tmux's own `prefix &` still works too).

`prefix !` (tmux's default) breaks the current pane out into its own window.
`prefix j` sends the current pane into a window chosen from a tree, and
`prefix J` pulls a chosen pane in beside the current one, so a pane can be
popped out to watch full-size and put back afterwards.

## Menus and Command Palette

Option-Space opens a command palette: an fzf popup listing every key binding
that has a note (the list `prefix ?` shows), description first and key
second, such as `Copy the last N command outputs   prefix O`. Type to filter,
Enter runs the binding, Escape closes it. The popup only picks: once it has
closed, tmux types the chosen key for your client (tmux 3.4 or newer), so the
binding acts on the pane you opened the palette from, and its prompts and
menus open over that pane. On older tmux the palette turns the prefix on and
names the key to press. The list leaves out mouse bindings and tmux's
`Select window 0` to `9`. The palette is `tmux-tools`' `tmux-command-palette`
and needs fzf. Option-Space needs a terminal that sends Option as Meta:
WezTerm does for the left Option key, while macOS Terminal, iTerm2 and VS
Code need their Option-as-Meta setting. Every right-click menu opens the
palette too.

The key goes where the other root keys go: into SSH, mosh, ET or a nested
tmux while it reports mouse, so the innermost tmux opens its own palette, and
it stays at this layer while the pane is in copy mode. A remote tmux that has
not loaded this config yet passes it to its program instead.

Right-click menus replace tmux's defaults:

- The pane menu (right-click a pane, or `prefix >`) copies the last command
  output or the last N, pastes from clipboard history, splits in the pane's
  directory, zooms, moves the pane to a new window, jumps to the next pane
  needing attention, opens a task window, a scratch shell or the palette, and
  closes the pane after asking. Under the pointer it also offers tmux's word,
  line and link items; copies go to the clipboard and clipboard history. In
  copy mode, where a right-click still leaves copy mode, Option-right-click
  or `prefix >` adds tmux's scroll-to-top and bottom items. Right-clicking a
  pane selects it first.
- The window menu (right-click a tab, or `prefix <`) moves the window left or
  right, stopping at the ends as Alt-Shift-[ and ] do, renames it, names it
  automatically again, opens a window or task window, opens the palette, and
  closes the window after asking, as `prefix X` does. Right-clicking a tab
  selects it first, as right-clicking a pane does.
- The session menu (right-click the session name) stays close to tmux's:
  next and previous session, renumber, rename, new session or window in the
  pane's directory, and the palette.

A program using the mouse (Neovim, a nested tmux, a remote session reporting
mouse) keeps the plain right-click, as with tmux's defaults; Option-right-click
always opens the menu. Items that cannot apply are greyed out, such as Zoom in
a window with one pane or Move left on the first window. A click opens a menu
and another chooses, and press, drag and release also works. The pane menu
opens below the pointer, or above it near the bottom of the screen, rather than
over it, where the release of the click would close it. Each item's key
matches the prefix binding it mirrors, and Space opens the palette. tmux's
Respawn items (which kill the running program without asking), its marked-pane
items and its swap up and down are left out; `prefix m` and Alt-Shift-H/J/K/L
cover those.

Each menu's title and items are defined once, in `%hidden` config variables
(tmux 3.2 or newer), and spliced into the mouse, Option-mouse and keyboard
bindings, which differ only in position. Items reuse the key bindings' own
commands where they can. tmux leaves mouse bindings out of `prefix ?`.

## Key Handling

The config intentionally enables extended keys, true color, focus events, OSC
passthrough, and hyperlink support. Those settings are part of the contract
between WezTerm, tmux, Neovim, and remote shells. Be careful changing them:
some require a fresh tmux server, not just `tmux source-file`.

Mouse bindings should preserve nested behavior. When `#{mouse_any_flag}` is
set, tmux forwards the event inward with `send-keys -M`, so Neovim, a nested
tmux, or a remote session decides at its own layer. Right-click does so too;
Option-right-click opens this layer's menu. Ctrl-click makes three exceptions,
all format-only:

- A known agent (`@pane_agent`) never gets it, so links and file paths in its
  output behave as in a shell. Codex ignores the click, and Claude opens only
  URLs, through `$BROWSER` on the host it runs on.
- A pane in a mode such as copy mode shows tmux's view, not the app's screen.
- An OSC 8 browser link (`#{mouse_hyperlink}`, tmux 3.4 and later) opens on
  the same desktop whichever layer resolves it, so the outermost tmux takes it.
  File links stay with the app, which knows their host and directory.

Ctrl-drag skips the link exception, so a drag that starts off a link is not
split between tmux and the app as it crosses linked cells; one that starts on
a link goes to tmux for the press and to the app afterwards. A drag Termnav
owns does nothing, and a fast second or third press keeps the click's owner.
When the terminal cannot take a URL, Termnav falls back to `$BROWSER` from its
run-shell job, which reads tmux's global environment rather than shell
startup files, so loading the config publishes the value shell startup
(env.d) chooses there.

The Ctrl-h/j/k/l, Alt-Shift-H/J/K/L, Ctrl-backslash, and Ctrl-Tab bindings
described below live in `10-base.conf` beside the ancestor relay keys
(`User8`-`User13`) they depend on.

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

## Clipboard fidelity and delivery

`clip` stages exact bytes in owner-only files and atomically publishes history.
It preserves trailing newlines and empty payloads, escapes picker previews,
and emits original selected bytes. History files are private and unsafe
symlink/directory replacements are rejected. Existing history permissions are
tightened without reading or changing payloads.

For tmux selections, tmux is the single OSC 52 writer and `clip capture
--history-only` records history without a competing asynchronous native write.
Explicit `clip copy` and ordinary `clip capture` retain native backend support.
The frontend owns normal paste across SSH. Deliberate last-output copies carry
the invoking client and pane and enter history through the same copy API.

`prefix P` uses `clip pick --paste-pane` inside a real popup. Each invocation
owns a distinct completed handoff and an explicit underlying pane; cancellation
cannot consume an older handoff and concurrent clients cannot exchange their
selection files. Native fallback paste uses the same transaction. Failed or
ambiguous delivery retains recovery bytes and never retries automatically.
Absent or empty history returns the distinct no-selection status 3; the popup
binding treats that and explicit cancellation as normal, preserving typing
and any existing pane modes. Other failures remain errors.
A zero-byte scoped tmux clipboard clear is rejected explicitly because tmux
ignores empty clipboard writes; native clipboard clears remain supported.

Extrakto uses its public `tmux_osc52` mode, which supplies the actual selected
text directly to `tmux set-buffer -w`. Its foreground/background clipboard
hooks first reread the global buffer, so another client's copy can replace the
selection between those operations. Those modes are excluded from the default
cycle and the previous custom pipeline is removed on reload. Extracted copies
therefore do not enter `clip` history. Upstream's public mode still uses
implicit client selection; no custom plugin fork or exact-client claim is
introduced here.

## Image paste

WezTerm's `Ctrl-V` can hand a clipboard image to an agent in a tmux pane
(see the WezTerm README). It sends the private trigger key `user-keys[14]`
(`User14`), and every tmux layer routes it once:

- A pane in a mode such as copy mode, or a window with synchronized panes,
  declines with a message, so neither the trigger nor the transfer behind it
  reaches an application or several panes.
- SSH, ET, or a nested tmux with mouse reporting on receives it with
  `send-keys -H`, so a remote or nested tmux running this config routes it
  again. The check has its own predicate: unlike pane navigation, a local
  Vim, Neovim, or fzf pane never receives it.
- mosh, and SSH or ET with mouse reporting off (no tmux on the far side),
  decline with a message.
- Otherwise this tmux is innermost: it opens a small popup running
  `termnav paste-image receive` for the active pane and this exact client.
  The receiver saves the image as a private PNG under
  `$XDG_CACHE_HOME/termnav/paste-images` on this host and bracket-pastes its
  absolute path into the pane.

That reaches local tmux and one remote hop over SSH or ET. The receiver exits
1 after reporting a failure itself, so only other statuses open tmux's error
view. The existing `C-v` fallback binding is unchanged.

Known limitations, accepted because remote tmux running this config is the
supported setup:

- Mouse reporting over SSH or ET is the same gate pane navigation uses, and
  it cannot tell a remote tmux from another mouse-aware program. A trigger
  forwarded to remote Neovim or Vim is typed into it: Neovim in insert mode
  inserts a stray character, and Vim inserts one and leaves insert mode. No
  receiver answers, so no image data follows.
- A remote or nested tmux that has not reloaded this config yet has no
  `user-keys[14]` and passes `^[[777010u` to its application. That window
  closes when the host's scheduled update reloads tmux.
