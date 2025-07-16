# claude-code.nvim MCP Server Specification

## Overview

claude-code.nvim implements a Model Context Protocol (MCP) server that enables Claude CLI to interact with Neovim. The server follows the [MCP specification version 2025-06-18](https://modelcontextprotocol.io/specification/2025-06-18).

## Discovery & Connection

### Lock File Discovery

The Neovim MCP server uses a lock file mechanism for discovery:

1. **Lock File Location**: `~/.claude/ide/<port>.lock`
1. **Lock File Content**:

```json
{
  "pid": <neovim_process_id>,
  "workspaceFolders": ["/path/to/workspace"],
  "ideName": "Neovim",
  "transport": "ws",
  "runningInWindows": false,
  "authToken": "<uuid>"
}
```

### Connection Process

1. **Start WebSocket Server**: Listen on `127.0.0.1` with a random port (10000-65535)
1. **Generate Auth Token**: Create a UUID for authentication
1. **Create Lock File**: Write server info to `~/.claude/ide/<port>.lock`
1. **Set Environment Variables** (for Neovim terminal):
   - `ENABLE_IDE_INTEGRATION="true"`
   - `CLAUDE_CODE_SSE_PORT="<port>"`
1. **WebSocket Authentication**: Validate `x-claude-code-ide-authorization` header

## MCP Protocol Implementation

### Server Initialization

```json
// Request
{
  "jsonrpc": "2.0",
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {
      "name": "Claude CLI",
      "version": "x.y.z"
    }
  },
  "id": 1
}

// Response
{
  "jsonrpc": "2.0",
  "result": {
    "protocolVersion": "2025-06-18",
    "capabilities": {
      "tools": { "listChanged": true },
      "resources": { "listChanged": true }
    },
    "serverInfo": {
      "name": "claude-code.nvim",
      "version": "0.1.0"
    },
    "instructions": "Neovim MCP server for Claude integration"
  },
  "id": 1
}
```

### Available Tools

The server must implement these MCP tools:

#### openFile

Opens a file in Neovim and optionally selects text.

```typescript
{
  name: "openFile",
  description: "Open a file in the editor",
  inputSchema: {
    type: "object",
    properties: {
      filePath: { type: "string", description: "Path to file" },
      preview: { type: "boolean", description: "Open in preview mode" },
      startText: { type: "string", description: "Start of selection" },
      endText: { type: "string", description: "End of selection" },
      makeFrontmost: { type: "boolean", description: "Focus the buffer" }
    },
    required: ["filePath"]
  }
}
```

#### openDiff

Shows a diff view for file changes.

```typescript
{
  name: "openDiff",
  description: "Open a diff view",
  inputSchema: {
    type: "object",
    properties: {
      old_file_path: { type: "string" },
      new_file_path: { type: "string" },
      new_file_contents: { type: "string" },
      tab_name: { type: "string" }
    },
    required: ["old_file_path", "new_file_path", "new_file_contents", "tab_name"]
  }
}
```

#### getDiagnostics

Returns LSP diagnostics.

```typescript
{
  name: "getDiagnostics",
  description: "Get language diagnostics",
  inputSchema: {
    type: "object",
    properties: {
      uri: { type: "string", description: "Optional file URI" }
    }
  }
}
```

#### getCurrentSelection

Returns current text selection.

```typescript
{
  name: "getCurrentSelection",
  description: "Get current text selection",
  inputSchema: {
    type: "object",
    properties: {}
  }
}
```

#### getOpenEditors

Returns list of open buffers.

```typescript
{
  name: "getOpenEditors",
  description: "Get open editors",
  inputSchema: {
    type: "object",
    properties: {}
  }
}
```

#### getWorkspaceFolders

Returns workspace folders.

```typescript
{
  name: "getWorkspaceFolders",
  description: "Get workspace folders",
  inputSchema: {
    type: "object",
    properties: {}
  }
}
```

## Implementation Notes

### Neovim Specifics

1. Use `vim.uv` (libuv) for WebSocket server implementation
1. Use `vim.json` for JSON serialization
1. Handle tool calls through standard MCP tool execution flow
1. Maintain compatibility with Neovim's async architecture using `plenary.async`

### Security

1. Lock file must have 600 permissions
1. Only bind to localhost (127.0.0.1)
1. Validate auth token on WebSocket upgrade
1. Validate all file paths before operations

### Response Format

All tool responses follow MCP content format:

```json
{
  "content": [
    {
      "type": "text",
      "text": "Response text or JSON"
    }
  ]
}
```

## Testing

Use the Claude CLI with environment variables set:

```bash
export ENABLE_IDE_INTEGRATION="true"
export CLAUDE_CODE_SSE_PORT="<port>"
claude
```

The CLI will discover the server via the lock file and connect using the MCP protocol.
