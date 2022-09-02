--Bindings
lvim.leader = "space"
lvim.keys.normal_mode["<C-s>"] = ":w<cr>"
lvim.keys.normal_mode["<leader>r"] = ":NvimTreeRefresh<cr>"
lvim.keys.visual_mode["p"] = '"_dP'
lvim.keys.normal_mode["fa"] = require("harpoon.mark").add_file
lvim.keys.normal_mode["fb"] = require("harpoon.ui").toggle_quick_menu
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

--Plugins
lvim.plugins = {
  {
    "folke/trouble.nvim",
    cmd = "TroubleToggle",
  },
  { 'edluffy/hologram.nvim' },
  { "sainnhe/gruvbox-material" },
  { "easymotion/vim-easymotion" },
  { "mg979/vim-visual-multi" },
  { "wakatime/vim-wakatime" },
  { "mattn/emmet-vim" },
  { "p00f/nvim-ts-rainbow" },
  { "ThePrimeagen/harpoon" }
}

--Preferences
lvim.log.level = "warn"
lvim.format_on_save = false
lvim.colorscheme = "gruvbox-material"

lvim.builtin.alpha.active = true
lvim.builtin.alpha.mode = "dashboard"
lvim.builtin.notify.active = true
lvim.builtin.terminal.active = true
lvim.builtin.nvimtree.setup.view.side = "right"

--Treesitter
lvim.builtin.treesitter.ensure_installed = {
  "bash",
  "c",
  "javascript",
  "clojure",
  "json",
  "lua",
  "python",
  "typescript",
  "haskell",
  "elm",
  "tsx",
  "css",
  "rust",
  "java",
  "yaml",
}

lvim.builtin.treesitter.rainbow = {
  enable = true,
  extended_mode = true,
  max_file_lines = nil,
}

lvim.builtin.treesitter.highlight.enabled = true
