return {
  "echasnovski/mini.nvim",
  config = function()
    local hipatterns = require("mini.hipatterns")
    hipatterns.setup({
      highlighters = {
        -- Highlight hex color strings (`#rrggbb`) using that color
        hex_color = hipatterns.gen_highlighter.hex_color(),
      },
    })
  end,
}
