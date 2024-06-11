return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      hls = {
        mason = false,
      },
      gleam = {
        mason = false,
      },
      emmet_language_server = {
        filetypes = {
          "css",
          "eruby",
          "html",
          "heex",
          "javascript",
          "javascriptreact",
          "less",
          "sass",
          "scss",
          "svelte",
          "pug",
          "typescriptreact",
          "vue",
        },
      },
      unison = {
        mason = false,
        setup = {
          on_attach = function(_, bufnr)
            -- Always show the signcolumn, otherwise it would shift the text each time
            -- diagnostics appear/become resolved
            vim.o.signcolumn = "yes"

            -- Update the cursor hover location every 1/4 of a second
            vim.o.updatetime = 250

            -- Disable appending of the error text at the offending line
            vim.diagnostic.config({ virtual_text = false })

            -- Enable a floating window containing the error text when hovering over an error
            vim.api.nvim_create_autocmd("CursorHold", {
              buffer = bufnr,
              callback = function()
                local opts = {
                  focusable = false,
                  close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
                  border = "rounded",
                  source = "always",
                  prefix = " ",
                  scope = "cursor",
                }
                vim.diagnostic.open_float(nil, opts)
              end,
            })

            -- This setting is to display hover information about the symbol under the cursor
            vim.keymap.set("n", "K", vim.lsp.buf.hover)
          end,
        },
      },
    },
  },
}
