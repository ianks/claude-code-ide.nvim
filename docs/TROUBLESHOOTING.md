# Troubleshooting Guide

This guide helps you diagnose and fix common issues with claude-code.nvim.

## Common Issues

### Server Won't Start

#### Symptoms

- `:ClaudeCodeStatus` shows server not running
- Error messages about port binding
- Lock file creation failures

#### Solutions

1. **Check if port is already in use**

   ```vim
   :ClaudeCodeLogSet DEBUG
   :lua require("claude-code").start()
   :ClaudeCodeLogShow
   ```

   Look for "bind" errors in the logs.

1. **Verify lock file permissions**

   ```bash
   ls -la ~/.claude/ide/
   ```

   Lock files should have 600 permissions.

1. **Try a specific port**

   ```lua
   require("claude-code").setup({
     port = 12345  -- Use a specific port instead of random
   })
   ```

### Claude Can't Connect

#### Symptoms

- Claude CLI shows "No IDE found"
- Authentication failures in logs
- WebSocket handshake errors

#### Solutions

1. **Ensure server is running**

   ```vim
   :ClaudeCodeStatus
   ```

1. **Check environment variables**

   ```vim
   :echo $ENABLE_IDE_INTEGRATION
   :echo $CLAUDE_CODE_SSE_PORT
   ```

   These should be set automatically.

1. **Verify Claude CLI version**

   ```bash
   claude --version
   ```

   Ensure you have a version that supports `--ide` flag.

1. **Check authentication**

   ```vim
   :ClaudeCodeLogShow
   ```

   Look for "Authentication failed" messages.

### Tools Not Working

#### Symptoms

- Tools fail with errors
- Claude can't open files or create diffs
- Diagnostics not showing

#### Solutions

1. **Check tool registration**

   ```lua
   local tools = require("claude-code.tools")
   vim.print(tools.list())
   ```

1. **Test tools manually**

   ```lua
   local tools = require("claude-code.tools")
   local result = tools.execute("openFile", {
     filePath = vim.fn.expand("%:p")
   })
   vim.print(result)
   ```

1. **Verify file paths**

   - Ensure you're using absolute paths
   - Check file permissions

### UI Issues

#### Symptoms

- Conversation window not appearing
- Layout problems
- Snacks.nvim errors

#### Solutions

1. **Check Snacks.nvim installation**

   ```vim
   :lua print(pcall(require, "snacks"))
   ```

1. **Fall back to basic UI**

   ```lua
   require("claude-code").setup({
     ui = {
       use_snacks = false  -- Disable Snacks.nvim
     }
   })
   ```

1. **Reset window layout**

   ```vim
   :ClaudeCodeToggle  " Close
   :ClaudeCodeToggle  " Reopen
   ```

### Performance Issues

#### Symptoms

- Slow responses
- High memory usage
- Neovim freezing

#### Solutions

1. **Check cache statistics**

   ```vim
   :ClaudeCodeCacheStats
   ```

   Clear if needed: `:ClaudeCodeCacheClear`

1. **Adjust performance settings**

   ```lua
   require("claude-code").setup({
     performance = {
       queue = {
         max_concurrent = 1,  -- Reduce concurrent requests
         rate_limit = 5       -- Reduce requests per minute
       },
       cache = {
         max_size = 50        -- Reduce cache size
       }
     }
   })
   ```

1. **Disable features**

   ```lua
   require("claude-code").setup({
     progress = { enabled = false },
     autocmds = false
   })
   ```

## Debugging

### Enable Debug Logging

```lua
require("claude-code").setup({
  debug = true,
  log = {
    level = "DEBUG"
  }
})
```

### View Logs

```vim
:ClaudeCodeLogShow       " Show in buffer
:ClaudeCodeLogSet TRACE  " Maximum verbosity
```

### Log File Location

```vim
:echo stdpath("data") . "/claude-code.log"
```

### Common Log Patterns

#### Successful connection

```
[DEBUG] WEBSOCKET: Received handshake headers
[DEBUG] WEBSOCKET: Computed Sec-WebSocket-Accept
[INFO] CLIENT_CONNECTED: { client_id = "..." }
```

#### Authentication failure

```
[WARN] AUTHENTICATION_FAILED: Invalid token
[DEBUG] WEBSOCKET: Sending 401 Unauthorized
```

#### Tool execution

```
[DEBUG] RPC: tools/call { name = "openFile", arguments = {...} }
[DEBUG] TOOL_EXECUTING: openFile
[DEBUG] TOOL_EXECUTED: openFile
```

## Health Check

Run this function to check your installation:

```lua
local function health_check()
  local ok = true
  local messages = {}
  
  -- Check Neovim version
  if vim.fn.has("nvim-0.9.0") ~= 1 then
    ok = false
    table.insert(messages, "ERROR: Neovim 0.9.0+ required")
  else
    table.insert(messages, "OK: Neovim version")
  end
  
  -- Check dependencies
  local deps = {
    ["plenary.nvim"] = "plenary",
    ["snacks.nvim"] = "snacks",
  }
  
  for name, module in pairs(deps) do
    if pcall(require, module) then
      table.insert(messages, "OK: " .. name .. " found")
    else
      if name == "snacks.nvim" then
        table.insert(messages, "WARN: " .. name .. " not found (optional)")
      else
        ok = false
        table.insert(messages, "ERROR: " .. name .. " not found")
      end
    end
  end
  
  -- Check openssl
  if vim.fn.executable("openssl") == 1 then
    table.insert(messages, "OK: openssl found")
  else
    ok = false
    table.insert(messages, "ERROR: openssl not found")
  end
  
  -- Check server
  local server = require("claude-code.server").get_server()
  if server and server.running then
    table.insert(messages, "OK: Server running on port " .. server.port)
  else
    table.insert(messages, "WARN: Server not running")
  end
  
  -- Check lock file
  local lock_dir = vim.fn.expand("~/.claude/ide")
  if vim.fn.isdirectory(lock_dir) == 1 then
    table.insert(messages, "OK: Lock directory exists")
  else
    table.insert(messages, "WARN: Lock directory missing: " .. lock_dir)
  end
  
  print("Claude Code Health Check")
  print("========================")
  for _, msg in ipairs(messages) do
    print(msg)
  end
  print("========================")
  print(ok and "Status: HEALTHY" or "Status: ISSUES FOUND")
end

-- Run the health check
health_check()
```

## Getting Help

1. **Check the documentation**

   - README.md for setup
   - API.md for programming
   - SPEC.md for protocol details

1. **Search existing issues**

   - https://github.com/ianks/claude-code.nvim/issues

1. **Create a new issue with:**

   - Neovim version (`:version`)
   - Plugin version
   - Minimal config to reproduce
   - Debug logs (`:ClaudeCodeLogShow`)
   - Steps to reproduce

## Emergency Recovery

If the plugin becomes unresponsive:

1. **Force stop the server**

   ```vim
   :lua require("claude-code.server").stop()
   ```

1. **Clear all state**

   ```bash
   rm -rf ~/.claude/ide/*.lock
   ```

1. **Restart Neovim and try again**
