return {
  "neovim/nvim-lspconfig",
  init = function()
    local keys = require("lazyvim.plugins.lsp.keymaps").get()
    keys[#keys + 1] = {
      "<leader>cs",
      function()
        require("telescope.builtin").lsp_document_symbols()
      end,
      desc = "Open document symbols",
      mode = "n",
    }
  end,
  opts = {
    autoformat = false,
    servers = {
      hls = {
        mason = false,
      },
    },
  },
}
