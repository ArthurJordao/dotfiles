return {
  "rose-pine/neovim",
  name = "rose-pine",
  config = function()
    require("rose-pine").setup({
      variant = "dawn",
      dark_variant = "dawn",
    })
  end,
  priority = 1000,
}
