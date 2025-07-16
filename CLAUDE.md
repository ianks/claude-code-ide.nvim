# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

claude-code.nvim is a Neovim plugin that integrates Claude AI directly into the Neovim text editor. The project is currently in the specification phase with detailed technical requirements documented.

## Architecture

The plugin implements a Model Context Protocol (MCP) server:

1. **MCP Server**: A WebSocket-based MCP server running within Neovim (protocol version 2025-06-18)
1. **Lock File Discovery**: Uses ~/.claude/ide/<port>.lock for server discovery
1. **MCP Tools**: Implements tools for file operations, diagnostics, and editor state management

## Key Components (Planned)

### Server Implementation

- `lua/claude-code/server.lua` - MCP WebSocket server
- `lua/claude-code/tools/` - MCP tool implementations
- `lua/claude-code/discovery.lua` - Lock file management

### Client Interface

- `lua/claude-code/init.lua` - Plugin entry point
- `lua/claude-code/ui/` - UI components (windows, buffers)
- `lua/claude-code/commands.lua` - Vim commands

## Development Commands

**IMPORTANT: Always use `just` for running tests and development tasks.**

```bash
# Run all tests - THIS IS THE PRIMARY COMMAND FOR TESTING
just test

# Run tests with verbose output
just test-verbose

# Run a specific test file
just test-file tests/spec/server/websocket_spec.lua

# List all available commands
just --list


# Inspect claude code CLI implementation
npx js-beautify /opt/homebrew/bin/claude | grep -A50 -B50 "<search_string>"
```

The `just test` command is the core evaluation function for this project. It:

- Runs all tests using Plenary's test framework
- Provides consistent test execution across environments
- Returns exit code 0 on success, 1 on failure
- Is the canonical way to verify code correctness

## Implementation Guidelines

### MCP Tools to Implement

Critical tools from SPEC.md:

- `openFile` - Open files and select text
- `openDiff` - Show diff views
- `getDiagnostics` - Return LSP diagnostics
- `getCurrentSelection` - Get selected text
- `getOpenEditors` - List open buffers
- `getWorkspaceFolders` - Get workspace info

### Security Considerations

- Lock file must have 600 permissions
- Validate all file paths before operations
- WebSocket should only bind to localhost
- Implement proper error handling for all RPC methods

## Testing Strategy

**Always use `just test` to run tests. This is the canonical testing command.**

1. Unit tests for MCP tool handlers using busted/plenary.nvim
1. Integration tests with mock WebSocket connections
1. Manual testing with Claude CLI integration

Test files go in `tests/spec/` and follow the pattern `*_spec.lua`. Tests use the Plenary test framework with busted-style assertions.

## Configuration

The plugin should support configuration via:

```lua
require('claude-code').setup({
  port = 0,  -- 0 for random port (10000-65535)
  host = '127.0.0.1',
  debug = false,
  lock_file_dir = vim.fn.expand('~/.claude/ide'),
  server_name = 'claude-code.nvim',
  server_version = '0.1.0'
})
```

## Current Status

The project has two key specification documents:

- `SPEC.md`: MCP server implementation specification
- `PLUGIN_GUIDE.md`: Comprehensive Neovim plugin development guide

No implementation code exists yet. Development should start with the core MCP WebSocket server and lock file management.

## Searching Documentation

When searching for MCP protocol documentation or other technical specs:

1. First check if the documentation is already indexed:

   ```
   mcp__docs-mcp-server__search_docs library="mcp" query="tools list"
   ```

1. If not indexed, scrape the documentation:

   ```
   mcp__docs-mcp-server__scrape_docs url="https://modelcontextprotocol.io" library="mcp" maxPages=500 maxDepth=10 scope="domain"
   ```

1. For the MCP protocol specification specifically:

   - Main site: https://modelcontextprotocol.io
   - Use `scope="domain"` to capture all subpages
   - Increase `maxDepth` (default 3) to capture nested documentation
   - Increase `maxPages` (default 1000) for comprehensive coverage

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

### Reference Implementation

The VSCode extension implementation in "tmp/claude-code-vscode-extension-demangled.js" shows:

- MCP server implementation using the `Ra` class
- Lock file discovery mechanism
- WebSocket authentication flow
- Tool registration patterns
