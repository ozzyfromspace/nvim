-- Git integration: inline blame + fugitive + diffview.
--
-- gitsigns is AstroNvim's default gutter-sign plugin; we just flip
-- `current_line_blame` on so the current line gets virtual text like
-- "Alice, 2 weeks ago · Fix layout" at the EOL. fugitive and diffview
-- add heavier commands (`:Git blame`, `:DiffviewOpen`) without any
-- keymaps — invoke via `:` cmdline; add keymaps later if they stick.

---@type LazySpec
return {
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      current_line_blame = true,
      current_line_blame_opts = {
        delay = 300,
        virt_text_pos = "eol",
        ignore_whitespace = false,
      },
      current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> · <summary>",
    },
  },

  -- `:Git blame` (full side pane), `:Gdiff`, `:Gread`, `:Gwrite`, etc.
  -- Pairs well with gitsigns — gitsigns for at-a-glance, fugitive for
  -- drilling into commits and staging hunks across larger scopes.
  {
    "tpope/vim-fugitive",
    cmd = { "Git", "G", "Gdiff", "Gdiffsplit", "Gvdiffsplit", "Gwrite", "Gread", "GMove", "GDelete", "GBrowse" },
    event = "VeryLazy",
  },

  -- Side-by-side diff UI for a file, a commit, or branch↔branch.
  -- `:DiffviewOpen main` compares HEAD to main; `:DiffviewFileHistory %`
  -- walks the history of the current file.
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
  },
}
