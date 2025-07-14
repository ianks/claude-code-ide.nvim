-- claude-code.nvim main module
-- Integration between Claude AI and Neovim

local M = {}

-- Module state
M._state = {
  initialized = false,
  server = nil,
  config = nil,
}

-- Setup function
---@param opts table? User configuration
function M.setup(opts)
  if M._state.initialized then
    vim.notify("claude-code.nvim: Already initialized", vim.log.levels.WARN)
    return
  end

  -- Default configuration
  M._state.config = vim.tbl_deep_extend("force", {
    port = 0,
    host = "127.0.0.1",
    debug = false,
    lock_file_dir = vim.fn.expand("~/.claude/ide"),
    server_name = "claude-code.nvim",
    server_version = "0.1.0",
  }, opts or {})

  -- Set debug log file globally if provided
  if M._state.config.debug_log_file then
    vim.g.claude_code_debug_log_file = M._state.config.debug_log_file
  end

  M._state.initialized = true
end

-- Start the server
function M.start()
  if not M._state.initialized then
    vim.notify("claude-code.nvim: Call setup() first", vim.log.levels.ERROR)
    return
  end

  -- Initialize server
  local server = require("claude-code.server")
  M._state.server = server.start(M._state.config)
  
  -- Setup commands if they exist
  local ok, commands = pcall(require, "claude-code.api.commands")
  if ok then
    commands.setup()
  end
  
  return M._state.server
end

-- Stop the server
function M.stop()
  local server = require("claude-code.server")
  server.stop()
  M._state.server = nil
end

-- Get current status
function M.status()
  local server = require("claude-code.server").get_server()
  return {
    initialized = M._state.initialized,
    server_running = server and server.running or false,
    config = M._state.config,
  }
end

return M