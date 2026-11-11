if vim.g.loaded_yt_tui then
  return
end
vim.g.loaded_yt_tui = true

vim.api.nvim_create_user_command("YtTui", function(opts)
  require("yt-tui").open(opts.fargs)
end, { nargs = "*", desc = "Open or resume yt-tui in a floating terminal" })

vim.api.nvim_create_user_command("YtTuiToggle", function()
  require("yt-tui").toggle()
end, { desc = "Hide or resume the yt-tui terminal" })

vim.api.nvim_create_user_command("YtTuiHide", function()
  require("yt-tui").hide()
end, { desc = "Hide yt-tui while keeping its process running" })

vim.api.nvim_create_user_command("YtTuiRestart", function(opts)
  require("yt-tui").restart(opts.fargs, { force = opts.bang })
end, { nargs = "*", bang = true, desc = "Start a fresh yt-tui session (asks before discarding work)" })

vim.api.nvim_create_user_command("YtTuiClose", function()
  require("yt-tui").close()
end, { desc = "Close the yt-tui terminal and stop its process" })
