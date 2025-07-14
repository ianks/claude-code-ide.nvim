-- Basic example configuration for claude-code.nvim
-- This config demonstrates a complete setup with UI and all dependencies

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Basic Neovim settings
vim.g.mapleader = " "
vim.g.maplocalleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"

-- Plugin setup
require("lazy").setup({
  -- Essential dependencies
  {
    "nvim-lua/plenary.nvim",
    lazy = false,
    priority = 1000,
  },

  -- UI framework - required for conversation window
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    config = function()
      require("snacks").setup({
        notifier = {
          enabled = true,
          top_down = false,
        },
        terminal = {
          enabled = true,
          win = {
            border = "rounded",
          },
        },
        win = {
          -- Default window options for snacks windows
          wo = {
            wrap = true,
            linebreak = true,
          },
        },
      })
    end,
  },

  -- Icons support
  {
    "echasnovski/mini.icons",
    config = function()
      require("mini.icons").setup()
    end,
  },

  -- Better notifications (optional but nice)
  {
    "rcarriga/nvim-notify",
    config = function()
      vim.notify = require("notify")
    end,
  },

  -- Treesitter for better markdown highlighting in conversation
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "markdown", "markdown_inline", "json" },
        highlight = { enable = true },
      })
    end,
  },

  -- claude-code.nvim (local development)
  {
    dir = vim.fn.getcwd(), -- Load from current directory
    name = "claude-code.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "folke/snacks.nvim",
    },
    config = function()
      local claude = require("claude-code")
      
      -- Complete setup with all options
      claude.setup({
        -- Server configuration
        port = 0, -- Random port
        host = "127.0.0.1",
        server_name = "claude-code.nvim-example",
        server_version = "0.1.0",
        
        -- Lock file location
        lock_file_dir = vim.fn.expand("~/.claude/ide"),
        
        -- UI configuration (this was missing!)
        ui = {
          conversation = {
            position = "right",
            width = 80,
            border = "rounded",
          },
        },
        
        -- Enable debug mode
        debug = true,
        
        -- Add debug logging to file
        debug_log_file = vim.fn.expand("~/claude-code-debug.log"),
      })
      
      -- Start the server
      local server = claude.start()
      
      if server then
        -- Use snacks notifier for nice notifications
        local Snacks = require("snacks")
        Snacks.notify.info(
          string.format("Claude Code server started on port %d", server.port),
          { title = "Claude Code" }
        )
        
        -- Show auth token in a separate notification
        vim.defer_fn(function()
          Snacks.notify.info(
            string.format("Auth token: %s", server.auth_token),
            { title = "Claude Code", timeout = 10000 }
          )
        end, 500)
      end
    end,
    keys = {
      { "<leader>cc", "<cmd>ClaudeCodeToggle<cr>", desc = "Toggle Claude conversation" },
      { "<leader>cn", "<cmd>ClaudeNew<cr>", desc = "New Claude CLI session" },
      { "<leader>ct", "<cmd>ClaudeToggleTerm<cr>", desc = "Toggle Claude terminal" },
      { "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = { "n", "v" }, desc = "Send to Claude" },
      { "<leader>cd", "<cmd>ClaudeCodeDiagnostics<cr>", desc = "Send diagnostics to Claude" },
      { "<leader>ci", "<cmd>ClaudeCodeStatus<cr>", desc = "Show Claude status" },
      { "<leader>cr", "<cmd>ClaudeCodeRestart<cr>", desc = "Restart Claude server" },
    },
    -- Also create some user commands
    init = function()
      -- Add commands for starting/stopping server
      vim.api.nvim_create_user_command("ClaudeCodeStart", function()
        require("claude-code").start()
      end, { desc = "Start Claude Code server" })
      
      vim.api.nvim_create_user_command("ClaudeCodeStop", function()
        require("claude-code").stop()
      end, { desc = "Stop Claude Code server" })
    end,
  },

  -- Which-key for discovering keybindings
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      local wk = require("which-key")
      wk.setup()
      
      -- Register Claude Code mappings
      wk.register({
        ["<leader>c"] = {
          name = "+claude",
          c = { "Toggle conversation" },
          n = { "New Claude CLI session" },
          t = { "Toggle Claude terminal" },
          s = { "Send to Claude" },
          d = { "Send diagnostics" },
          i = { "Show status" },
          r = { "Restart server" },
        },
      })
    end,
  },
}, {
  -- Lazy.nvim options
  ui = {
    border = "rounded",
  },
  checker = {
    enabled = false,
  },
  change_detection = {
    enabled = false,
  },
})

