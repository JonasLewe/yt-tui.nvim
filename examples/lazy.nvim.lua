return {
  {
    "JonasLewe/yt-tui.nvim",
    name = "yt-tui.nvim",
    main = "yt-tui",
    cmd = { "YtTui", "YtTuiToggle", "YtTuiHide", "YtTuiRestart", "YtTuiClose" },
    keys = {
      { "<leader>yt", "<cmd>YtTuiRestart<cr>", desc = "Start YouTrack fresh" },
      { "<leader>yy", "<cmd>YtTuiToggle<cr>", desc = "Toggle YouTrack" },
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
