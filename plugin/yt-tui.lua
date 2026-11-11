if vim.g.loaded_yt_tui then
  return
end
vim.g.loaded_yt_tui = true

vim.api.nvim_create_user_command("YtTui", function(opts)
  require("yt-tui").open(opts.fargs)
end, { nargs = "*", desc = "Open yt-tui in a floating terminal" })

vim.api.nvim_create_user_command("YtTuiClose", function()
  require("yt-tui").close()
end, { desc = "Close the yt-tui terminal and stop its process" })
