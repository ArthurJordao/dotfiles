-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local set = vim.keymap.set

set("n", "k", "kzz")
set("n", "j", "jzz")
set("n", "<leader>cs", function()
  require("telescope.builtin").lsp_document_symbols()
end, { desc = "Open document symbols" })
set("n", "<leader>h", ":noh<CR>", { desc = "Clear highlights" })
