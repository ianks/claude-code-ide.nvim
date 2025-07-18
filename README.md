# claude-code-ide.nvim

Native Claude Code integration for Neovim via the Model Context Protocol (MCP).

> 🚧 **Under Active Development** - Core functionality is working. API may change.

## Overview

claude-code-ide.nvim provides a WebSocket MCP server that runs inside Neovim, allowing Claude Code to interact with your editor as if it were a built-in IDE. Claude can open files, view diagnostics, create diffs, and help you write code without leaving your workflow.

## Features

- **Zero-friction setup** - Server auto-starts by default
- **IDE Tools** - Claude can open files, create diffs, view diagnostics, and more
- **Smart text objects** - Send functions, classes, or selections to Claude naturally
- **Non-blocking UI** - Diff previews and conversations don't interrupt your flow
- **Session persistence** - Conversations auto-save and restore
- **Rich notifications** - Actionable error messages with recovery hints

## Installation

```lua
-- lazy.nvim
{
  "ianks/claude-code-ide.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("claude-code-ide").setup()
  end,
}
```

## Quick Start

1. **Connect Claude** (server starts automatically):
   ```lua
   vim.cmd("ClaudeCodeConnect")
   -- or press <leader>co
   ```

That's it! The server auto-starts and Claude will connect to your Neovim instance.

## Configuration Examples

### Minimal (Recommended)

```lua
require("claude-code-ide").setup()
-- That's it! Sensible defaults handle everything
```

### Custom Keymaps

```lua
require("claude-code-ide").setup({
  keymaps = {
    prefix = "<leader>ai", -- Change prefix from default <leader>c
  }
})
```

### Disable Features

```lua
require("claude-code-ide").setup({
  auto_start = false,      -- Don't auto-start server
  statusline = false,      -- Disable statusline integration
  keymaps = false,         -- Disable all keymaps
})
```

### Advanced UI Configuration

```lua
require("claude-code-ide").setup({
  -- Server settings
  port = 0,                -- 0 = random available port
  host = "127.0.0.1",
  
  -- Features
  auto_start = true,       -- Start server automatically
  statusline = true,       -- Show connection status in statusline
  
  -- Keymaps (set to false to disable)
  keymaps = {
    prefix = "<leader>c",
  },
  
  -- Debug settings
  debug = false,           -- Enable debug logging
})
```

## Default Key Mappings

| Key | Action | Description |
|-----|--------|-------------|
| `<leader>co` | `:ClaudeCodeConnect` | Launch Claude and connect |
| `<leader>cc` | Send selection/line | Send code to Claude |
| `<leader>cf` | Send function | Send current function |
| `<leader>cC` | Send class | Send current class |
| `<leader>cp` | Send paragraph | Send current paragraph |
| `<leader>cb` | Send buffer | Send entire file |
| `<leader>cs` | Start server | Start MCP server |
| `<leader>cS` | Stop server | Stop MCP server |
| `<leader>c?` | Show status | Show connection status |

### In Conversation Window

| Key | Action |
|-----|--------|
| `q` | Close window |
| `c` | Clear conversation |
| `s` | Save conversation |
| `r` | Refresh view |
| `?` | Show help |
| `y` | Copy message |
| `<CR>` | Send current line |

## Commands

```lua
-- Server control
vim.cmd("ClaudeCode start")     -- Start server
vim.cmd("ClaudeCode stop")      -- Stop server
vim.cmd("ClaudeCode status")    -- Show status

-- Quick connect
vim.cmd("ClaudeCodeConnect")    -- Launch Claude CLI and connect
```

## Statusline Integration

Add Claude's connection status to your statusline:

```lua
-- For custom statuslines, add this component:
"%{v:lua.require('claude-code-ide.statusline').get_status()}"

-- Example with lualine:
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('claude-code-ide.statusline').get_status()
      end,
    },
  },
})
```

## Text Objects

The plugin provides smart text object detection:

```lua
-- Send the function under cursor
vim.keymap.set("n", "<leader>cf", function()
  require("claude-code-ide.text_objects").send_function()
end)

-- Send the class under cursor
vim.keymap.set("n", "<leader>cC", function()
  require("claude-code-ide.text_objects").send_class()
end)

-- Works with any language that has treesitter support
```

## Session Persistence

Conversations are automatically saved and restored:

```lua
-- Conversations save to: ~/.local/share/nvim/claude-code-ide/conversations/
-- Auto-saves on: disconnect, every 60s, after tool execution
-- Auto-restores on reconnect

-- Load a previous conversation
require("claude-code-ide.persistence").show_picker()
```

## MCP Tools Available

Claude can use these tools to help you:

- **`openFile`** - Open files and select specific text ranges
- **`openDiff`** - Show changes in a non-blocking split
- **`getDiagnostics`** - Get LSP errors and warnings
- **`getCurrentSelection`** - Read your selected text
- **`getOpenEditors`** - See all open buffers
- **`getWorkspaceFolders`** - Get project structure

## Architecture

```
Claude CLI
    ↓
WebSocket connection
    ↓
Neovim MCP Server (this plugin)
    ├── Tools (file operations)
    ├── UI (conversation window)
    ├── Events (file changes)
    └── Persistence (auto-save)
```

## Troubleshooting

### Server Issues

```lua
-- Check server status
vim.cmd("ClaudeCode status")

-- View debug logs (if debug = true)
vim.cmd("messages")
```

### Connection Issues

1. **Claude CLI not found**: Install from [github.com/anthropics/claude-cli](https://github.com/anthropics/claude-cli)
2. **Lock file issues**: Check `~/.claude/ide/` for lock files
3. **Port conflicts**: Set a specific port in config

### Recovery Actions

The plugin provides actionable error messages:
- If Claude CLI fails: Press `<leader>ci` to open installation page
- If server crashes: Auto-restart with `:ClaudeCodeConnect`

## Requirements

- Neovim 0.8.0+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Claude CLI (`claude` command)
- (Optional) Treesitter for smart text objects

## License

MIT - See [LICENSE](LICENSE) for details