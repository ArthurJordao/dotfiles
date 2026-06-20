return {
  {
    "zk-org/zk-nvim",
    dependencies = {
      "folke/which-key.nvim",
    },
    config = function()
      require("zk").setup({
        picker = "minipick",
        lsp = {
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
              vim.keymap.set("i", "<c-r>", function()
                vim.cmd("norm! i")
                cmd.get("ZkInsertLink")()
              end)
            end,
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

