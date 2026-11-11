return {
  {
    dir = vim.fn.expand("~/Developer/yt-tui.nvim"),
    name = "yt-tui.nvim",
    main = "yt-tui",
    cmd = { "YtTui", "YtTuiClose" },
    keys = {
      { "<leader>yy", "<cmd>YtTui<cr>", desc = "Open YouTrack" },
    },
    opts = {},
  },
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>y", group = "youtrack" })
    end,
  },
}
