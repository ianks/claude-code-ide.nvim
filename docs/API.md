# API Documentation

This document describes the public APIs available in claude-code.nvim for extending and customizing the plugin.

## Core Module

### `require("claude-code")`

The main module for plugin management.

#### Functions

##### `setup(opts)`

Initialize the plugin with configuration options.

```lua
require("claude-code").setup({
  -- configuration options
})
```

##### `start()`

Start the MCP server.

```lua
require("claude-code").start()
```

##### `stop()`

Stop the MCP server.

```lua
require("claude-code").stop()
```

##### `status()`

Get current plugin status.

```lua
local status = require("claude-code").status()
-- Returns: {
--   initialized = boolean,
--   server_running = boolean,
--   config = table
-- }
```

## Tools Module

### `require("claude-code.tools")`

Register and manage MCP tools.

#### Functions

##### `register(name, definition, handler)`

Register a custom tool.

```lua
local tools = require("claude-code.tools")

tools.register("myCustomTool", {
  description = "My custom tool description",
  inputSchema = {
    type = "object",
    properties = {
      param1 = { type = "string", description = "First parameter" },
      param2 = { type = "number", description = "Second parameter" }
    },
    required = { "param1" }
  }
}, function(args)
  -- Tool implementation
  -- args contains the parameters passed by Claude
  
  return {
    content = {
      {
        type = "text",
        text = "Tool result: " .. args.param1
      }
    }
  }
end)
```

##### `unregister(name)`

Remove a registered tool.

```lua
tools.unregister("myCustomTool")
```

##### `execute(name, args)`

Execute a tool programmatically.

```lua
local result = tools.execute("openFile", {
  filePath = "/path/to/file.lua",
  preview = false
})
```

##### `list()`

Get all registered tools.

```lua
local all_tools = tools.list()
```

## Resources Module

### `require("claude-code.resources")`

Manage MCP resources.

#### Functions

##### `register(uri, name, description, mime_type, metadata)`

Register a custom resource.

```lua
local resources = require("claude-code.resources")

resources.register(
  "custom://my-resource",
  "My Resource",
  "Description of my resource",
  "text/plain",
  { author = "Me", version = "1.0" }
)
```

##### `unregister(uri)`

Remove a registered resource.

```lua
resources.unregister("custom://my-resource")
```

##### `read(uri)`

Read a resource by URI.

```lua
local content = resources.read("file:///path/to/file.lua")
-- Returns: {
--   contents = {
--     {
--       uri = string,
--       mimeType = string,
--       text = string (or blob for binary)
--     }
--   }
-- }
```

##### `list(filter)`

List resources with optional filtering.

```lua
-- List all resources
local all = resources.list()

-- Filter by type
local files = resources.list({ type = "file" })

-- Filter by pattern
local lua_files = resources.list({ pattern = "%.lua$" })
```

## Events Module

### `require("claude-code.events")`

Event system for plugin lifecycle.

#### Functions

##### `on(event, handler)`

Subscribe to an event.

```lua
local events = require("claude-code.events")

events.on(events.events.CLIENT_CONNECTED, function(data)
  print("Client connected:", data.client_id)
end)
```

##### `off(event, handler)`

Unsubscribe from an event.

```lua
events.off(events.events.CLIENT_CONNECTED, my_handler)
```

##### `emit(event, data)`

Emit a custom event.

```lua
events.emit("my_custom_event", { foo = "bar" })
```

#### Available Events

```lua
events.events = {
  -- Server events
  SERVER_STARTED = "ServerStarted",
  SERVER_STOPPED = "ServerStopped",
  
  -- Client events
  CLIENT_CONNECTED = "ClientConnected",
  CLIENT_DISCONNECTED = "ClientDisconnected",
  AUTHENTICATION_FAILED = "AuthenticationFailed",
  
  -- Tool events
  TOOL_EXECUTING = "ToolExecuting",
  TOOL_EXECUTED = "ToolExecuted",
  TOOL_FAILED = "ToolFailed",
  
  -- Message events
  MESSAGE_RECEIVED = "MessageReceived",
  MESSAGE_SENT = "MessageSent",
  
  -- UI events
  CONVERSATION_OPENED = "ConversationOpened",
  CONVERSATION_CLOSED = "ConversationClosed",
  CONVERSATION_CLEARED = "ConversationCleared",
  
  -- Progress events
  PROGRESS_STARTED = "ProgressStarted",
  PROGRESS_UPDATED = "ProgressUpdated",
  PROGRESS_COMPLETED = "ProgressCompleted",
  
  -- Queue events
  REQUEST_QUEUED = "RequestQueued",
  REQUEST_PROCESSING = "RequestProcessing",
  REQUEST_COMPLETED = "RequestCompleted",
  REQUEST_FAILED = "RequestFailed",
  
  -- Terminal events
  TERMINAL_STARTED = "TerminalStarted",
  TERMINAL_EXITED = "TerminalExited",
  CODE_EXECUTED = "CodeExecuted",
}
```

