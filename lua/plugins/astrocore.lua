-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 },
      autopairs = true,
      cmp = true,
      diagnostics = { virtual_text = true, virtual_lines = false },
      highlighturl = true,
      notifications = true,
    },
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    options = {
      opt = {
        exrc = true,
        relativenumber = true,
        number = true,
        spell = false,
        signcolumn = "yes",
        wrap = false,
      },
    },
    mappings = {
      n = {
        -- navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- copy project-relative file path to clipboard
        ["<Leader>kp"] = {
          function()
            local abs = vim.fn.expand "%:p"
            local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(vim.fn.expand "%:p:h") .. " rev-parse --show-toplevel")[1]
            local path = (vim.v.shell_error == 0 and git_root) and abs:sub(#git_root + 2) or vim.fn.expand "%:."
            vim.fn.setreg("+", path)
            vim.notify(path, vim.log.levels.INFO, { title = "Path copied (relative)" })
          end,
          desc = "Copy relative file path to clipboard",
        },

        -- copy absolute file path to clipboard
        ["<Leader>Kp"] = {
          function()
            local path = vim.fn.expand "%:p"
            vim.fn.setreg("+", path)
            vim.notify(path, vim.log.levels.INFO, { title = "Path copied (absolute)" })
          end,
          desc = "Copy absolute file path to clipboard",
        },

        -- lazygit
        ["lg"] = { function() Snacks.lazygit() end, desc = "LazyGit" },

        -- close buffer from tabline
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },
      },
    },
  },
}
