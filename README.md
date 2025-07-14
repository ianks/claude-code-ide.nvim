# claude-code.nvim

Neovim integration for Claude AI, enabling seamless interaction with Claude directly from your editor through the Model Context Protocol (MCP).

## ✨ Features

- 🔌 WebSocket MCP server for Claude CLI integration
- 🔍 Automatic server discovery via lock files
- 📝 Send code, diagnostics, and editor state to Claude
- 💬 Interactive conversation window
- 🛠️ Rich set of MCP tools for editor interaction
- 🔒 Secure authentication and localhost-only binding

## 📦 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ianks/claude-code.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function()
    require("claude-code").setup({
      -- Configuration options
    })
  end,
}
```

**Note:** The plugin uses the system's `openssl` command for WebSocket handshake authentication.

## 🚀 Quick Start

1. Install the plugin using your package manager
2. Start the MCP server: `:lua require("claude-code").start()`
3. Launch Claude CLI with `claude --ide --debug`
4. Claude will automatically discover and connect to your Neovim instance

## ⚙️ Configuration

```lua
require("claude-code").setup({
  -- Server settings
  port = 0,                    -- 0 for random port (10000-65535)
  host = "127.0.0.1",         -- Localhost only for security
  
  -- Paths
  lock_file_dir = vim.fn.expand("~/.claude/ide"),
  
  -- Server info
  server_name = "claude-code.nvim",
  server_version = "0.1.0",
  
  -- UI settings
  ui = {
    conversation = {
      position = "right",
      width = 80,
      border = "rounded",
    },
  },
  
  -- Debug
  debug = false,
})
```

## 📋 Commands

- `:ClaudeCodeStart` - Start the MCP server
- `:ClaudeCodeStop` - Stop the MCP server
- `:ClaudeCodeToggle` - Toggle conversation window
- `:ClaudeCodeStatus` - Show server status
- `:ClaudeCodeRestart` - Restart the server

## 🛠️ MCP Tools

The plugin implements these MCP tools for Claude:

- `openFile` - Open files and select text
- `openDiff` - Show diff views
- `getDiagnostics` - Get LSP diagnostics
- `getCurrentSelection` - Get selected text
- `getOpenEditors` - List open buffers
- `getWorkspaceFolders` - Get workspace information

## 🔧 Development

### Prerequisites

- Neovim ≥ 0.9.0
- Lua 5.1 or LuaJIT
- Git CLI

### Dependencies

The plugin uses:
- `plenary.nvim` - Essential utilities
- `snacks.nvim` (optional) - For UI components
- System `openssl` command - For WebSocket authentication

### Running Tests

```bash
just test                    # Run all tests
just test-file <file>       # Run specific test file
just test-verbose           # Run with verbose output
```

### Example Configuration

See `examples/basic/init.lua` for a complete working configuration.

## 📁 Project Structure

```
claude-code.nvim/
├── lua/claude-code/         # Main plugin code
│   ├── server/             # WebSocket MCP server
│   ├── rpc.lua            # JSON-RPC protocol
│   ├── tools.lua          # MCP tool implementations
│   ├── events.lua         # Event system
│   └── ui/                # UI components
├── tests/                 # Test suite
├── examples/              # Example configurations
└── doc/                   # Documentation
```

## 🤝 Contributing

Contributions are welcome! Please read:
- `SPEC.md` - Technical specification
- `CLAUDE.md` - Guidelines for AI assistance
- Run tests with `just test` before submitting

## 📄 License

MIT License