-- Container-routed LSP helper.
--
-- Reusable machinery to run LSP servers INSIDE a Docker container and
-- talk to them over stdio from host-side Neovim. The host stays clean
-- (no per-project Node / Python / etc. installs); language servers run
-- where the real `node_modules` + venv + toolchains live.
--
-- Per-project setup lives in that project's `.nvim.lua` and looks like:
--
--     require("container_lsp").setup({
--       basedpyright = { "myproj-backend-1", "basedpyright-langserver", "--stdio" },
--       vtsls        = { "myproj-frontend-1", "npx", "vtsls", "--stdio" },
--       -- ...
--     })
--
-- The first entry is the container name; the rest is the command to
-- exec inside it. Path mirroring between host + container (working_dir
-- + bind mount on the same absolute path) is a prerequisite — that's
-- what makes go-to-definition + diagnostics match byte-for-byte across
-- the filesystem boundary.
--
-- Requires: Neovim >= 0.11, `vim.o.exrc = true`.

local M = {}

-- server_name → { "docker", "exec", "-i", container, ...cmd }
local overrides = {}
local installed = false

local function docker_cmd(container, ...)
  return vim.list_extend({ "docker", "exec", "-i", container }, { ... })
end

-- Install the vim.lsp.start wrapper + notify filters exactly once.
-- Idempotent — safe to call from multiple project configs that all
-- ``require("container_lsp")`` on startup. Subsequent ``.route`` /
-- ``.setup`` calls just add more entries to the shared override map.
local function install_wrapper()
  if installed then return end
  installed = true

  -- Filter harmless ENOENT file-watcher warnings from container LSPs —
  -- containers can't always watch the host's filesystem the same way
  -- host-native processes can, and the noise drowns out real errors.
  local _notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, ...)
    if type(msg) == "string" and msg:find("watch") and msg:find("ENOENT") then
      return
    end
    return _notify(msg, ...)
  end

  -- Wrap vim.lsp.start to intercept every LSP launch and rewrite
  -- `cmd` for declared servers. Catches all code paths: lspconfig,
  -- native vim.lsp.enable, mason-lspconfig, astrolsp, etc.
  local _lsp_start = vim.lsp.start
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.start = function(config, opts)
    if config and config.name then
      local override = overrides[config.name]
      if override then
        config.cmd = override
        -- Null processId so the container LSP doesn't try to monitor
        -- a host PID that doesn't exist inside the container.
        local orig_before_init = config.before_init
        config.before_init = function(params, conf)
          params.processId = vim.NIL
          if orig_before_init then
            return orig_before_init(params, conf)
          end
        end
        -- Filter ENOENT showMessage noise from container LSPs.
        config.handlers = vim.tbl_deep_extend("force", config.handlers or {}, {
          ["window/showMessage"] = function(err, result, ctx, conf)
            if result and result.message and result.message:find("ENOENT") then
              return
            end
            return vim.lsp.handlers["window/showMessage"](err, result, ctx, conf)
          end,
        })
      end
    end
    return _lsp_start(config, opts)
  end
end

--- Declare that LSP `server_name` should run inside `container` via
--- the given command. Installs the wrapper on first call.
---
---     require("container_lsp").route("vtsls", "frontend-1", "npx", "vtsls", "--stdio")
function M.route(server_name, container, ...)
  overrides[server_name] = docker_cmd(container, ...)
  install_wrapper()
end

--- Declare multiple routes at once. Accepts a table keyed by server
--- name; each value is a list whose first element is the container
--- and whose remainder is the command.
---
---     require("container_lsp").setup({
---       basedpyright = { "backend-1", "basedpyright-langserver", "--stdio" },
---       vtsls        = { "frontend-1", "npx", "vtsls", "--stdio" },
---     })
function M.setup(routes)
  for server_name, spec in pairs(routes) do
    -- Lua 5.1 / LuaJIT compat: unpack() is global; Lua 5.2+ moved it
    -- to table.unpack(). Neovim's embedded LuaJIT exposes both.
    local container = spec[1]
    local cmd = {}
    for i = 2, #spec do cmd[#cmd + 1] = spec[i] end
    M.route(server_name, container, (table.unpack or unpack)(cmd))
  end
end

return M
