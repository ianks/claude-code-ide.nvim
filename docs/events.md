# Event System

claude-code.nvim provides a comprehensive event system that allows plugins and user configurations to react to various Claude-related events. The event system is built on top of Neovim's native User autocmds for maximum compatibility and performance.

## Quick Start

```lua
local events = require("claude-code.events")

-- Listen to a specific event
events.on("ToolExecuted", function(data)
  print("Tool executed:", data.tool_name)
end)

-- Listen to all events
events.on("*", function(data)
  print("Event fired:", vim.fn.expand("<amatch>"))
end)
```

## API Reference

### `events.on(event, callback, opts?)`

Subscribe to an event.

- **event** (string): Event name or pattern (e.g., "ToolExecuted" or "\*" for all)
- **callback** (function): Function called when event fires, receives data as argument
- **opts** (table?): Optional options (group, desc)
- **Returns**: number - The autocmd ID for unsubscribing

```lua
local id = events.on("FileOpened", function(data)
  print("Opened file:", data.file_path)
end)
```

### `events.once(event, callback, opts?)`

Subscribe to an event that fires only once.

```lua
events.once("Connected", function(data)
  print("Claude connected on port:", data.port)
end)
```

### `events.off(autocmd_id)`

Unsubscribe from an event.

```lua
local id = events.on("ToolExecuted", handler)
-- Later...
events.off(id)
```

### `events.emit(event, data)`

Emit an event (primarily for internal use).

```lua
events.emit("CustomEvent", { message = "Hello" })
```

### `events.group(name)`

Create an event group for better organization.

```lua
local group = events.group("MyPlugin")
events.on("ToolExecuted", handler, { group = group })
```

### `events.debug(enabled)`

Enable/disable debug logging of all events.

```lua
-- Enable debug mode
events.debug(true)

-- Disable debug mode
events.debug(false)
```

## Available Events

### Connection Events

| Event | Data | Description |
|-------|------|-------------|
| `Connected` | `{ }` | WebSocket connection established |
| `Disconnected` | `{ reason }` | Connection closed |
| `AuthenticationFailed` | `{ client_ip, reason }` | Authentication attempt failed |
| `ClientConnected` | `{ client_id, client_ip }` | New client connected |
| `ClientDisconnected` | `{ client_id, reason }` | Client disconnected |

### Server Events

| Event | Data | Description |
|-------|------|-------------|
| `ServerStarted` | `{ port, host, auth_token }` | MCP server started |
| `ServerStopped` | `{ port }` | MCP server stopped |
| `Initializing` | `{ }` | Server initializing |
| `Initialized` | `{ server }` | Server initialization complete |

### Tool Events

| Event | Data | Description |
|-------|------|-------------|
| `ToolExecuting` | `{ tool_name, arguments }` | Before tool execution |
| `ToolExecuted` | `{ tool_name, arguments, result }` | Tool executed successfully |
| `ToolFailed` | `{ tool_name, arguments, error }` | Tool execution failed |

### File Events

| Event | Data | Description |
|-------|------|-------------|
| `FileOpened` | `{ file_path, preview, selection }` | File opened via openFile tool |
| `DiffCreated` | `{ old_file_path, new_file_path, tab_name }` | Diff view created |

### Message Events

| Event | Data | Description |
|-------|------|-------------|
| `MessageReceived` | `{ raw, message }` | Raw message received from Claude |
| `MessageSent` | `{ message }` | Message sent to Claude |
| `RequestStarted` | `{ id, method, params }` | RPC request started |
| `RequestCompleted` | `{ id, method, result }` | RPC request completed |
| `RequestFailed` | `{ id, method, error }` | RPC request failed |

### Diagnostic Events

| Event | Data | Description |
|-------|------|-------------|
| `DiagnosticsRequested` | `{ uri }` | Diagnostics requested |
| `DiagnosticsProvided` | `{ uri, diagnostics, count }` | Diagnostics returned |

## Integration Examples

### Telescope Integration

Show Claude tool execution history:

```lua
local events = require("claude-code.events")
local tool_history = {}

events.on("ToolExecuted", function(data)
  table.insert(tool_history, {
    time = os.time(),
    tool = data.tool_name,
    args = data.arguments
  })
end)

-- Create Telescope picker for tool history
vim.keymap.set("n", "<leader>ch", function()
  require("telescope.pickers").new({}, {
    prompt_title = "Claude Tool History",
    finder = require("telescope.finders").new_table({
      results = tool_history,
      entry_maker = function(entry)
        return {
          value = entry,
          display = string.format("%s - %s", 
            os.date("%H:%M:%S", entry.time), 
            entry.tool
          ),
          ordinal = entry.tool
        }
      end
    })
  }):find()
end)
```

### lualine Integration

Show Claude connection status:

```lua
local events = require("claude-code.events")
local claude_status = "Disconnected"

events.on("Connected", function() claude_status = "Connected" end)
events.on("Disconnected", function() claude_status = "Disconnected" end)

require("lualine").setup({
  sections = {
    lualine_x = {
      {
        function() return "Claude: " .. claude_status end,
        color = function()
          return claude_status == "Connected" 
            and { fg = "#a6e3a1" } 
            or { fg = "#f38ba8" }
        end
      }
    }
  }
})
```

### nvim-notify Integration

Show tool execution notifications:

```lua
local events = require("claude-code.events")

events.on("ToolExecuted", function(data)
  require("notify")(
    string.format("Executed: %s", data.tool_name),
    "info",
    { title = "Claude Code" }
  )
end)

events.on("ToolFailed", function(data)
  require("notify")(
    string.format("Failed: %s\n%s", data.tool_name, data.error),
    "error",
    { title = "Claude Code" }
  )
end)
```

### Custom Autocmds

Since events use Neovim's User autocmds, you can also use traditional autocmds:

```vim
" VimScript
augroup ClaudeCodeEvents
  autocmd!
  autocmd User ClaudeCode:FileOpened echo "File opened by Claude"
augroup END
```

```lua
-- Lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudeCode:ToolExecuted",
  callback = function(args)
    print("Tool executed:", vim.inspect(args.data))
  end
})
```

## Best Practices

1. **Use Groups**: Organize related event handlers in groups for easy management
1. **Unsubscribe**: Remember to unsubscribe from events when no longer needed
1. **Error Handling**: Wrap event handlers in pcall for robustness
1. **Performance**: Avoid heavy operations in event handlers
1. **Wildcards**: Use wildcard patterns sparingly as they receive all events

## Debugging

Enable debug mode to see all events as they fire:

```lua
require("claude-code.events").debug(true)
```

This will log all events to Neovim's message history with their data.
