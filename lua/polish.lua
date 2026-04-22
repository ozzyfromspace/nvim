-- Runs last in the init sequence. Good place for things that don't
-- fit the plugin-spec shape AstroNvim uses for its configs.

-- Route LSP servers through Docker containers automatically for any
-- project that follows the convention (docker-compose.yml at root,
-- services as top-level subdirs named after compose services, each
-- with a toolchain marker like package.json / pyproject.toml).
--
-- Projects that violate the convention drop a .nvim.lua with
-- explicit ``require("container_lsp").setup({...})`` mappings —
-- exrc loads it after this runs and additional routes merge in.
require("container_lsp").auto_discover()
