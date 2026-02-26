# Neovim Configuration

Personal Neovim configuration built on [AstroNvim v5](https://astronvim.com/) with language packs for Python/Django, Vue 3/Nuxt, Tailwind CSS, and more.

## What's Included

**Language support** (via [AstroCommunity](https://github.com/AstroNvim/astrocommunity) packs):

- **Python** — basedpyright (type checking set to `basic`) + ruff (linting/formatting)
- **Vue 3 / Nuxt** — Volar LSP + vtsls for TypeScript
- **Tailwind CSS** — intellisense, completions, color preview; class regex support for `clsx`/`cn`/`cva` utilities
- **Prettier + ESLint** — frontend formatting and linting
- **Lua** — for editing Neovim configs
- **Docker, YAML, TOML, Bash, Markdown**

**Editor settings** (`lua/plugins/astrocore.lua`):

- Relative line numbers, sign column always visible
- `exrc` enabled (project-local `.nvim.lua` files)
- Format on save (2s timeout), with `lua_ls` formatting disabled in favor of StyLua
- Virtual text diagnostics

**Custom keymaps** (leader = `Space`):

| Key | Description |
|-----|-------------|
| `<Leader>kp` | Copy project-relative file path to clipboard |
| `<Leader>Kp` | Copy absolute file path to clipboard |
| `lg` | Open LazyGit |
| `<Leader>bd` | Pick and close a buffer from the tabline |
| `]b` / `[b` | Next / previous buffer |

**Other customizations**:

- ASCII "ASTRO NVIM" dashboard header
- LuaSnip: JavaScript snippets extended to JSX files
- StyLua formatting: 120 col width, 2-space indent, Unix line endings

## Prerequisites

- **Neovim >= 0.10** (stable release)
- **Git**
- A [Nerd Font](https://www.nerdfonts.com/) installed and configured in your terminal
- A terminal with true color support

**Recommended** (optional but expected by some features):

| Tool | Purpose |
|------|---------|
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Live grep / file search |
| [lazygit](https://github.com/jesseduffield/lazygit) | Git UI (mapped to `lg`) |
| A system clipboard tool | `pbcopy`/`xclip`/`wl-copy` for path-copy keymaps |
| Node.js | Required by many LSP servers |
| Python 3 | Required by debugpy and Python LSPs |

## Installation

### 1. Back up any existing config

```bash
mv ~/.config/nvim ~/.config/nvim.bak
mv ~/.local/share/nvim ~/.local/share/nvim.bak
mv ~/.local/state/nvim ~/.local/state/nvim.bak
mv ~/.cache/nvim ~/.cache/nvim.bak
```

### 2. Clone this repository

```bash
git clone https://github.com/ozzyfromspace/nvim.git ~/.config/nvim
```

### 3. Launch Neovim

```bash
nvim
```

On first launch, [Lazy.nvim](https://github.com/folke/lazy.nvim) will automatically:

1. Bootstrap itself
2. Install all plugins
3. Install LSP servers, formatters, and linters via Mason

This may take a minute. Let it finish, then restart Neovim.

### 4. Verify the setup

Inside Neovim, run:

- `:checkhealth` — verify dependencies and plugin health
- `:LspInfo` — confirm language servers are attached
- `:Mason` — review installed tools

## Updating

- `:Lazy update` — update all plugins (run twice if using pinned AstroNvim versions)
- `:AstroUpdate` — update plugins and Mason packages together
- `:AstroVersion` — check the current AstroNvim version

## Project Structure

```
.
├── init.lua                  # Entry point: bootstraps Lazy.nvim
├── lua/
│   ├── lazy_setup.lua        # Lazy.nvim plugin spec and config
│   ├── community.lua         # AstroCommunity language packs
│   ├── polish.lua            # Post-setup customizations (currently inactive)
│   └── plugins/
│       ├── astrocore.lua     # Core options, keymaps, features
│       ├── astrolsp.lua      # LSP configuration and formatting rules
│       ├── astroui.lua       # UI / colorscheme settings
│       ├── mason.lua         # Extra Mason tool installations
│       ├── treesitter.lua    # Extra Treesitter parsers
│       ├── user.lua          # Dashboard header, LuaSnip extensions
│       └── none-ls.lua       # None-ls sources (currently inactive)
├── .stylua.toml              # StyLua formatter config
├── selene.toml               # Selene linter config
├── neovim.yml                # Selene Neovim globals definition
├── .luarc.json               # lua-language-server: disable built-in formatting
├── .neoconf.json             # Neoconf: LSP plugin settings
└── .gitignore
```

## License

This configuration is provided as-is for personal use. Feel free to fork and adapt it.
