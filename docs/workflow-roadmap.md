# YouTrack development workflow roadmap

Recorded: 2026-11-11. Scope: `yt-tui` and its separate `yt-tui.nvim` launcher.
This file records proposals, not commitments to implement all of them. Each
independent feature should have its own branch and focused review. Hide/resume
is the first approved implementation; the other items remain proposals.

## Existing capabilities to build on

The TUI already provides issue and article editing, external Neovim editing,
numbered panels, global search, one favorite view per server, manual time
entries, clipboard operations, attachment selection with zoxide, direct issue
URL launches, and optional GitLab TUI integration. Custom quick actions can
already combine assignment, state/field changes, comments, and board changes.
Configuring these actions is an immediate improvement that needs no new feature.

## Proposed additions, in priority order

| Priority | Addition | Workflow benefit | Owner and acceptance criteria |
| --- | --- | --- | --- |
| 1 | Hide and resume the float | Switch between code and YouTrack without losing the current issue, pane, filter, scroll position, or draft. | `yt-tui.nvim`: reuse the same terminal process and buffer; distinguish resume, fresh start, and stop; cover cleanup and failures. Detailed plan below. |
| 2 | Git context awareness | Open the issue named in the current branch, or select the project associated with the current repository. | Plugin plus TUI launch interface: explicit repo/project mapping; recognize issue IDs; handle ambiguous/missing matches without guessing; explicit issue arguments take precedence. Optional follow-up: create a branch/worktree from an issue using a reviewable name and never overwrite local work. |
| 3 | Capture selected code into a draft | Turn a selection or error output into an issue/comment draft without repetitive copying. | Plugin plus TUI draft input: include selected text, filename, line range, and an optional repository permalink; preview before submission. Consider KB drafts once issue/comment capture works. |
| 4 | Edit in the current Neovim session | Share existing buffers, registers, windows, and editor context instead of launching nested Neovim. | Plugin/editor bridge: open a normal Markdown buffer, wait for completion, return the result to the TUI draft; handle cancel, changed buffers, shutdown, and standalone fallback. Saving the buffer must not silently submit to YouTrack. |
| 5 | Durable draft recovery | Recover unfinished issues, comments, and articles after quitting or a crash. | TUI: local storage scoped by server/user/target; restore/discard UI; private file permissions; no credentials in drafts; conflict checks before saving recovered content; cleanup after successful submission. In-memory error recovery already exists. |
| 6 | Multiple named saved searches | Jump between recurring queues such as assigned work, reviews, and sprint work. | TUI: named server-scoped queries with a picker, persistence, and migration of the current single favorite; preserve existing search/filter behavior. |
| 7 | Multi-issue actions | Apply a consistent change to several selected tickets during triage. | TUI: explicit selection and action preview, permissions and partial-failure reporting, and safe retry; reuse existing action definitions. Current actions target one selected issue. |
| 8 | Running work timer | Record a duration while working instead of calculating it manually. | Optional TUI follow-up: start/pause/stop tied to an issue; survive interruption; review duration/date/work type before posting; retain the existing manual time-entry workflow. |

The strongest differentiator is integration with the local coding context.
Keep the browser available for visual board planning, reporting, administration,
and image-heavy documentation instead of trying to reproduce every web screen.

## Hide/resume implementation plan

Status: implemented. Branch: `feature/persistent-session` in `yt-tui.nvim`.

### User-facing contract

- `:YtTui [arguments]` / `open(args)` opens, resumes, or focuses the one existing
  session. New arguments must never silently replace a live session.
- `:YtTuiToggle` / `toggle()` hides a visible float or resumes the existing
  hidden session. The user's `<leader>yy` maps to this action.
- `:YtTuiHide` / `hide()` and terminal-normal-mode `q`/Escape hide the window.
  They retain the terminal buffer and process. An optional buffer-local
  `hide_key` can hide directly from terminal mode. With a compatible TUI,
  browsing `q` requests hide and `Q` fully quits. Forms, searches, and the
  nested editor keep their normal input; no leader sequence is intercepted.
- `:YtTuiRestart[!] [arguments]` / `restart(args, opts)` intentionally starts
  fresh. With a live session, ask before discarding it; cancellation is the
  default. `!` / `{ force = true }` is the explicit opt-out. `<leader>yt` uses
  the confirming command. Validate the launch configuration before stopping.
- Restart without arguments does not reuse a previous invocation's issue URL.
  It uses configured executable/default arguments and normal yt-tui startup.
  A server chooser/login may precede the dashboard; this is not a simulated
  sequence of Escape presses. Configured default arguments remain intentional.
- `:YtTuiClose` / `close()` keeps its existing meaning: stop the process and
  release the window, buffer, and callbacks. Terminal application quit also
  ends the session. Hide/resume lasts only for the current Neovim process.

### Lifecycle and boundaries

1. Separate the terminal session from its current window. Hiding closes only
   the owned float; reopening recreates it at the current editor dimensions.
2. Reuse exactly one process and buffer. Preserve the application's in-memory
   navigation and draft state without serializing credentials or UI internals.
3. An external float closure or buffer replacement hides the session. Never
   close a window that has been repurposed. Explicit terminal buffer deletion
   and Neovim shutdown terminate and clean up the session.
