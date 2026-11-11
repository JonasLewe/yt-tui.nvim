# Initial implementation plan

## Scope

Create a standalone Neovim plugin that launches the existing `yt-tui` executable in a floating terminal. Match the user's existing k9s integration and support installation through a local lazy.nvim specification. Keep the plugin in its own Git repository, with an initial `v0.1.0` tag after validation.

## Interface

- Neovim 0.11 or newer, with no external Lua dependencies.
- `require("yt-tui").setup(opts)` configures the executable, default arguments, window width and height, border, and title.
- `:YtTui [arguments]` and `require("yt-tui").open(args)` open the terminal.
- `:YtTuiClose` and `require("yt-tui").close()` stop and close the session.
- The local lazy.nvim specification maps `<leader>yy` and adds a YouTrack which-key group.

## Terminal behavior

1. Create a centered float covering approximately 90% of the editor and resize it when Neovim changes size.
2. Start the program directly with an argument list, preserving issue URLs and arguments without shell evaluation.
3. Mark the buffer with `terminal_passthrough` before terminal initialization and enter terminal mode.
4. Reuse the current session when opening again without arguments. Require closing it before supplying different arguments.
5. Leave terminal-mode keys to the application. In terminal normal mode, `q` and Escape close the session.
6. Stop the process and release the buffer, window, and event handlers on explicit or external closure.
7. Close automatically on success, retain output on failure, and keep callbacks from old sessions from affecting new ones.

The first release does not persist hidden sessions or bridge the external editor into the parent Neovim instance. It inherits the executable's environment and configuration.

## Work allocation

- Runtime implementation: Lua module and command entry point.
- Regression coverage: headless Neovim with real terminal jobs and fixture processes.
- Independent review: lifecycle handling, terminal key compatibility, and local configuration integration.
- Integration: documentation, local lazy.nvim specification, end-to-end checks, Git history, and installation.

## Acceptance checks

- Launch, repeated invocation, argument forwarding, and window resizing work.
- Missing executables and invalid options fail cleanly.
- Successful and unsuccessful process exits follow the documented behavior.
- Closing the window or deleting its buffer stops the process without leaving stale callbacks.
- Reopening quickly cannot be closed by a previous process's exit callback.
- The existing terminal passthrough convention is respected.
- The installed executable opens inside Neovim and exits cleanly.
- The user's configuration loads the new local plugin and `<leader>yy` mapping.
- Existing unrelated configuration edits are preserved.
- The standalone repository has a clean committed state and an initial release tag.
