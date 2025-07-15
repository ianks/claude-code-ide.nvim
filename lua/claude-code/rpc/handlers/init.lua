-- RPC method handler registry

local M = {}

-- Handler registry
local handlers = {}
local notification_handlers = {}

-- Register all handlers
function M.setup()
	-- Core handlers
	handlers["initialize"] = require("claude-code.rpc.handlers.initialize")

	-- These handlers are for non-MCP legacy methods
	-- In MCP, all tool calls should go through tools/call
	-- But we keep these for backward compatibility if needed

	-- NOTE: The following are legacy handlers, not part of MCP protocol
	-- local file = require("claude-code.rpc.handlers.file")
	-- handlers["openFile"] = file.open_file
	-- handlers["openDiff"] = file.open_diff

	-- local diagnostics = require("claude-code.rpc.handlers.diagnostics")
	-- handlers["getDiagnostics"] = diagnostics.get_diagnostics

	-- local selection = require("claude-code.rpc.handlers.selection")
	-- handlers["getCurrentSelection"] = selection.get_current_selection

	-- local workspace = require("claude-code.rpc.handlers.workspace")
	-- handlers["getOpenEditors"] = workspace.get_open_editors
	-- handlers["getWorkspaceFolders"] = workspace.get_workspace_folders
	-- handlers["workspace/executeCommand"] = workspace.execute_command
	-- handlers["workspace/applyEdit"] = workspace.apply_edit

	-- local window = require("claude-code.rpc.handlers.window")
	-- handlers["window/visibleRanges"] = window.get_visible_ranges

	-- MCP Tools handlers
	local tools = require("claude-code.rpc.handlers.tools")
	handlers["tools/list"] = tools.list_tools
	handlers["tools/call"] = tools.call_tool

	-- IDE-specific handlers (non-standard MCP extensions)
	local ide = require("claude-code.rpc.handlers.ide")
	handlers["ide_connected"] = ide.ide_connected

	-- MCP Resources handlers
	local resources = require("claude-code.rpc.handlers.resources")
	handlers["resources/list"] = resources.list_resources
	handlers["resources/read"] = resources.read_resource

	-- Notification handlers
	notification_handlers["initialized"] = function() end -- No-op
	notification_handlers["notifications/initialized"] = function() end -- MCP protocol initialized notification
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
		instructions = "Neovim MCP server for Claude integration",
	}
end

handlers["initialize"] = M.initialize

return M
