-- JSON-RPC 2.0 handler for MCP protocol
-- Handles incoming RPC messages and dispatches to appropriate handlers

local json = vim.json
local events = require("claude-code.events")
local log = require("claude-code.log")

local M = {}

-- RPC instance
local RPC = {}
RPC.__index = RPC

function RPC.new(connection)
	local self = setmetatable({}, RPC)
	self.connection = connection
	self.server = connection.server
	self.handlers = {}

	-- Register MCP method handlers
	self:_register_handlers()

	return self
end

-- Register all MCP method handlers
function RPC:_register_handlers()
	-- Initialize method
	self.handlers["initialize"] = function(params)
		return self:_handle_initialize(params)
	end

	-- Initialized notification
	self.handlers["notifications/initialized"] = function(params)
		return self:_handle_initialized(params)
	end

	-- Tool methods
	self.handlers["tools/list"] = function(params)
		return self:_handle_tools_list(params)
	end

	self.handlers["tools/call"] = function(params)
		return self:_handle_tools_call(params)
	end

	-- Resource methods
	self.handlers["resources/list"] = function(params)
		return self:_handle_resources_list(params)
	end

	self.handlers["resources/read"] = function(params)
		return self:_handle_resources_read(params)
	end

	-- Notification handlers (no response expected)
	self.handlers["notifications/initialized"] = function(params)
		self:_handle_initialized(params)
	end
end

-- Process incoming JSON-RPC message
---@param data string Raw JSON data
function RPC:process_message(data)
	local ok, message = pcall(json.decode, data)
	if not ok then
		return self:_error_response(nil, -32700, "Parse error")
	end

	-- Emit message received event
	events.emit(events.events.MESSAGE_RECEIVED, {
		raw = data,
		message = message,
	})

	-- Handle batch requests
	if vim.tbl_islist(message) then
		return self:_process_batch(message)
	end

	-- Single request
	return self:_process_single(message)
end

-- Process single RPC request
function RPC:_process_single(message)
	-- Validate JSON-RPC format
	if message.jsonrpc ~= "2.0" then
		return self:_error_response(message.id, -32600, "Invalid Request")
	end

	-- Check if server is initialized for non-init methods
	if
		not self.server.initialized
		and message.method ~= "initialize"
		and message.method ~= "notifications/initialized"
	then
		return self:_error_response(message.id, -32002, "Server not initialized")
	end

	-- Emit request started event
	if message.id then
		events.emit(events.events.REQUEST_STARTED, {
			id = message.id,
			method = message.method,
			params = message.params,
		})
	end

	-- Find handler
	local handler = self.handlers[message.method]
	if not handler then
		local error_response = self:_error_response(message.id, -32601, "Method not found")
		if message.id then
			events.emit(events.events.REQUEST_FAILED, {
				id = message.id,
				method = message.method,
				error = error_response.error,
			})
		end
		return error_response
	end

	-- Execute handler
	local ok, result = pcall(handler, message.params or {})
	if not ok then
		local error_response = self:_error_response(message.id, -32603, "Internal error: " .. tostring(result))
		if message.id then
			events.emit(events.events.REQUEST_FAILED, {
				id = message.id,
				method = message.method,
				error = error_response.error,
			})
		end
		return error_response
	end

	-- Emit request completed event
	if message.id then
		events.emit(events.events.REQUEST_COMPLETED, {
			id = message.id,
			method = message.method,
			result = result,
		})
	end

	-- Notifications don't get responses
	if not message.id then
		return nil
	end

	-- Return successful response
	return {
		jsonrpc = "2.0",
		result = result,
		id = message.id,
	}
end

-- Process batch of requests
function RPC:_process_batch(messages)
	local responses = {}

	for _, message in ipairs(messages) do
		local response = self:_process_single(message)
		if response then
			table.insert(responses, response)
		end
	end

	return responses
end

-- Create error response
function RPC:_error_response(id, code, message)
	return {
		jsonrpc = "2.0",
		error = {
			code = code,
			message = message,
		},
		id = id,
	}
end

-- Handle initialize request
function RPC:_handle_initialize(params)
	-- Validate protocol version
	if params.protocolVersion ~= "2025-06-18" then
		error("Unsupported protocol version: " .. (params.protocolVersion or "none"))
	end

	-- Return server capabilities
	return {
		protocolVersion = "2025-06-18",
		capabilities = self.server.capabilities,
		serverInfo = self.server.server_info,
		instructions = "Neovim MCP server for Claude integration",
	}
end

-- Handle initialized notification
function RPC:_handle_initialized(params)
	self.server.initialized = true
	events.emit(events.events.INITIALIZED, {
		server = self.server:get_info(),
	})
	vim.notify("MCP client initialized", vim.log.levels.DEBUG)
end

-- Handle tools/list request
function RPC:_handle_tools_list(params)
	local tools = require("claude-code.tools")
	return {
		tools = tools.list(),
	}
end

-- Handle tools/call request
function RPC:_handle_tools_call(params)
	local tools = require("claude-code.tools")

	-- Validate parameters
	if not params.name then
		error("Missing tool name")
	end

	-- Emit tool executing event
	events.emit(events.events.TOOL_EXECUTING, {
		tool_name = params.name,
		arguments = params.arguments,
	})

	-- Execute tool
	local ok, result = pcall(tools.execute, params.name, params.arguments or {})

	if not ok then
		-- Emit tool failed event
		events.emit(events.events.TOOL_FAILED, {
			tool_name = params.name,
			arguments = params.arguments,
			error = tostring(result),
		})
		error(result)
	end

	-- Emit tool executed event
	events.emit(events.events.TOOL_EXECUTED, {
		tool_name = params.name,
		arguments = params.arguments,
		result = result,
	})

	return result
end

-- Handle resources/list request
function RPC:_handle_resources_list(params)
	-- TODO: Implement resource listing
	return {
		resources = {},
	}
end

-- Handle resources/read request
function RPC:_handle_resources_read(params)
	-- TODO: Implement resource reading
	error("Resources not implemented yet")
end

-- Send response to client
function RPC:send_response(response)
	if not response then
		return
	end

	log.debug("RPC", "Sending response", response)

	local data = json.encode(response)
	local websocket = require("claude-code.server.websocket")
	websocket.send_text(self.connection, data)
end

-- Module functions
function M.new(connection)
	return RPC.new(connection)
end

return M
