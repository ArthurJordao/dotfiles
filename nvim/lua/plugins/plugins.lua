return {
  {
    "echasnovski/mini.pairs",
    event = "VeryLazy",
    opts = {
      modes = { insert = true, command = true, terminal = false },
      -- skip autopair when next character is one of these
      skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
      -- skip autopair when the cursor is inside these treesitter nodes
      skip_ts = { "string" },
      -- skip autopair when next character is closing pair
      -- and there are more closing pairs than opening pairs
      skip_unbalanced = false,
      -- better deal with markdown code blocks
      markdown = true,
    },
    config = function(_, opts)
      LazyVim.mini.pairs(opts)
    end,
  },
  {
    "zbirenbaum/copilot.lua",
    opts = {
      copilot_node_command = "/opt/homebrew/bin/node",
    },
  },
  {
    "zk-org/zk-nvim",
    config = function()
      require("zk").setup({
        picker = "fzf_lua",
        lsp = {
          -- `config` is passed to `vim.lsp.start_client(config)`
          config = {
            cmd = { "zk", "lsp" },
            name = "zk",
            -- on_attach = ...
            -- etc, see `:h vim.lsp.start_client()`
            auto_attach = {
              enabled = true,
              filetypes = { "markdown" },
            },
          },
        },
      })
    end,
  },
}
