return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      hls = {
        mason = false,
      },
     emmet_language_server = {
        filetypes = {"css", "eruby", "html", "heex", "javascript", "javascriptreact", "less", "sass", "scss", "svelte", "pug", "typescriptreact", "vue"}

      }
    },
  },
}
