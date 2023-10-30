return {
  {
    "tamton-aquib/duck.nvim",
    keys = {
      {
        "<leader>dd",
        function()
          require("duck").hatch('🐤')
        end,
        desc = "Duck hatch",
        mode = "n",
        silent = true,
      },
      {
        "<leader>dk",
        function()
          require("duck").cook()
        end,
        desc = "Duck cook",
        mode = "n",
        silent = true,
      },
    },
  },
}
