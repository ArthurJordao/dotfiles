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
    "JulianNymark/zk-nvim",
    branch = "add-some-guards",
    dependencies = {
      "folke/which-key.nvim",
    },
    config = function()
      require("zk").setup({
        picker = "fzf_lua",
        lsp = {
          -- `config` is passed to `vim.lsp.start_client(config)`
          config = {
            cmd = { "zk", "lsp" },
            name = "zk",
            on_attach = function()
              local cmd = require("zk.commands")

              local wk = require("which-key")
              wk.add({
                mode = { "n", "v" },
                { "<leader>z", group = "Zk" },
              })

              --visual mode
              vim.keymap.set(
                "n",
                "<leader>zn",
                ":ZkNew {title = vim.fn.input('Title: '), dir = vim.fn.input('Dir: ')}<cr>",
                { desc = "New note" }
              )
              vim.keymap.set("n", "<leader>zt", ":ZkTags<cr>", { desc = "All tags" })
              vim.keymap.set("n", "<leader>zf", ":ZkNotes {excludeHrefs = {'journal'}}<cr>", { desc = "List notes" })
              vim.keymap.set("n", "<leader>zo", ":ZkLinks<cr>", { desc = "List links" })
              vim.keymap.set("n", "<leader>zs", ":ZkBuffers<cr>", { desc = "List buffers" })
              vim.keymap.set("n", "<leader>zi", ":ZkBacklinks<cr>", { desc = "List backlinks" })

              -- visual mode
              vim.keymap.set("v", "<leader>zm", ":ZkMatch<cr>", { desc = "Match selection content" })
              vim.keymap.set(
                "v",
                "<leader>zn",
                ":ZkNewFromTitleSelection {dir = vim.fn.input('Dir: ')}<cr>",
                { desc = "New note from title" }
              )
              vim.keymap.set("v", "<leader>zl", ":ZkInsertLinkAtSelection<cr>", { desc = "Insert link at selection" })
              vim.keymap.set(
                "v",
                "<leader>ze",
                ":ZkNewFromContentSelection {title = vim.fn.input('Title: '), dir = vim.fn.input('Dir: ')}<cr>",
                { desc = "New note from content" }
              )

              -- insert mode
              vim.keymap.set("i", "<c-r>", function()
                vim.cmd("norm! i") -- otherwise link gets inserted after cursor
                cmd.get("ZkInsertLink")()
              end)
            end,
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
