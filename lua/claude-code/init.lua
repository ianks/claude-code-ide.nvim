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

  -- Load configuration
  local config = require("claude-code.config")
  M._state.config = config.setup(opts)

  -- Initialize server
  local server = require("claude-code.server")
  M._state.server = server.start(M._state.config)

  -- Setup commands
  require("claude-code.api.commands").setup()

  M._state.initialized = true
end

-- Stop the server
function M.stop()
  if M._state.server then
    M._state.server:stop()
    M._state.server = nil
  end
  M._state.initialized = false
end

-- Get current status
function M.status()
  return {
    initialized = M._state.initialized,
    server_running = M._state.server and M._state.server:is_running() or false,
    config = M._state.config,
  }
end

return M