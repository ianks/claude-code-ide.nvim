# claude-code.nvim 🤖 - The Ultimate AI Coding Assistant for Neovim

**Transform your Neovim into an AI-powered development environment** with seamless Claude AI integration via the Model Context Protocol (MCP). Get intelligent code assistance, refactoring suggestions, and natural language programming without leaving your editor.

## Features

- 🤖 **Direct Claude Integration** - Chat with Claude without leaving Neovim
- 🔧 **MCP Protocol Support** - Full implementation of the Model Context Protocol with WebSocket server
- 🎨 **Modern UI** - Beautiful conversation interface powered by Snacks.nvim
- 📁 **Resource Access** - Share files, templates, and workspace context with Claude
- 🛠️ **Tool Execution** - Let Claude open files, create diffs, and run diagnostics
- ⚡ **Performance** - Smart caching, request queuing, and rate limiting
- 🔌 **Extensible** - Add custom tools and resources via simple APIs

## Requirements

- Neovim >= 0.9.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [snacks.nvim](https://github.com/folke/snacks.nvim) (recommended for full UI experience)
- System `openssl` command (for WebSocket handshake)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ianks/claude-code.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "folke/snacks.nvim", -- Recommended for best UI experience
  },
  config = function()
    require("claude-code").setup()
  end,
}
```

For the simplest possible setup, use `config = true`:

```lua
{
  "ianks/claude-code.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = true,
}
```

## Quick Start

1. Install the plugin using your package manager
1. Start the MCP server: `:lua require("claude-code").start()`
1. Run Claude CLI: `claude --ide`
1. Claude automatically connects to Neovim via MCP
1. Start chatting with Claude!

## Default Keybindings

| Mapping | Mode | Description |
|---------|------|-------------|
| `<leader>cc` | n | Toggle Claude conversation window |
| `<leader>cs` | n, v | Send current selection or context to Claude |
| `<leader>cd` | n | Send workspace diagnostics |
| `<leader>cp` | n | Open command palette |
| `<leader>cr` | n | Retry last request |

## Configuration

```lua
require("claude-code").setup({
  -- Server configuration
  port = 0,                    -- 0 for random port
  host = "127.0.0.1",
  lock_file_dir = vim.fn.expand("~/.claude/ide"),
  server_name = "claude-code.nvim",
  server_version = "0.1.0",
  
  -- UI configuration
  ui = {
    conversation = {
      position = "right",     -- left, right, top, bottom, float
      width = 50,            -- Width for left/right positions
      height = 20,           -- Height for top/bottom positions
      border = "rounded",    -- Border style
      wrap = true,           -- Wrap long lines
      show_timestamps = true,
      auto_scroll = true,
    },
  },
  
  -- Enable debug logging
  debug = false,
  
  -- Keymaps (set to false to disable)
  keymaps = {
    toggle = "<leader>cc",
    send = "<leader>cs",
    -- ... see keymaps.lua for all options
  },
})
```

## Commands

| Command | Description |
|---------|-------------|
| `:ClaudeCodeToggle` | Toggle conversation window |
| `:ClaudeCodeSend` | Send selection or current context |
| `:ClaudeCodeStatus` | Show server status |
| `:ClaudeCodeRestart` | Restart MCP server |
| `:ClaudeCodeDiagnostics` | Send workspace diagnostics |
| `:ClaudeCodePalette` | Open command palette |
| `:ClaudeCodeCacheStats` | Show cache statistics |
| `:ClaudeCodeCacheClear` | Clear all caches |

## MCP Tools

Claude can use these tools to interact with your editor:

- **openFile** - Open files and select text ranges
- **openDiff** - Create diff views for code changes
- **getDiagnostics** - Get LSP diagnostics for workspace or specific files
- **getCurrentSelection** - Get currently selected text
- **getOpenEditors** - List all open buffers
- **getWorkspaceFolders** - Get workspace root and information

## MCP Resources

The plugin exposes various resources to Claude:

- **File Resources** - Access to any file in the workspace
- **Template Resources** - Bug reports, feature requests, code reviews
- **Snippet Resources** - Common code patterns and boilerplate
- **Workspace Resources** - Project structure and information
- **Documentation Resources** - Access to help files and project docs

## Development

**Requirements:** Neovim ≥ 0.9.0, Lua 5.1/LuaJIT

**Run Tests:**

```bash
just test                    # Run all tests
just test-file <path>       # Run specific test file
just test-verbose           # Run with verbose output
```

**Project Structure:**

- `lua/claude-code/` - Main plugin code
- `lua/claude-code/server/` - MCP WebSocket server
- `lua/claude-code/rpc/` - JSON-RPC handlers
- `lua/claude-code/tools/` - MCP tool implementations
- `tests/spec/` - Test specifications

## Contributing

See `SPEC.md` for the MCP implementation specification and `CLAUDE.md` for development guidelines. Please run tests before submitting pull requests.

## License

MIT
