-- Customize Treesitter
-- Most parsers are installed automatically by community packs.
-- Add any extras here that aren't covered by the packs.

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "lua",
      "vim",
      "vimdoc",
      "query",
      "regex",
      "markdown",
      "markdown_inline",
    },
  },
}
