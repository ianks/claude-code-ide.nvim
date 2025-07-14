# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-code.nvim is a Neovim plugin that integrates Claude AI directly into the Neovim text editor. The project is currently in the specification phase with detailed technical requirements documented.

## Architecture

The plugin follows a client-server architecture:

1. **WebSocket Server**: A Lua-based server running within Neovim that handles JSON-RPC 2.0 protocol
2. **Lock File Discovery**: Uses ~/.claude/nvim/servers.lock for server discovery
3. **RPC Communication**: Implements methods for file operations, diagnostics, and editor state management

## Key Components (Planned)

### Server Implementation
- `lua/claude-code/server.lua` - WebSocket server handling RPC requests
- `lua/claude-code/rpc/` - RPC method implementations
- `lua/claude-code/discovery.lua` - Lock file management

### Client Interface
- `lua/claude-code/init.lua` - Plugin entry point
- `lua/claude-code/ui/` - UI components (windows, buffers)
- `lua/claude-code/commands.lua` - Vim commands

## Development Commands

Since this is a Neovim plugin project in planning phase:

```bash
# Run Neovim with the plugin loaded (once implemented)
nvim --cmd "set rtp+=."

# Run tests (once test framework is set up)
# Typically: nvim --headless -c "PlenaryBustedDirectory tests/ {minimal_init.lua}"
```

## Implementation Guidelines

### RPC Methods to Implement

Critical methods from SPEC.md:
- `textDocument/didOpen` - File opened notifications
- `textDocument/didChange` - File change notifications
- `workspace/executeCommand` - Execute editor commands
- `workspace/applyEdit` - Apply file modifications
- `window/visibleRanges` - Get visible text ranges

### Security Considerations

- Lock file must have 600 permissions
- Validate all file paths before operations
- WebSocket should only bind to localhost
- Implement proper error handling for all RPC methods

## Testing Strategy

1. Unit tests for RPC handlers using busted/plenary.nvim
2. Integration tests with mock WebSocket connections
3. Manual testing with Claude CLI integration

## Configuration

The plugin should support configuration via:
```lua
require('claude-code').setup({
  port = 0,  -- 0 for random port
  host = '127.0.0.1',
  debug = false,
  lock_file_path = vim.fn.expand('~/.claude/nvim/servers.lock')
})
```

## Current Status

The project has two key specification documents:
- `SPEC.md`: Technical requirements for the WebSocket server
- `PLUGIN_GUIDE.md`: Comprehensive Neovim plugin development guide

No implementation code exists yet. Development should start with the core WebSocket server and lock file management.

## Available Dependencies

The following plugins are already available in the user's Neovim configuration and should be leveraged:

### Core Libraries

**plenary.nvim** - Essential utilities
- Use `plenary.async` for async/await style programming with WebSocket handlers
- Use `plenary.path` for lock file and path operations
- Use `plenary.job` if needing to spawn processes
- Use `plenary.busted` for unit testing

**nvim-nio** - Async I/O
- Complementary to plenary.async for I/O operations
- Good for file watching and async file operations

### UI Components

**snacks.nvim** - Modern UI framework (preferred)
- Use `Snacks.win` for Claude conversation windows
- Use `Snacks.notifier` for status notifications
- Use `Snacks.input` for user prompts
- Use `Snacks.animate` for smooth UI transitions

**nui.nvim** - Alternative UI library
- Use as fallback if snacks.nvim doesn't meet specific needs
- Good for complex layouts

### Supporting Libraries

**mini.icons** - File type icons
- Use for displaying file types in UI

**nvim-window-picker** - Window selection
- Use when user needs to select target window for operations

**which-key.nvim** - Command palette
- Register claude-code commands for discoverability

### JSON Handling

Use built-in `vim.json`:
```lua
local encoded = vim.json.encode(data)
local decoded = vim.json.decode(json_string)
```

No external JSON library needed - vim.json is sufficient for RPC messages.

### WebSocket Implementation

Since no WebSocket library is available, implement using `vim.uv` (libuv):
- Reference instant.nvim's websocket_server.lua for proven patterns
- Use `vim.uv.new_tcp()` for server socket
- Implement WebSocket handshake and frame parsing