-- Example event listeners with nice notifications
local events = require("claude-code.events")
local Snacks = require("snacks")

-- Connection events with snacks notifications
events.on("Connected", function()
  Snacks.notify.info("Claude connected!", { title = "Claude Code" })
end)

events.on("Disconnected", function(data)
  Snacks.notify.warn(
    "Claude disconnected: " .. (data.reason or "unknown"),
    { title = "Claude Code" }
  )
end)

-- Tool execution tracking
local tool_count = 0
events.on("ToolExecuted", function(data)
  tool_count = tool_count + 1
  -- Don't spam notifications, just update a counter
  vim.g.claude_tool_count = tool_count
end)

-- Show errors prominently
events.on("ToolFailed", function(data)
  Snacks.notify.error(
    string.format("Tool '%s' failed: %s", data.tool_name, data.error),
    { title = "Claude Code Error" }
  )
end)

-- Authentication failures
events.on("AuthenticationFailed", function(data)
  Snacks.notify.error(
    "Authentication failed from " .. data.client_ip,
    { title = "Claude Code Security" }
  )
end)

-- Debug mode: log all events to messages
-- Enable this to see events
events.debug(true)

-- Custom statusline component showing Claude status and tool count
vim.o.statusline = table.concat({
  "%f %m",                                                              -- filename and modified flag
  "%=",                                                                 -- right align
  "Tools: %{get(g:, 'claude_tool_count', 0)} ",                       -- tool execution count
  "Claude: %{luaeval('require(\"claude-code\").status().server_running and \"●\" or \"○\"')} ", -- connection indicator
  "%l:%c",                                                             -- line:column
}, "")

-- Start a new Claude CLI session in a terminal
vim.api.nvim_create_user_command("ClaudeNew", function()
  local server = require("claude-code.server").get_server()
  if not server then
    Snacks.notify.error("Server not running! Start it first with <leader>cs", { title = "Claude Code" })
    return
  end
  
  -- Use snacks.terminal for a better terminal experience
  local term = Snacks.terminal({ "/opt/homebrew/bin/claude", "--ide", "--debug" }, {
    cwd = vim.fn.getcwd(),
    env = {
      -- Pass through any environment variables Claude might need
      HOME = vim.env.HOME,
      PATH = vim.env.PATH,
      SHELL = vim.env.SHELL,
    },
    win = {
      position = "bottom",
      height = 0.4,
      border = "rounded",
      title = " Claude CLI Session (IDE + Debug) ",
      title_pos = "center",
      footer = string.format(" Port: %d | <C-\\><C-n> to exit insert mode ", server.port),
      footer_pos = "center",
    },
  })
  
  -- Open and focus the terminal
  term:toggle()
  
  -- Notify user
  Snacks.notify.info(
    string.format("Starting Claude CLI in IDE mode (server on port %d)", server.port),
    { title = "Claude Code" }
  )
end, { desc = "Start a new Claude CLI session in terminal" })

-- Create a persistent Claude terminal that can be toggled
local claude_terminal = nil

vim.api.nvim_create_user_command("ClaudeToggleTerm", function()
  local server = require("claude-code.server").get_server()
  if not server then
    Snacks.notify.error("Server not running! Start it first", { title = "Claude Code" })
    return
  end
  
  -- Create terminal if it doesn't exist
  if not claude_terminal then
    claude_terminal = Snacks.terminal({ "/opt/homebrew/bin/claude", "--ide", "--debug" }, {
      cwd = vim.fn.getcwd(),
      win = {
        position = "bottom",
        height = 0.4,
        border = "rounded",
        title = " Claude CLI (IDE + Debug) ",
        title_pos = "center",
        footer = string.format(" Port: %d | <C-\\><C-n> for normal mode | <leader>ct to toggle ", server.port),
        footer_pos = "center",
      },
    })
    -- Show it immediately after creation
    claude_terminal:show()
  else
    -- Toggle the terminal
    claude_terminal:toggle()
  end
end, { desc = "Toggle persistent Claude CLI terminal" })

