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
  cmd = { "YtTui", "YtTuiClose" },
  keys = {
    { "<leader>yy", "<cmd>YtTui<cr>", desc = "Open YouTrack" },
  },
  opts = {},
}
```

[examples/lazy.nvim.lua](examples/lazy.nvim.lua) also adds a YouTrack group to an existing which-key configuration. The core plugin does not assign a global key mapping; the specification above supplies `<leader>yy`.

For another plugin manager, put the repository on `runtimepath` and call `require("yt-tui").setup({})`. Commands also work with defaults without calling setup.

## Usage

| Action | Command or key |
| --- | --- |
| Open YouTrack | `<leader>yy` with the example configuration, or `:YtTui` |
| Open an issue directly | `:YtTui https://youtrack.example.com/issue/PROJ-123` |
| Leave terminal mode | `Ctrl+\`, then `Ctrl+n` |
| Close from terminal normal mode | `q` or `Esc` |
| Close by command | `:YtTuiClose` |

While in terminal mode, all keys go to `yt-tui`, including Escape and Ctrl+C. The plugin sets `b:terminal_passthrough` before starting the terminal; a user configuration can use this flag to skip terminal mappings such as `kj`.

The float follows Neovim's size. Calling `:YtTui` again focuses the existing window. To pass different arguments, close the current session first. Closing the window stops its process; reopening starts a fresh session. A normal application exit closes the float automatically. If the process fails, the terminal remains visible so you can read the error, then close it or start a new session.

The process inherits Neovim's current directory and environment. `yt-tui`'s external-editor commands continue to use `$EDITOR` (or its default editor), inside the floating terminal. Exit that editor to return to YouTrack.

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

`args` is a list of default command-line arguments. Arguments passed to `:YtTui` or `open()` are appended. The executable and arguments are passed as an argument vector, without shell evaluation. Do not put shell commands or extra flags in the `executable` string.

The Lua interface is also available:

```lua
require("yt-tui").open()
require("yt-tui").open({ "https://youtrack.example.com/issue/PROJ-123" })
require("yt-tui").close()
```

## Development

Run the regression suite from the repository root:

```sh
sh tests/run.sh
```

The suite requires Neovim and Python 3 and uses a headless editor with fixture processes. It does not require a YouTrack account or contact a YouTrack server.

The initial implementation plan is recorded in [docs/implementation-plan.md](docs/implementation-plan.md).
