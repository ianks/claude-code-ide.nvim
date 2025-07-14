# claude-code.nvim Test Suite

This directory contains comprehensive tests for the claude-code.nvim MCP server implementation.

## Running Tests

```bash
# Run all tests
just test

# Run specific test file
just test-file tests/spec/lock_file_spec.lua

# Run with verbose output
just test-verbose
```

## Test Structure

### Declarative Specification Tests

- `spec/mcp_server_spec.lua` - Declarative specification of MCP server requirements
- `spec/helpers/mcp_spec_dsl.lua` - DSL for writing declarative specs

### Protocol Tests

- `spec/mcp_protocol_flow_spec.lua` - Tests the MCP protocol message flow
- `spec/helpers/mock_mcp_client.lua` - Mock MCP client for testing

### Implementation Tests

- `spec/server/websocket_spec.lua` - WebSocket implementation tests
- `spec/lock_file_spec.lua` - Lock file discovery mechanism tests

## Key Features

1. **Declarative Testing**: The MCP server specification is written declaratively, separate from implementation details. This makes it easy to update specs without changing test logic.

2. **Protocol Compliance**: Tests verify compliance with MCP protocol version 2025-06-18, including:
   - JSON-RPC 2.0 message format
   - Initialization flow
   - Tool registration and execution
   - Error handling

3. **Mock Infrastructure**: Comprehensive mocks for testing without real network connections:
   - Mock MCP server
   - Mock MCP client
   - Full protocol simulation

4. **Security Testing**: Verifies security requirements:
   - Lock file permissions (600)
   - Authentication token validation
   - Localhost-only binding

## Writing New Tests

### Adding a New Tool

1. Add the tool to `mcp_server_spec.lua`:
```lua
spec.tool("myNewTool", {
  description = "Description of the tool",
  input_schema = {
    param1 = { type = "string", required = true },
    param2 = { type = "boolean", default = false }
  },
  response_format = "content",
  implementation_notes = {
    "Use vim.api.nvim_... for implementation",
    "Handle edge cases"
  }
})
```

2. Add the tool to the mock server in `mock_mcp_client.lua`
3. Write protocol flow tests in `mcp_protocol_flow_spec.lua`

### Testing Implementation

Create implementation-specific tests separate from the declarative specs:

```lua
describe("My Implementation", function()
  it("should handle specific behavior", function()
    -- Test implementation details
  end)
end)
```

## Test Philosophy

- **Separation of Concerns**: Specs are separate from implementation
- **Declarative First**: Define what should happen, not how
- **Mock Everything**: Test in isolation without external dependencies
- **Security by Default**: Always test security requirements