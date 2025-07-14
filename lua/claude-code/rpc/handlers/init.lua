-- RPC method handler registry

local M = {}

-- Handler registry
local handlers = {}
local notification_handlers = {}

-- Register all handlers
function M.setup()
  -- Core handlers
  handlers["initialize"] = require("claude-code.rpc.handlers.initialize")
  
  -- File handlers
  local file = require("claude-code.rpc.handlers.file")
  handlers["openFile"] = file.open_file
  handlers["openDiff"] = file.open_diff
  
  -- Diagnostic handlers
  local diagnostics = require("claude-code.rpc.handlers.diagnostics")
  handlers["getDiagnostics"] = diagnostics.get_diagnostics
  
  -- Selection handlers
  local selection = require("claude-code.rpc.handlers.selection")
  handlers["getCurrentSelection"] = selection.get_current_selection
  
  -- Workspace handlers
  local workspace = require("claude-code.rpc.handlers.workspace")
  handlers["getOpenEditors"] = workspace.get_open_editors
  handlers["getWorkspaceFolders"] = workspace.get_workspace_folders
  handlers["workspace/executeCommand"] = workspace.execute_command
  handlers["workspace/applyEdit"] = workspace.apply_edit
  
  -- Window handlers
  local window = require("claude-code.rpc.handlers.window")
  handlers["window/visibleRanges"] = window.get_visible_ranges
  
  -- Notification handlers
  notification_handlers["initialized"] = function() end -- No-op
  notification_handlers["textDocument/didOpen"] = require("claude-code.rpc.notifications").did_open
  notification_handlers["textDocument/didChange"] = require("claude-code.rpc.notifications").did_change
end

-- Get handler for method
---@param method string Method name
---@return function? handler
function M.get_handler(method)
  if vim.tbl_isempty(handlers) then
    M.setup()
  end
  return handlers[method]
end

-- Get notification handler for method
---@param method string Method name
---@return function? handler
function M.get_notification_handler(method)
  if vim.tbl_isempty(notification_handlers) then
    M.setup()
  end
  return notification_handlers[method]
end

-- Initialize handler (special case)
---@param rpc table RPC instance
---@param params table Initialize parameters
---@return table result
function M.initialize(rpc, params)
  -- Store protocol version
  rpc.protocol_version = params.protocolVersion or "2025-06-18"
  
  -- Return server capabilities
  return {
    protocolVersion = rpc.protocol_version,
    capabilities = {
      tools = { listChanged = true },
      resources = { listChanged = true },
    },
    serverInfo = {
      name = "claude-code.nvim",
      version = "0.1.0",
    },
    instructions = "Welcome to Claude Code for Neovim!",
  }
end

handlers["initialize"] = M.initialize

return M