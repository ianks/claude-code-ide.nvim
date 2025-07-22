# claude-code-ide.nvim

Dead simple Claude Code integration for Neovim. Just a terminal that works.

## Installation

### Basic installation

```lua
{
  "ianks/claude-code-ide.nvim",
  dependencies = { 
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim"
  },
  config = function()
    require("claude-code-ide").setup()
  end,
}
```

### With optional SHA1 dependency (recommended)

For better WebSocket performance, you can add the SHA1 luarocks package:

```lua
{
  "ianks/claude-code-ide.nvim",
  dependencies = { 
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim",
    {
      "vhyrro/luarocks.nvim",
      priority = 1000,
      opts = {
        rocks = { "sha1" }
      }
    }
  },
  config = function()
    require("claude-code-ide").setup()
  end,
}
```

## Usage

Press `<leader>ct` to toggle Claude terminal.

That's it.

## What it does

1. Starts an MCP server in Neovim
1. Opens a terminal with `claude code` on the right
1. Claude connects to your Neovim automatically

## Configuration

```lua
require("claude-code-ide").setup({
  port = 0,  -- 0 = random port
  host = "127.0.0.1",
})
```

## License

MIT