## Cache Module

### `require("claude-code.cache")`

Cache management for performance optimization.

#### Functions

##### `get_cache(name, config)`

Get or create a named cache instance.

```lua
local cache = require("claude-code.cache")

local my_cache = cache.get_cache("my_cache", {
  max_size = 100,
  default_ttl = 300  -- 5 minutes
})
```

##### Cache Instance Methods

```lua
-- Set a value
my_cache:set("method_name", params, value, ttl)

-- Get a value
local value, hit = my_cache:get("method_name", params)

-- Invalidate entries
my_cache:invalidate()  -- All entries
my_cache:invalidate("pattern")  -- By pattern

-- Get statistics
local stats = my_cache:stats()

-- Clean expired entries
my_cache:cleanup()
```

## UI Module

### `require("claude-code.ui")`

User interface management.

#### Functions

##### `toggle_conversation()`

Toggle the conversation window.

```lua
require("claude-code.ui").toggle_conversation()
```

##### `send_message(text)`

Send a message to Claude.

```lua
require("claude-code.ui").send_message("Hello Claude!")
```

##### `clear_conversation()`

Clear the current conversation.

```lua
require("claude-code.ui").clear_conversation()
```

##### `show_diagnostics()`

Send workspace diagnostics to Claude.

```lua
require("claude-code.ui").show_diagnostics()
```

## Configuration Module

### `require("claude-code.config")`

Access and modify configuration at runtime.

#### Functions

##### `get(key)`

Get a configuration value.

```lua
local config = require("claude-code.config")
local ui_config = config.get("ui")
```

##### `set(key, value)`

Set a configuration value.

```lua
config.set("ui.conversation.width", 60)
```

##### `update(updates)`

Update multiple configuration values.

```lua
config.update({
  ["ui.conversation.width"] = 60,
  ["performance.cache.enabled"] = false
})
```

##### `reset(key)`

Reset a configuration value to default.

```lua
config.reset("ui.conversation.width")
```

## Custom Tool Example

Here's a complete example of creating a custom tool:

```lua
-- In your config or a separate module
local tools = require("claude-code.tools")
local notify = require("claude-code.ui.notify")

-- Register a tool to count lines in a file
tools.register("countLines", {
  description = "Count lines in a file",
  inputSchema = {
    type = "object",
    properties = {
      filePath = {
        type = "string",
        description = "Path to the file"
      },
      includeEmpty = {
        type = "boolean",
        description = "Include empty lines in count",
        default = true
      }
    },
    required = { "filePath" }
  }
}, function(args)
  local path = vim.fn.expand(args.filePath)
  
  if vim.fn.filereadable(path) ~= 1 then
    return {
      content = {
        {
          type = "text",
          text = "Error: File not found: " .. path
        }
      },
      isError = true
    }
  end
  
  local lines = vim.fn.readfile(path)
  local count = #lines
  
  if not args.includeEmpty then
    count = 0
    for _, line in ipairs(lines) do
      if line:match("%S") then  -- Has non-whitespace
        count = count + 1
      end
    end
  end
  
  return {
    content = {
      {
        type = "text",
        text = string.format("File %s has %d lines", path, count)
      }
    }
  }
end)
```

## Custom Resource Example

```lua
-- Register a resource that provides project statistics
local resources = require("claude-code.resources")

resources.register(
  "project://stats",
  "Project Statistics",
  "Statistical information about the current project",
  "application/json"
)

-- Handle reading this resource
local original_read = resources.read
resources.read = function(uri)
  if uri == "project://stats" then
    -- Gather statistics
    local stats = {
      total_files = vim.fn.systemlist("find . -type f -name '*.lua' | wc -l")[1],
      total_lines = vim.fn.systemlist("find . -type f -name '*.lua' -exec wc -l {} + | tail -1")[1],
      last_modified = os.date("%Y-%m-%d %H:%M:%S"),
    }
    
    return {
      contents = {
        {
          uri = uri,
          mimeType = "application/json",
          text = vim.json.encode(stats)
        }
      }
    }
  end
  
  -- Fall back to original implementation
  return original_read(uri)
end
```
