-- AstroCommunity: import any community modules here
-- We import this file in `lazy_setup.lua` before the `plugins/` folder.
-- This guarantees that the specs are processed before any user plugins.

---@type LazySpec
return {
  "AstroNvim/astrocommunity",

  ---- Language Packs ----

  -- Lua (for Neovim config editing)
  { import = "astrocommunity.pack.lua" },

  -- Python / Django (basedpyright LSP + ruff for linting/formatting)
  { import = "astrocommunity.pack.python.base" },
  { import = "astrocommunity.pack.python.basedpyright" },
  { import = "astrocommunity.pack.python.ruff" },

  -- Vue 3 / Nuxt (Volar LSP, auto-imports typescript pack with vtsls)
  { import = "astrocommunity.pack.vue" },

  -- Tailwind CSS (intellisense, completions, color preview; auto-imports html-css pack)
  { import = "astrocommunity.pack.tailwindcss" },

  -- Formatting & Linting
  { import = "astrocommunity.pack.prettier" },
  { import = "astrocommunity.pack.eslint" },

  ---- Supporting Language Packs ----
  { import = "astrocommunity.pack.docker" },
  { import = "astrocommunity.pack.yaml" },
  { import = "astrocommunity.pack.toml" },
  { import = "astrocommunity.pack.bash" },
  { import = "astrocommunity.pack.markdown" },
}
