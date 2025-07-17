-- RPC method handler registry

local M = {}

-- Handler registry
local handlers = {}
local notification_handlers = {}

-- Register all handlers
function M.setup()
	-- Core handlers
	-- Initialize handler is defined in this module (see bottom)

	-- These handlers are for non-MCP legacy methods
	-- In MCP, all tool calls should go through tools/call
	-- But we keep these for backward compatibility if needed

	-- NOTE: The following are legacy handlers, not part of MCP protocol
	-- local file = require("claude-code-ide.rpc.handlers.file")
	-- handlers["openFile"] = file.open_file
	-- handlers["openDiff"] = file.open_diff

	-- local diagnostics = require("claude-code-ide.rpc.handlers.diagnostics")
	-- handlers["getDiagnostics"] = diagnostics.get_diagnostics

	-- local selection = require("claude-code-ide.rpc.handlers.selection")
	-- handlers["getCurrentSelection"] = selection.get_current_selection

	-- local workspace = require("claude-code-ide.rpc.handlers.workspace")
	-- handlers["getOpenEditors"] = workspace.get_open_editors
	-- handlers["getWorkspaceFolders"] = workspace.get_workspace_folders
	-- handlers["workspace/executeCommand"] = workspace.execute_command
	-- handlers["workspace/applyEdit"] = workspace.apply_edit

	-- local window = require("claude-code-ide.rpc.handlers.window")
	-- handlers["window/visibleRanges"] = window.get_visible_ranges

	-- MCP Tools handlers
	local tools = require("claude-code-ide.rpc.handlers.tools")
	handlers["tools/list"] = tools.list_tools
	handlers["tools/call"] = tools.call_tool

	-- IDE-specific handlers (non-standard MCP extensions)
	local ide = require("claude-code-ide.rpc.handlers.ide")
	handlers["ide_connected"] = ide.ide_connected

	-- MCP Resources handlers
	local resources = require("claude-code-ide.rpc.handlers.resources")
	handlers["resources/list"] = resources.list_resources
	handlers["resources/read"] = resources.read_resource

	-- Notification handlers
	notification_handlers["initialized"] = function() end -- No-op
	notification_handlers["notifications/initialized"] = function() end -- MCP protocol initialized notification
	-- TODO: Implement text document notifications when needed
	-- notification_handlers["textDocument/didOpen"] = function() end
	-- notification_handlers["textDocument/didChange"] = function() end
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

	-- Mark session as initialized
	if rpc.session_id then
		rpc.session.set_initialized(rpc.session_id)
		rpc.session.set_session_data(rpc.session_id, "protocol_version", rpc.protocol_version)
		rpc.session.set_session_data(rpc.session_id, "client_info", params.clientInfo)
	end

	-- Return server capabilities
	return {
		protocolVersion = rpc.protocol_version,
		capabilities = {
			tools = { listChanged = true },
			resources = { listChanged = true },
		},
		serverInfo = {
			name = "claude-code-ide.nvim",
			version = "0.1.0",
		},
		instructions = "Neovim MCP server for Claude integration",
	}
end

handlers["initialize"] = M.initialize

return M
