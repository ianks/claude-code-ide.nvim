# claude-code.nvim

Neovim plugin for Claude AI integration via Model Context Protocol (MCP).

## Features

- WebSocket MCP server for Claude CLI
- Auto-discovery via lock files
- Send code, diagnostics, and editor state to Claude
- Interactive conversation window
- Rich MCP tools for editor interaction

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "ianks/claude-code.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("claude-code").setup({})
  end,
}
```

**Note:** Requires system `openssl` command.

## Quick Start

1. Install the plugin
2. Start server: `:lua require("claude-code").start()`
3. Run: `claude --ide`
4. Claude auto-connects to Neovim

## Configuration

```lua
require("claude-code").setup({
  port = 0,                    -- 0 for random port
  host = "127.0.0.1",
  lock_file_dir = vim.fn.expand("~/.claude/ide"),
  server_name = "claude-code.nvim",
  server_version = "0.1.0",
  ui = {
    conversation = {
      position = "right",
      width = 80,
      border = "rounded",
    },
  },
  debug = false,
})
```

## Commands

- `:ClaudeCodeStart` - Start server
- `:ClaudeCodeStop` - Stop server
- `:ClaudeCodeToggle` - Toggle conversation
- `:ClaudeCodeStatus` - Show status
- `:ClaudeCodeRestart` - Restart server

## MCP Tools

- `openFile` - Open files and select text
- `openDiff` - Show diffs
- `getDiagnostics` - Get LSP diagnostics
- `getCurrentSelection` - Get selected text
- `getOpenEditors` - List open buffers
- `getWorkspaceFolders` - Get workspace info

## Development

**Requirements:** Neovim ≥ 0.9.0, Lua 5.1/LuaJIT

**Tests:** `just test`

**Example:** See `examples/basic/init.lua`

## Contributing

See `SPEC.md` and `CLAUDE.md`. Run tests before submitting.

## License

MIT