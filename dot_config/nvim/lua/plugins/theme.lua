return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    config = function()
      require("rose-pine").setup({
        variant = "dawn",
        dark_variant = "dawn",
      })
    end,
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
  {
    "folke/tokyonight.nvim",
    lazy = true,
    opts = { style = "day" },
  },
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "latte"
    }
  },
}
