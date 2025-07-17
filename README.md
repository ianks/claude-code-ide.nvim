# claude-code-ide.nvim

Native Claude Code integration for Neovim via the Model Context Protocol (MCP).

> 🚧 **Under Active Development** - Core functionality is working. API may change.

## Overview

claude-code-ide.nvim provides a WebSocket MCP server that runs inside Neovim, allowing Claude Code to interact with your editor as if it were a built-in IDE. Claude can open files, view diagnostics, create diffs, and help you write code without leaving your workflow.

## Features

- **MCP WebSocket Server** - Runs directly in Neovim, no external processes
- **IDE Tools** - Claude can open files, create diffs, view diagnostics, and more
- **Auto-Discovery** - Claude Code automatically finds your Neovim instance via lock files
- **Rich UI** - Integrated conversation window, progress indicators, and notifications
- **Async Architecture** - Non-blocking operations using plenary.async
- **Comprehensive Config** - Extensive customization options with sensible defaults

## Installation

```lua
-- lazy.nvim
{
  "ianks/claude-code-ide.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = true,
}
```

For advanced setups, see [examples/](examples/):
- [minimal.lua](examples/minimal.lua) - Bare minimum setup
- [standard.lua](examples/standard.lua) - Recommended configuration
- [advanced-config.lua](examples/advanced-config.lua) - All options explained

## Quick Start

1. Start the MCP server:
   ```vim
   :ClaudeCodeStart
   ```

2. Connect from Claude Code:
   ```bash
   claude --ide
   ```

The server creates a lock file at `~/.claude/nvim/servers.lock` for automatic discovery.

## Commands

| Command | Description |
|---------|-------------|
| `:ClaudeCodeStart` | Start the MCP server |
| `:ClaudeCodeStop` | Stop the MCP server |
| `:ClaudeCodeRestart` | Restart the MCP server |
| `:ClaudeCodeStatus` | Show server status |
| `:ClaudeCodeToggle` | Toggle conversation window |
| `:ClaudeCodeSend` | Send selection or current context |
| `:ClaudeCodeLogs` | View debug logs |
| `:ClaudeCodeClearLogs` | Clear debug logs |

## Default Key Mappings

| Key | Action | Mode |
|-----|--------|------|
| `<leader>cc` | Toggle conversation | n |
| `<leader>cs` | Send selection | n, v |
| `<leader>cf` | Send current file | n |
| `<leader>cd` | Send diagnostics | n |
| `<leader>cD` | Open diff view | n |
| `<leader>cn` | New conversation | n |
| `<leader>cx` | Clear conversation | n |
| `<leader>cr` | Retry last message | n |
| `<leader>cp` | Show command palette | n |
| `<leader>ct` | Toggle context | n |
| `<leader>cv` | Toggle preview | n |
| `<leader>cl` | Cycle layout | n |

All mappings use `<leader>c` as prefix by default. Configure with `keymaps.prefix`.

## MCP Tools Available to Claude

- **`openFile`** - Open files and optionally select text ranges
- **`openDiff`** - Create diff views showing code changes
- **`close_tab`** - Close tabs after operations
- **`getDiagnostics`** - Get LSP diagnostics for files or workspace
- **`getCurrentSelection`** - Read selected text in visual mode
- **`getOpenEditors`** - List all open buffers with metadata
- **`getWorkspaceFolders`** - Get project root and workspace info
- **`closeAllDiffTabs`** - Clean up all diff view tabs

## Configuration

```lua
require("claude-code-ide").setup({
  -- Server settings
  server = {
    host = "127.0.0.1",
    port = 0,  -- 0 = random port
    auto_start = false,  -- Start server on setup
  },
  
  -- UI settings
  ui = {
    conversation = {
      position = "right",  -- right, left, bottom, top, float
      width = 80,
      border = "rounded",
    },
  },
  
  -- Keymaps
  keymaps = {
    enabled = true,
    prefix = "<leader>c",
    -- See advanced-config.lua for all mappings
  },
  
  -- Debug
  debug = {
    enabled = false,
    log_level = "info",  -- debug, info, warn, error
  },
})
```

See [examples/advanced-config.lua](examples/advanced-config.lua) for all options.

## Architecture

```
Claude Code CLI
      |
      v
WebSocket (port from lock file)
      |
      v
Neovim MCP Server
      |
      +---> Tools (file ops, diagnostics)
      +---> Resources (workspace info)
      +---> UI (windows, notifications)
      +---> Events (file changes, etc)
```

The plugin uses:
- **plenary.nvim** for async operations
- **vim.uv** for WebSocket server
- **vim.lsp** for diagnostics integration
- Native Neovim APIs for all editor operations

## Development

```bash
just test                    # Run all tests
just test-verbose           # Run tests with verbose output
just test-file <file>       # Test specific file
just --list                 # Show all commands
```

Tests use Plenary's test framework. See [tests/README.md](tests/README.md) for details.

## Requirements

- Neovim 0.9.0+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- Claude Code CLI (for connecting)

## Troubleshooting

1. **Server won't start**: Check `:ClaudeCodeStatus` and `:ClaudeCodeLogs`
2. **Claude can't connect**: Verify lock file exists at `~/.claude/nvim/servers.lock`
3. **WebSocket errors**: Ensure no firewall blocking localhost connections
4. **Tool errors**: Enable debug mode and check logs

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more.

## Contributing

Contributions welcome! Please:
1. Run tests with `just test`
2. Follow existing code style
3. Update tests for new features

## License

MIT - See [LICENSE](LICENSE) for details