lvim.log.level = "warn"
lvim.format_on_save = false
lvim.colorscheme = "gruvbox-material"
lvim.leader = "space"
lvim.keys.normal_mode["<C-s>"] = ":w<cr>"
lvim.keys.normal_mode["<leader>r"] = ":NvimTreeRefresh<cr>"
lvim.keys.visual_mode["p"] = '"_dP'
lvim.keys.normal_mode["k"] = "kzz"
lvim.keys.normal_mode["j"] = "jzz"
lvim.builtin.which_key.mappings["P"] = { "<cmd>Telescope projects<CR>", "Projects" }
lvim.builtin.which_key.mappings["t"] = {
  name = "+Trouble",
  r = { "<cmd>Trouble lsp_references<cr>", "References" },
  f = { "<cmd>Trouble lsp_definitions<cr>", "Definitions" },
  d = { "<cmd>Trouble document_diagnostics<cr>", "Diagnostics" },
  q = { "<cmd>Trouble quickfix<cr>", "QuickFix" },
  l = { "<cmd>Trouble loclist<cr>", "LocationList" },
  w = { "<cmd>Trouble workspace_diagnostics<cr>", "Wordspace Diagnostics" },
}
lvim.builtin.alpha.active = true
lvim.builtin.alpha.mode = "dashboard"
lvim.builtin.terminal.active = true
lvim.builtin.nvimtree.setup.view.side = "left"
lvim.builtin.nvimtree.setup.renderer.icons.show.git = false

vim.cmd [[
  augroup numbertoggle
    autocmd!
    autocmd BufEnter,FocusGained,InsertLeave,WinEnter * if &nu && mode() != "i" | set rnu   | endif
    autocmd BufLeave,FocusLost,InsertEnter,WinLeave   * if &nu                  | set nornu | endif
  augroup END
]]
lvim.builtin.treesitter.ensure_installed = {
  "bash",
  "c",
  "javascript",
  "json",
  "lua",
  "python",
  "typescript",
  "tsx",
  "css",
  "rust",
  "java",
  "yaml",
  "haskell",
  "elm",
}

lvim.builtin.treesitter.highlight.enable = true

lvim.lsp.installer.setup.ensure_installed = {
    "sumneko_lua",
    "jsonls",
}

lvim.plugins = {
    {
      "folke/trouble.nvim",
      cmd = "TroubleToggle",
    },
  { "sainnhe/gruvbox-material" },
  { "wakatime/vim-wakatime" },
  { "p00f/nvim-ts-rainbow" },
  { "machakann/vim-sandwich" },
  { "nvim-treesitter/nvim-treesitter-context" },
}

lvim.builtin.treesitter.rainbow = {
  enable = true,
  extended_mode = true,
  max_file_lines = nil,
}
