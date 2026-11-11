# yt-tui.nvim

Open [yt-tui](https://github.com/nospor/yt-tui) in a centered Neovim floating terminal. Browse and edit YouTrack issues using the same executable and configuration as your shell.

## Requirements

- Neovim 0.11 or newer.
- `yt-tui` installed on Neovim's `PATH`, or an explicit `executable` path in setup.

There are no Lua plugin dependencies. Credentials remain managed by `yt-tui`.

## Install with lazy.nvim

Keep this repository at `~/Developer/yt-tui.nvim` and add the following specification to your lazy.nvim configuration:

```lua
return {
  dir = vim.fn.expand("~/Developer/yt-tui.nvim"),
  name = "yt-tui.nvim",
  main = "yt-tui",
  cmd = { "YtTui", "YtTuiToggle", "YtTuiHide", "YtTuiRestart", "YtTuiClose" },
  keys = {
    { "<leader>yt", "<cmd>YtTuiToggle<cr>", desc = "Toggle YouTrack" },
    { "<leader>yR", "<cmd>YtTuiRestart<cr>", desc = "Restart YouTrack" },
  },
  opts = {},
}
```

[examples/lazy.nvim.lua](examples/lazy.nvim.lua) also adds a YouTrack group to an existing which-key configuration. The core plugin does not assign global mappings; the specification above supplies `<leader>yt` and `<leader>yR` in normal mode.

For another plugin manager, put the repository on `runtimepath` and call `require("yt-tui").setup({})`. Commands also work with defaults without calling setup.

## Usage

| Action | Command or key |
| --- | --- |
| Open, resume, or focus YouTrack | `:YtTui` |
| Toggle between YouTrack and code | `<leader>yt` with the example configuration, or `:YtTuiToggle` |
| Open an issue directly when no session exists | `:YtTui https://youtrack.example.com/issue/PROJ-123` |
| Leave terminal mode | `Ctrl+\`, then `Ctrl+n` |
| Hide from terminal normal mode | `q` or `Esc` |
| Hide by command, keeping your place | `:YtTuiHide` |
| Start fresh, asking before discarding a live session | `<leader>yR` with the example configuration, or `:YtTuiRestart` |
| Start fresh without confirmation | `:YtTuiRestart!` |
| Stop and release the session | `:YtTuiClose` |

To return to code while keeping your place, press `Ctrl+\`, then `Ctrl+n`, then `q` or `Esc`. Press `<leader>yt` from code to resume. These hide keys belong to Neovim's terminal **normal mode**. In terminal mode, all keys go to `yt-tui` or its nested editor: Escape keeps its application behavior, and the application's quit keys (`q` on the dashboard or `Ctrl+C`) end the session. The plugin sets `b:terminal_passthrough` before starting the terminal so user configuration can skip terminal mappings such as `kj`.

### Resume or start fresh

Hiding closes only the float. The terminal process and buffer stay alive, preserving the current issue, pane, filters, scroll position, and unfinished draft. Closing the float externally, or replacing its buffer with another buffer, also keeps the session. Reopening uses the current editor dimensions. If you open from another tab, the same session moves to that tab. Toggle hides a float visible in the current tab; otherwise it shows the session in the current tab.

Use `:YtTuiRestart` when you want to start over. With a live session, it asks before discarding the session and any unsaved work, with Cancel first. `:YtTuiRestart!` deliberately skips that prompt. Without arguments, restart forgets a previously supplied issue URL and uses normal `yt-tui` startup with your configured executable and default arguments. Normally this leads to the dashboard; server selection or login may appear first. A URL deliberately placed in the default `args` still applies. To replace the session with a particular issue, use `:YtTuiRestart https://youtrack.example.com/issue/PROJ-123`.

`:YtTui` with new arguments rejects an existing session instead of replacing it or ignoring the arguments. Use Restart to replace it, or Close to stop it first. `:YtTuiClose` and explicit terminal-buffer deletion stop the process and release its resources. A successful application exit cleans up automatically, including while hidden. A failed process keeps its output for inspection: reopen it with `:YtTui`, then use `:YtTuiRestart` to retry or `:YtTuiClose` to discard the output. A hidden failure does not open the float or steal focus.

Hiding keeps a live process; it does not pause background work or save drafts to disk. The session lasts only until the parent Neovim exits. Showing it does not refresh server data; use the application's existing `r` action when you want to refresh.

The process inherits Neovim's current directory and environment when started. Resume retains that process; a fresh start uses the current directory and latest setup. `yt-tui`'s external-editor commands continue to use `$EDITOR` (or its default editor) inside the floating terminal. If you hide while that editor is open, it remains open on resume. Exit it to return to YouTrack. There is no bridge to edit in the parent Neovim session yet.

## Configuration

```lua
require("yt-tui").setup({
  executable = "yt-tui",
  args = {},
  width = 0.9,
  height = 0.9,
  border = "rounded",
  title = " yt-tui ",
})
```

`width` and `height` are fractions of the available editor size, greater than zero and at most one. The border uses Neovim's standard floating-window highlights and follows your colorscheme. Set `executable` to a full path if Neovim cannot find the program, for example `vim.fn.expand("~/.local/bin/yt-tui")`.

`args` is a list of default command-line arguments. Arguments passed to `:YtTui`, `:YtTuiRestart`, or their Lua functions are appended when launching a new process. The executable and arguments are passed as an argument vector, without shell evaluation. Do not put shell commands or extra flags in the `executable` string. Calling `setup()` again changes the next fresh session, not a running or hidden session.

The Lua interface is also available:

```lua
require("yt-tui").open()
require("yt-tui").open({ "https://youtrack.example.com/issue/PROJ-123" })
require("yt-tui").hide()
require("yt-tui").toggle()
require("yt-tui").restart()
require("yt-tui").restart({}, { force = true })
require("yt-tui").close()
```

`open()`, `hide()`, and `toggle()` return a boolean indicating success. Hiding an already hidden or absent session succeeds without changing anything. `restart(args, opts)` returns true when it launches successfully **or requests confirmation**; an asynchronous confirmation may still be cancelled. It returns false for an immediate validation or launch failure. `opts.force` skips confirmation. `close()` has no return-value contract.

## Development

Run the regression suite from the repository root:

```sh
sh tests/run.sh
```

The suite requires Neovim and Python 3 and uses a headless editor with fixture processes. It does not require a YouTrack account or contact a YouTrack server.

The current proposals and hide/resume design are recorded in [docs/workflow-roadmap.md](docs/workflow-roadmap.md). The historical [initial implementation plan](docs/implementation-plan.md) describes v0.1.0; the roadmap supersedes its close/reopen behavior.
