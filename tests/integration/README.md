# Integration Tests

This directory contains integration tests for claude-code.nvim that test real components with minimal mocking.

## Philosophy

Unlike unit tests that mock heavily, these integration tests:

1. **Use real WebSocket connections** - No mocked TCP sockets or handshakes
2. **Start actual servers** - Real server lifecycle with lock files
3. **Perform real vim operations** - Actual buffer/window manipulation
4. **Test end-to-end workflows** - Complete user scenarios

## Test Structure

```
integration/
├── helpers/
│   ├── websocket_client.lua  - Real WebSocket client implementation
│   └── setup.lua             - Test utilities and helpers
├── server_integration_spec.lua    - Server lifecycle and protocol tests
├── tools_integration_spec.lua     - Tool execution with real vim ops
└── session_integration_spec.lua   - Session management and workflows
```

## Running Tests

```bash
# Run all integration tests
just test-integration

# Run specific integration test
just test-integration-file tests/integration/server_integration_spec.lua

# Run all tests (unit + integration)
just test-all
```

## Key Components

### WebSocket Client

The `websocket_client.lua` implements a real WebSocket client using vim.loop (libuv):
- Performs actual TCP connections
- Implements WebSocket handshake (RFC 6455)
- Handles frame parsing and masking
- Supports async request/response pattern

### Test Helpers

The `setup.lua` provides utilities for:
- Temporary workspace creation
- Real server lifecycle management
- Client creation with auth
- Assertions for JSON-RPC responses

### Test Scenarios

1. **Server Integration**
   - Server startup and shutdown
   - Lock file creation/cleanup
   - Authentication validation
   - Concurrent connections
   - Error handling

2. **Tools Integration**
   - File operations (openFile)
   - Diagnostics retrieval
   - Selection handling
   - Buffer management
   - Diff creation

3. **Session Integration**
   - State persistence
   - Multi-step workflows
   - Resource subscriptions
   - Error recovery

## Benefits

1. **Higher Confidence** - Tests actual component interactions
2. **Catch Integration Bugs** - Find issues mocks might hide
3. **Better Documentation** - Shows real usage patterns
4. **Regression Prevention** - Ensures protocol compatibility

## Writing New Integration Tests

```lua
describe("Feature Integration", function()
  it("performs real operation", function()
    helpers.with_temp_workspace(function(workspace)
      helpers.with_real_server({}, function(server, config)
        -- Get auth token
        local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
        
        -- Create real client
        local client = helpers.create_client(server.port, lock_file.authToken)
        
        -- Initialize connection
        client:request("initialize", {
          protocolVersion = "2025-06-18",
          capabilities = {},
          clientInfo = { name = "Test", version = "1.0" }
        })
        client:notify("initialized", {})
        
        -- Test real operations
        local response = client:request("tools/call", {
          name = "someRealTool",
          arguments = { real = "data" }
        })
        
        -- Assert on actual results
        assert.truthy(response.result)
        
        -- Cleanup
        client:close()
      end)
    end)
  end)
end)
```

## Debugging

Set debug mode in tests:
```lua
client:set_debug(true)  -- Prints all WebSocket messages
```

Or enable server debug:
```lua
helpers.with_real_server({ debug = true }, function(server, config)
  -- Server will log all operations
end)
```

## Known Limitations

1. **Speed** - Integration tests are slower than unit tests
2. **Environment** - Requires Neovim with plenary.nvim
3. **Async Timing** - Some operations need wait times
4. **Session Isolation** - Vim state is shared between tests

## Future Improvements

1. Parallel test execution
2. Better session isolation
3. Performance benchmarking
4. Coverage reporting
5. CI/CD optimizations