4. A successful process exit cleans up even while hidden. A failed process
   retains diagnostic output; reopening reveals it, with an explicit restart
   action. A hidden failure must not steal focus.
5. Guard deferred callbacks and asynchronous restart confirmation against old
   session identities; they must not affect a newly opened session.
6. Retain terminal passthrough, external-editor behavior, safe argv forwarding,
   minimum Neovim version, existing window styling, and configuration defaults.
7. Show/hide is process persistence, not polling or refresh: existing `r`
   refreshes server data. Do not reset forms or make API mutations on resume.

### Implementation sequence

1. Commit this roadmap before implementation.
2. Refactor session/window lifecycle and add explicit commands/Lua API.
3. Update README, help, and lazy.nvim example; update the user's local mappings
   while preserving the scoped `EDITOR=nvim` launcher and unrelated settings.
4. Run headless tests with real PTY fixture jobs. Cover repeated hide/resume,
   process identity and terminal state, resize while hidden, external close,
   buffer replacement/deletion, cross-tab behavior, restart confirm/cancel,
   argument handling, hidden exits/failures, stale callbacks, and cleanup.
5. Review the implementation independently, then run a configured-Neovim
   smoke check with the installed TUI without modifying YouTrack data.
6. Commit the implementation separately on the feature branch and make it
   available in the locally installed plugin repository. No remote publication
   is required for this change.

### Completion record

The initial hide/resume implementation did not change the Go application.
The later q/Q integration below adds application-aware quitting controls. Reopening from another tab moves the same terminal to the current
tab; toggling hides any owned float visible in that tab. Buffer unloading,
as well as deletion, stops the session. Failed output requires explicit
restart, replacing the old automatic retry behavior so diagnostics are kept.

Initial validation: all 38 headless tests with real PTY processes pass on
Neovim 0.12.4.
Coverage includes process/buffer/content identity, repeated hide/resume without
callback leaks, resize and cross-tab movement, restart confirmation and literal
arguments, hidden exits/failures, stale callbacks, and synchronous Neovim hooks
that close/restart/repurpose the terminal while it is opening. Tests also verify
that a nested Neovim process survives hiding and is stopped on explicit close
or parent-editor exit. Independent lifecycle review, documentation consistency,
help-tag generation, example Lua parsing, and whitespace checks passed.

The historical `implementation-plan.md` describes v0.1.0; this plan supersedes
its close/reopen lifecycle decisions. Items 2-8 above remain unimplemented
proposals; configuring existing quick actions remains separate setup work.

### Earlier keymap refinement (2026-11-11, superseded)

The native terminal-mode escape was awkward on the user's keyboard. The first
refinement enabled `hide_key = "<C-w>q"` in the local configuration and examples
for direct hiding with Vim's window-close gesture. At that point `<leader>yt`
resumed and `<leader>yR` started fresh. The preferred controls below replace
that setup; the optional `hide_key` setting remains supported.

The plugin option defaults to `false` and accepts a nonempty key sequence when
enabled. Its mapping is local to the session's terminal buffer in terminal and
normal modes; configuration changes apply to the next fresh session. The chord
is reserved for the outer float even inside nested Neovim. Other keys,
including `kj`, Escape, and leader sequences, remain available to the child.
The prefix follows the user's `timeoutlen`, so Ctrl+w alone may wait briefly
before reaching the child. The option can be changed or disabled without
altering global terminal mappings or the existing hide/resume lifecycle.

Refinement validation: all 41 tests pass. The added checks drive real terminal
input through a separate Neovim instance and capture raw PTY bytes, verifying
direct hide/resume, unchanged process identity, ordinary-key passthrough,
alternative/disabled mappings, and rejected invalid configuration.

### Preferred quit controls (2026-11-11)

The user requested `q`/`Q` for the two exit modes and reassigned the leader
keys. The current workflow supersedes the earlier Ctrl+w, q recommendation:

- Browsing `q` hides and preserves the session; `Q` fully quits it.
- `<leader>yt` starts fresh through the existing confirming restart action.
- `<leader>yy` toggles/resumes the float. The old `<leader>yR` example is removed.
- Forms, search inputs, and nested editors receive literal letters. Close an
  active menu or finish/cancel editing before using browsing quit controls.
- Neovim terminal-normal-mode `q`/Escape hides; `Q` explicitly stops the process.
- The optional `hide_key` setting remains available, disabled by default. It is
  removed from the local setup and examples because browsing `q` now hides.

Implementation belongs on `feature/nvim-quit-controls` in the TUI and plugin
repositories. The TUI decides when quitting keys are active and sends a fixed
hide request only when launched by the plugin. The plugin does not map terminal
letters, parse screen contents, or interfere with the external editor. This
requires the matching TUI build; older binaries continue to quit on `q`.
The existing hide/resume, restart confirmation, and Lua command API stay intact.

Plugin validation: all 45 tests pass, including real terminal q/Q input,
ordinary typing, process identity across hide/resume, child-only capability
environment, unrelated control sequences, stale-window/session requests, and
cleanup after a full quit. Documentation and independent runtime review passed.
