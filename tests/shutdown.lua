-- Runs in a separate parent Neovim so quitting the editor is exercised for real.
local root = assert(vim.env.YT_TUI_TEST_ROOT)
local capture = assert(vim.env.YT_TUI_SHUTDOWN_CAPTURE)
vim.opt.runtimepath:prepend(root)
local plugin = require("yt-tui")
plugin.setup({
  executable = vim.fn.exepath("python3"),
  args = { root .. "/tests/fixture.py", "nested", capture, vim.v.progpath },
})
assert(plugin.open())
assert(vim.wait(3000, function()
  return vim.fn.filereadable(capture .. ".child-pid") == 1
end, 10), "nested editor did not start")
plugin.hide()
vim.cmd("qa!")