-- Helper commands
vim.api.nvim_create_user_command("ClaudeInfo", function()
  local server = require("claude-code.server").get_server()
  if server then
    local info = {
      "Claude Code Server Information",
      "==============================",
      string.format("Port: %d", server.port),
      string.format("Host: %s", server.host),
      string.format("Auth Token: %s", server.auth_token),
      string.format("Lock File: %s", server.lock_file_path or "none"),
      string.format("Initialized: %s", server.initialized and "yes" or "no"),
      string.format("Running: %s", server.running and "yes" or "no"),
      string.format("Clients: %d", vim.tbl_count(server.clients)),
      "",
      "Tools executed: " .. (vim.g.claude_tool_count or 0),
    }
    
    -- Create a floating window with the info
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, info)
    vim.bo[buf].modifiable = false
    
    local width = 50
    local height = #info
    local win = vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      width = width,
      height = height,
      col = (vim.o.columns - width) / 2,
      row = (vim.o.lines - height) / 2,
      style = "minimal",
      border = "rounded",
      title = " Claude Code Info ",
      title_pos = "center",
    })
    
    -- Close on any key
    vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf })
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf })
  else
    Snacks.notify.warn("Server not running", { title = "Claude Code" })
  end
end, { desc = "Show detailed Claude Code server information" })

-- Test command to verify events are working
vim.api.nvim_create_user_command("ClaudeTest", function()
  local tools = require("claude-code.tools")
  
  -- Test openFile tool
  local result = tools.execute("openFile", {
    filePath = vim.fn.expand("%:p"),
    preview = false,
  })
  
  Snacks.notify.info("Test completed - check notifications", { title = "Claude Code Test" })
end, { desc = "Test Claude Code functionality" })

-- Show debug log command
vim.api.nvim_create_user_command("ClaudeDebugLog", function()
  local log_file = vim.g.claude_code_debug_log_file
  if log_file and vim.fn.filereadable(log_file) == 1 then
    vim.cmd("vsplit " .. log_file)
    vim.cmd("normal! G")
  else
    Snacks.notify.warn("No debug log file found", { title = "Claude Code" })
  end
end, { desc = "Show Claude Code debug log" })

