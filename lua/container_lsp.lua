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

-- Toolchain templates: marker files that identify a stack, the
-- LSP servers (plus their per-container cmd) to route if the stack
-- is present, the filetypes each stack owns, and the command prefix
-- for invoking PROJECT-CUSTOM LSPs (bin/lsp-*) in the stack's
-- preferred interpreter. ``python_cmd`` lets us reach straight for
-- the project's .venv/bin/python3 so we skip uv's bytecode-
-- recompile overhead on every LSP start.
local TOOLCHAIN_TEMPLATES = {
  {
    name = "node",
    markers = { "package.json" },
    filetypes = { "javascript", "typescript", "vue", "javascriptreact", "typescriptreact" },
    custom_cmd = { "node" },
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
    filetypes = { "python" },
    -- Reach for the uv-managed venv directly. uv places it at
    -- `<service>/.venv/` when you run `uv sync`. Falling back to a
    -- plain ``python3`` on the container PATH keeps non-uv projects
    -- working; see ``resolve_custom_cmd`` below.
    custom_cmd = { ".venv/bin/python3" },
    custom_cmd_fallback = { "python3" },
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

-- Resolve the interpreter prefix for project-custom LSPs. The first
-- ``custom_cmd`` entry may be a relative path into the service dir
-- (e.g. ``.venv/bin/python3``); if that file exists we use it,
-- otherwise we fall back to ``custom_cmd_fallback``. This lets uv-
-- and non-uv-managed Python projects share the same template.
local function resolve_custom_cmd(template, service_dir)
  if template.custom_cmd and #template.custom_cmd > 0 then
    local first = template.custom_cmd[1]
    -- Relative path to something in the service dir → probe it.
    if first and not first:match("^/") and first:match("/") then
      if has_file(service_dir, first) then
        return template.custom_cmd
      end
      return template.custom_cmd_fallback or template.custom_cmd
    end
    return template.custom_cmd
  end
  return { "sh", "-c" }
end

-- Scan ``<service_dir>/bin/`` for executable files matching
-- ``lsp-<name>`` and register each as a project-custom LSP. Server
-- naming: ``custom_<project>_<service>_<name>`` to avoid collisions
-- across projects sharing nvim session state. Filetypes are
-- inherited from the enclosing service's toolchain template. The
-- actual cmd is routed through the container_lsp wrapper (installed
-- on first ``route`` call) so these LSPs run inside the service's
-- container just like the standard ones.
local function register_custom_lsps(project_name, service_name, service_dir, container, template)
  local bin_dir = service_dir .. "/bin"
  if vim.fn.isdirectory(bin_dir) ~= 1 then return end

  local interp = resolve_custom_cmd(template, service_dir)
  local safe_project = project_name:gsub("[^%w]", "_")
  local safe_service = service_name:gsub("[^%w]", "_")

  for _, entry in ipairs(vim.fn.readdir(bin_dir)) do
    local rule = entry:match("^lsp%-(.+)$")
    if rule and vim.fn.executable(bin_dir .. "/" .. entry) == 1 then
      local safe_rule = rule:gsub("[^%w]", "_")
      local server_name = "custom_" .. safe_project .. "_" .. safe_service .. "_" .. safe_rule

      -- Route via the docker wrapper. The cmd that lands in
      -- ``overrides`` is: docker exec -i <container> <interp>
      -- <script>. Path is relative to the container's working_dir,
      -- which Compose-convention projects set to the service dir
      -- (e.g. ``/.../backend``) — so we just say ``bin/<entry>``,
      -- not ``<service>/bin/<entry>``.
      local cmd = vim.list_extend({}, interp)
      table.insert(cmd, "bin/" .. entry)
      M.route(server_name, container, (table.unpack or unpack)(cmd))

      -- Register the server config with Neovim's native lsp API.
      -- ``cmd`` here is a never-runs placeholder — the vim.lsp.start
      -- wrapper (installed above by ``M.route``) replaces it with
      -- the docker-routed cmd before spawn, so whatever we put here
      -- never actually gets exec'd. Uses 0.11+ API: vim.lsp.config
      -- + vim.lsp.enable.
      if vim.lsp.config and vim.lsp.enable then
        vim.lsp.config(server_name, {
          cmd = { "container-lsp-placeholder" },
          filetypes = template.filetypes,
          root_markers = { "pyproject.toml", "package.json", "docker-compose.yml" },
        })
        vim.lsp.enable(server_name)
      end
    end
  end
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
          -- Project-custom LSPs: any ``<service>/bin/lsp-<name>``
          -- executable becomes an auto-registered LSP named
          -- ``custom_<project>_<service>_<name>``. Filetypes inherited
          -- from the toolchain template; cmd routed through docker.
          register_custom_lsps(project_name, entry, service_dir, container, toolchain)
        end
      end
    end
  end
end

return M
