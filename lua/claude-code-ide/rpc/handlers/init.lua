-- RPC method handler registry with improved error handling

local log = require("claude-code-ide.log")

local M = {}

-- Configuration constants
local CONFIG = {
	DEFAULT_PROTOCOL_VERSION = "2025-06-18",
	SERVER_NAME = "claude-code-ide.nvim",
	SERVER_VERSION = "0.1.0",
}

-- Handler registry
local handlers = {}
local notification_handlers = {}

-- Validate handler function
---@param handler function Handler function to validate
---@return boolean valid
local function validate_handler(handler)
	return type(handler) == "function"
end

-- Register all handlers with validation
function M.setup()
	log.debug("RPC", "Setting up handler registry")

	-- Clear existing handlers
	handlers = {}
	notification_handlers = {}

	-- Core MCP protocol handlers
	local tools_ok, tools = pcall(require, "claude-code-ide.rpc.handlers.tools")
	if tools_ok then
		if validate_handler(tools.list_tools) then
			handlers["tools/list"] = tools.list_tools
		end
		if validate_handler(tools.call_tool) then
			handlers["tools/call"] = tools.call_tool
		end
	else
		log.warn("RPC", "Failed to load tools handler", { error = tools })
	end

	-- MCP Resources handlers
	local resources_ok, resources = pcall(require, "claude-code-ide.rpc.handlers.resources")
	if resources_ok then
		if validate_handler(resources.list_resources) then
			handlers["resources/list"] = resources.list_resources
		end
		if validate_handler(resources.read_resource) then
			handlers["resources/read"] = resources.read_resource
		end
	else
		log.warn("RPC", "Failed to load resources handler", { error = resources })
	end

	-- Core protocol handler
	handlers["initialize"] = M.initialize

	-- IDE-specific notification handlers (based on real-world logs)
	local ide_ok, ide = pcall(require, "claude-code-ide.rpc.handlers.ide")
	if ide_ok then
		if validate_handler(ide.ide_connected) then
			-- ide_connected is a NOTIFICATION in real-world logs, not a request
			notification_handlers["ide_connected"] = ide.ide_connected
		end
	else
		log.warn("RPC", "Failed to load IDE handler", { error = ide })
	end

	-- Standard MCP notification handlers
	notification_handlers["initialized"] = function()
		log.debug("RPC", "Client initialized")
	end

	notification_handlers["notifications/initialized"] = function()
		log.debug("RPC", "MCP protocol initialized")
	end

	-- Real-world notification handlers observed in logs
	notification_handlers["selection_changed"] = function(rpc, params)
		log.debug("RPC", "Selection changed", {
			file = params and params.filePath,
			is_empty = params and params.selection and params.selection.isEmpty,
		})
		-- Emit selection change event for other parts of the system
		local events = require("claude-code-ide.events")
		pcall(events.emit, "SelectionChanged", params)
	end

	notification_handlers["log_event"] = function(rpc, params)
		log.debug("RPC", "Log event received", params)
		-- Forward log events to our logging system
		if params and params.eventName then
			local events = require("claude-code-ide.events")
			pcall(events.emit, "LogEvent", params)
		end
	end

	notification_handlers["diagnostics_changed"] = function(rpc, params)
		log.debug("RPC", "Diagnostics changed", {
			uris = params and params.uris and #params.uris or 0,
		})
		-- Forward diagnostics changes to the system
		local events = require("claude-code-ide.events")
		pcall(events.emit, "DiagnosticsChanged", params)
	end

	log.debug("RPC", "Handler registry setup complete", {
		handlers = vim.tbl_count(handlers),
		notifications = vim.tbl_count(notification_handlers),
	})
end

-- Get handler for method with validation
---@param method string Method name
---@return function? handler
function M.get_handler(method)
	if not method or type(method) ~= "string" then
		log.warn("RPC", "Invalid method name provided", { method = method })
		return nil
	end

	if vim.tbl_isempty(handlers) then
		M.setup()
	end

	local handler = handlers[method]
	if not handler then
		log.debug("RPC", "No handler found for method", { method = method })
	end

	return handler
end

-- Get notification handler for method with validation
---@param method string Method name
---@return function? handler
function M.get_notification_handler(method)
	if not method or type(method) ~= "string" then
		log.warn("RPC", "Invalid notification method name", { method = method })
		return nil
	end

	if vim.tbl_isempty(notification_handlers) then
		M.setup()
	end

	return notification_handlers[method]
end

-- Validate initialize parameters
---@param params table Initialize parameters
---@return boolean valid, string? error_message
local function validate_initialize_params(params)
	if type(params) ~= "table" then
		return false, "Initialize params must be a table"
	end

	-- Protocol version is optional but should be string if provided
	if params.protocolVersion and type(params.protocolVersion) ~= "string" then
		return false, "protocolVersion must be a string"
	end

	-- Client info is optional but should be table if provided
	if params.clientInfo and type(params.clientInfo) ~= "table" then
		return false, "clientInfo must be a table"
	end

	return true, nil
end

-- Initialize handler with enhanced validation matching real-world interactions
---@param rpc table RPC instance
---@param params table Initialize parameters
---@return table result
function M.initialize(rpc, params)
	log.debug("RPC", "Initialize request received", params)

	-- Validate parameters
	local valid, error_msg = validate_initialize_params(params)
	if not valid then
		error("Invalid initialize parameters: " .. error_msg)
	end

	-- Validate RPC instance
	if not rpc or not rpc.connection then
		error("Invalid RPC instance provided")
	end

	-- Store protocol version with fallback (real-world uses "2025-06-18")
	rpc.protocol_version = params.protocolVersion or CONFIG.DEFAULT_PROTOCOL_VERSION

	-- Initialize session if session management is available
	if rpc.session_id and rpc.session then
		local session_ok, session_err = pcall(function()
			rpc.session.set_initialized(rpc.session_id)
			rpc.session.set_session_data(rpc.session_id, "protocol_version", rpc.protocol_version)
			if params.clientInfo then
				rpc.session.set_session_data(rpc.session_id, "client_info", params.clientInfo)
			end
		end)

		if not session_ok then
			log.warn("RPC", "Failed to initialize session", { error = session_err })
		end
	end

	-- Build capabilities response - MUST include both tools AND resources per real-world logs
	local capabilities = {
		tools = { listChanged = true },
		resources = { listChanged = true },
	}

	local result = {
		protocolVersion = rpc.protocol_version,
		capabilities = capabilities,
		serverInfo = {
			name = CONFIG.SERVER_NAME,
			version = CONFIG.SERVER_VERSION,
		},
		instructions = "Neovim MCP server for Claude integration",
	}

	log.debug("RPC", "Initialize successful", {
		protocol_version = rpc.protocol_version,
		session_id = rpc.session_id,
	})

	return result
end

return M
