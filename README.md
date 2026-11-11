# yt-tui.nvim

Open [yt-tui](https://github.com/JonasLewe/yt-tui) in a centered Neovim floating terminal. Browse and edit YouTrack issues using the same executable and configuration as your shell. This is a separate Lua plugin for the Go application, which is based on [nospor/yt-tui](https://github.com/nospor/yt-tui).

## Requirements

- Neovim 0.11 or newer.
- `yt-tui` installed on Neovim's `PATH`, or an explicit `executable` path in setup.

There are no Lua plugin dependencies. Credentials remain managed by `yt-tui`.
Install the [Go executable separately](https://github.com/JonasLewe/yt-tui#-build-this-fork-from-source); installing this plugin does not build or download it. The linked fork includes the browsing `q`/`Q` integration described below.

## Install with lazy.nvim

Add the following specification to your lazy.nvim configuration:

```lua
return {
  "JonasLewe/yt-tui.nvim",
  name = "yt-tui.nvim",
  main = "yt-tui",
  cmd = { "YtTui", "YtTuiToggle", "YtTuiHide", "YtTuiRestart", "YtTuiClose" },
  keys = {
    { "<leader>yt", "<cmd>YtTuiRestart<cr>", desc = "Start YouTrack fresh" },
    { "<leader>yy", "<cmd>YtTuiToggle<cr>", desc = "Toggle YouTrack" },
  },
  opts = {},
}
```

[examples/lazy.nvim.lua](examples/lazy.nvim.lua) also adds a YouTrack group to an existing which-key configuration. The core plugin does not assign global mappings; the specification above supplies `<leader>yt` and `<leader>yy` in normal mode.

For local development, replace `"JonasLewe/yt-tui.nvim"` with `dir = vim.fn.expand("~/Developer/yt-tui.nvim")` to use your checkout instead of the GitHub copy.

For another plugin manager, put the repository on `runtimepath` and call `require("yt-tui").setup({})`. Commands also work with defaults without calling setup.

## Usage

| Action | Command or key |
| --- | --- |
| Hide while browsing, keeping your place | `q` |
| Fully quit while browsing | `Q` |
| Start fresh, asking before discarding a live session | `<leader>yt` with the example configuration, or `:YtTuiRestart` |
| Toggle the float, resuming your existing session | `<leader>yy` with the example configuration, or `:YtTuiToggle` |
| Open, resume, or focus YouTrack | `:YtTui` |
| Open an issue directly when no session exists | `:YtTui https://youtrack.example.com/issue/PROJ-123` |
| Hide by command | `:YtTuiHide` |
| Start fresh without confirmation | `:YtTuiRestart!` |
| Stop and release the session by command | `:YtTuiClose` |

While browsing yt-tui, press **`q` to hide** or **`Q` to fully quit**. From your code, `<leader>yy` toggles the float and resumes your place; `<leader>yt` starts fresh. No terminal-mode escape is needed.

These browsing keys require a compatible yt-tui build with Neovim hide integration. Older yt-tui binaries keep their original quit behavior, so `q` still exits them. Other executables retain their own key handling; the plugin does not turn arbitrary programs' `q` into a hide command.

The letters remain normal input in forms, searches, and your nested editor. Close an active menu or finish/cancel editing before using the browsing quit keys. The plugin does not intercept printable letters or leader sequences in terminal mode, so your editor's `kj`, Escape, and normal commands keep working. The buffer sets `b:terminal_passthrough` before starting the terminal so user configuration can skip terminal mappings such as `kj`.

If you enter Neovim's terminal normal mode, `q` or `Esc` hides the float and `Q` stops the process. `:YtTuiHide` and `:YtTuiClose` are also always available.

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
  hide_key = false,
})
```

`width` and `height` are fractions of the available editor size, greater than zero and at most one. The border uses Neovim's standard floating-window highlights and follows your colorscheme. Set `executable` to a full path if Neovim cannot find the program, for example `vim.fn.expand("~/.local/bin/yt-tui")`.

`hide_key` is an optional nonempty key sequence, such as `"<C-w>q"`, mapped only in this plugin's terminal buffer in terminal and normal modes. It defaults to `false` (disabled) and is not needed for browsing-mode `q`/`Q`. An enabled key is intercepted regardless of what the child process is doing, so use a deliberate chord rather than printable text. Choose another sequence or set `false` to restore full terminal passthrough. A mapping prefix waits for the next key according to Neovim's `timeoutlen`: with `<C-w>q`, pressing `Ctrl+w` alone may briefly wait before reaching the application. The completed hide chord is reserved even in a nested editor.

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

The plugin sets `YT_TUI_NVIM_HIDE=1` only in its child process environment. A compatible yt-tui emits the fixed OSC request `ESC ]777;yt-tui;hide BEL` when its own browsing handler accepts `q`. The buffer-local `TermRequest` callback matches the exact request and schedules hiding only for the same live session and window. It does not execute payloads or infer input state from terminal text. `Q` exits the application normally. See Neovim's [TermRequest documentation](https://neovim.io/doc/user/autocmd.html#TermRequest).

The current proposals and hide/resume design are recorded in [docs/workflow-roadmap.md](docs/workflow-roadmap.md). The historical [initial implementation plan](docs/implementation-plan.md) describes v0.1.0; the roadmap supersedes its close/reopen behavior.
