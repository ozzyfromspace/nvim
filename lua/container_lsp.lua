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

-- --- Convention-based auto-discovery --------------------------------
--
-- Most containerized projects follow a simple shape:
--
--   - ``docker-compose.yml`` at the project root.
--   - Top-level subdirectories are services (``frontend/``,
--     ``backend/``, ``worker/``, …). The directory name IS the
--     compose service name.
--   - Each service dir contains a toolchain marker:
--     ``package.json`` → Node-based service; ``pyproject.toml`` /
--     ``requirements.txt`` / ``setup.py`` → Python-based service.
--   - Compose's default container naming applies:
--     ``${project_basename}-${service}-1``.
--
-- Given those assumptions, we can wire the right LSP-to-container
-- mappings without any project-local Lua. Call ``auto_discover()``
-- once from the global config; any project following the convention
-- Just Works. Projects that violate the convention drop a ``.nvim.lua``
-- with explicit ``setup({...})`` calls — same escape hatch as before.

-- Toolchain templates: marker files that identify a stack, and the
-- LSP servers (plus their per-container cmd) to route if the stack
-- is present in a service dir.
local TOOLCHAIN_TEMPLATES = {
  {
    name = "node",
    markers = { "package.json" },
    servers = {
      vtsls = { "npx", "vtsls", "--stdio" },
      volar = { "npx", "vue-language-server", "--stdio" },
      vue_ls = { "npx", "vue-language-server", "--stdio" },
      tailwindcss = { "npx", "tailwindcss-language-server", "--stdio" },
      eslint = { "npx", "vscode-eslint-language-server", "--stdio" },
    },
  },
  {
    name = "python",
    markers = { "pyproject.toml", "requirements.txt", "setup.py" },
    servers = {
      basedpyright = { "basedpyright-langserver", "--stdio" },
      ruff = { "ruff", "server", "--preview" },
    },
  },
}

local COMPOSE_FILENAMES = {
  "docker-compose.yml",
  "docker-compose.yaml",
  "docker-compose.override.yml",
  "compose.yml",
  "compose.yaml",
}

local function has_file(dir, name)
  return vim.uv.fs_stat(dir .. "/" .. name) ~= nil
end

local function find_project_root(start)
  local dir = start or vim.fn.getcwd()
  while dir ~= "" and dir ~= "/" do
    for _, name in ipairs(COMPOSE_FILENAMES) do
      if has_file(dir, name) then return dir end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then break end
    dir = parent
  end
  return nil
end

local function match_toolchain(service_dir)
  for _, template in ipairs(TOOLCHAIN_TEMPLATES) do
    for _, marker in ipairs(template.markers) do
      if has_file(service_dir, marker) then return template end
    end
  end
  return nil
end

--- Walk up from the starting directory (or ``cwd`` by default)
--- looking for a compose file, then scan its subdirs for toolchain
--- markers and route the matching LSPs to the corresponding
--- containers. Fully idempotent — subsequent explicit
--- ``setup()``/``route()`` calls overwrite the discovered entries if
--- the user needs a different cmd or container for a particular
--- server.
---
--- Options:
---   - ``root`` (string, optional): start the walk here instead of cwd.
---   - ``project_name`` (string, optional): use this for the compose
---     project prefix. Defaults to the basename of the directory
---     containing the compose file.
function M.auto_discover(opts)
  opts = opts or {}
  local root = opts.root or find_project_root()
  if not root then return end

  local project_name = opts.project_name or vim.fn.fnamemodify(root, ":t")

  for _, entry in ipairs(vim.fn.readdir(root)) do
    if entry:sub(1, 1) ~= "." and entry:sub(1, 1) ~= "_" then
      local service_dir = root .. "/" .. entry
      if vim.fn.isdirectory(service_dir) == 1 then
        local toolchain = match_toolchain(service_dir)
        if toolchain then
          local container = project_name .. "-" .. entry .. "-1"
          for server_name, cmd in pairs(toolchain.servers) do
            M.route(server_name, container, (table.unpack or unpack)(cmd))
          end
        end
      end
    end
  end
end

return M
