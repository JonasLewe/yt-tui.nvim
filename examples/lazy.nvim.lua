return {
  {
    dir = vim.fn.expand("~/Developer/yt-tui.nvim"),
    name = "yt-tui.nvim",
    main = "yt-tui",
    cmd = { "YtTui", "YtTuiToggle", "YtTuiHide", "YtTuiRestart", "YtTuiClose" },
    keys = {
      { "<leader>yt", "<cmd>YtTuiToggle<cr>", desc = "Toggle YouTrack" },
      { "<leader>yR", "<cmd>YtTuiRestart<cr>", desc = "Restart YouTrack" },
    },
    opts = { hide_key = "<C-w>q" },
  },
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>y", group = "youtrack" })
    end,
  },
}