-- Show recent events in a floating window
vim.api.nvim_create_user_command("ClaudeRecentEvents", function()
  local events_store = vim.g.claude_recent_events or {}
  if #events_store == 0 then
    Snacks.notify.warn("No recent events captured", { title = "Claude Code" })
    return
  end
  
  -- Format events for display
  local lines = { "=== Recent Claude Code Events ===" }
  for _, event in ipairs(events_store) do
    table.insert(lines, "")
    table.insert(lines, string.format("[%s] %s", event.timestamp, event.name))
    if event.data then
      local data_lines = vim.split(vim.inspect(event.data, {indent = "  "}), "\n")
      for _, line in ipairs(data_lines) do
        table.insert(lines, "  " .. line)
      end
    end
  end
  
  -- Create floating window using Snacks
  Snacks.win({
    buf = vim.api.nvim_create_buf(false, true),
    enter = true,
    wo = {
      wrap = true,
      linebreak = true,
      cursorline = true,
    },
    keys = {
      q = "close",
      ["<Esc>"] = "close",
    },
  }):map("n", "q", "close"):show({
    title = " Recent Claude Code Events ",
    width = 80,
    height = math.min(#lines + 2, 30),
    border = "rounded",
  }):lines(lines)
end, { desc = "Show recent Claude Code events" })

-- Store recent events for debugging
vim.g.claude_recent_events = {}
local max_events = 50

vim.api.nvim_create_autocmd("User", {
  pattern = "ClaudeCode:*",
  callback = function(args)
    local events_store = vim.g.claude_recent_events or {}
    table.insert(events_store, 1, {
      name = args.match:gsub("^ClaudeCode:", ""),
      data = args.data,
      timestamp = os.date("%H:%M:%S")
    })
    -- Keep only the most recent events
    while #events_store > max_events do
      table.remove(events_store)
    end
    vim.g.claude_recent_events = events_store
  end,
  desc = "Store recent events for debugging"
})

-- Watch events in real-time
local event_buffer = nil
vim.api.nvim_create_user_command("ClaudeEventsWatch", function()
  -- Create or reuse buffer
  if not event_buffer or not vim.api.nvim_buf_is_valid(event_buffer) then
    event_buffer = vim.api.nvim_create_buf(false, true)
    vim.bo[event_buffer].buftype = "nofile"
    vim.bo[event_buffer].bufhidden = "hide"
    vim.bo[event_buffer].swapfile = false
  end
  
  -- Clear and set initial content
  vim.api.nvim_buf_set_lines(event_buffer, 0, -1, false, {
    "=== Claude Code Event Monitor ===",
    "Watching for events...",
    "",
  })
  
  -- Open in a split
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, event_buffer)
  
  -- Set up autocmd to scroll to bottom
  vim.api.nvim_create_autocmd("TextChanged", {
    buffer = event_buffer,
    callback = function()
      local win = vim.fn.bufwinid(event_buffer)
      if win ~= -1 then
        vim.api.nvim_win_set_cursor(win, {vim.api.nvim_buf_line_count(event_buffer), 0})
      end
    end
  })
  
  -- Listen to all events and add to buffer
  vim.api.nvim_create_autocmd("User", {
    pattern = "ClaudeCode:*",
    callback = function(args)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(event_buffer) then
          local timestamp = os.date("%H:%M:%S")
          local event_name = args.match:gsub("^ClaudeCode:", "")
          local lines = {
            string.format("[%s] %s", timestamp, event_name),
          }
          
          -- Add data if present
          if args.data then
            local data_str = vim.inspect(args.data, {indent = "  "})
            for line in data_str:gmatch("[^\n]+") do
              table.insert(lines, "  " .. line)
            end
          end
          
          table.insert(lines, "") -- Empty line for separation
          
          -- Append to buffer
          vim.api.nvim_buf_set_lines(event_buffer, -1, -1, false, lines)
        end
      end)
    end,
    desc = "Watch all ClaudeCode events"
  })
  
  Snacks.notify.info("Watching Claude Code events...", { title = "Event Monitor" })
end, { desc = "Watch Claude Code events in real-time" })

-- Autocommand to stop server on exit
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    require("claude-code").stop()
  end,
})

-- Test WebSocket connection
vim.api.nvim_create_user_command("ClaudeTestConnection", function()
  local server = require("claude-code.server").get_server()
  if not server then
    Snacks.notify.error("Server not running!", { title = "Claude Code" })
    return
  end
  
  -- Create a test WebSocket client
  local port = server.port
  local auth_token = server.auth_token
  
  Snacks.notify.info(
    string.format("Testing connection to localhost:%d with token: %s", port, auth_token),
    { title = "Connection Test" }
  )
  
  -- Try to connect using curl to test the WebSocket endpoint
  local cmd = string.format(
    "curl -i -N -H 'Connection: Upgrade' -H 'Upgrade: websocket' " ..
    "-H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: test123=' " ..
    "-H 'x-claude-code-ide-authorization: %s' " ..
    "http://localhost:%d/",
    auth_token, port
  )
  
  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data and #data > 0 then
        local response = table.concat(data, "\n")
        if response:match("101 Switching Protocols") then
          Snacks.notify.info("WebSocket handshake successful!", { title = "Connection Test" })
        else
          Snacks.notify.warn("Unexpected response: " .. response:sub(1, 100), { title = "Connection Test" })
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        Snacks.notify.error("Connection error: " .. table.concat(data, "\n"), { title = "Connection Test" })
      end
    end,
  })
end, { desc = "Test WebSocket connection to Claude Code server" })

-- Welcome message
vim.defer_fn(function()
  print("Claude Code example loaded! Press <leader>ci to see server info")
  print("Try <leader>cn to start a new Claude CLI session")
  print("Try <leader>cc to open the conversation window")
  print("Use :ClaudeTest to test the tool system")
  print("Use :ClaudeTestConnection to test WebSocket connection")
  print("Use :ClaudeRecentEvents to see recent events")
  print("Use :ClaudeDebugLog to view WebSocket debug log")
  print("Debug log: ~/claude-code-debug.log")
end, 100)