return {
  "dzfrias/arena.nvim",
  event = "BufWinEnter",
  -- Calls `.setup()` automatically
  config = true,
  keys = {
    {
      "<leader>fa",
      function()
        require("arena").toggle()
      end,
      mode = { "n", "v" },
      desc = "Toggle arena",
    },
  },
}
