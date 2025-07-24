-- JSON-RPC 2.0 dispatcher for claude-code-ide.nvim

local log = require("claude-code-ide.log")
local async = require("plenary.async")

-- Configuration constants
local CONFIG = {
	REQUEST_TIMEOUT_MS = 30000,
	MAX_PENDING_REQUESTS = 100,
	SESSION_ID_LENGTH = 16,
}

local M = {}
M.__index = M

-- Generate secure session ID
local function generate_session_id()
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local result = {}
	math.randomseed(os.time() + os.clock() * 1000000)

	for i = 1, CONFIG.SESSION_ID_LENGTH do
		local rand = math.random(#chars)
		result[i] = chars:sub(rand, rand)
	end

	return table.concat(result)
end

-- Validate critical dependencies only
local function validate_dependencies()
	local required = {
		"claude-code-ide.rpc.handlers",
		"claude-code-ide.rpc.protocol",
	}

	for _, module in ipairs(required) do
		local ok = pcall(require, module)
		if not ok then
			error("Missing required dependency: " .. module)
		end
	end
end

-- Create new RPC handler
---@param connection table WebSocket connection
---@return table rpc RPC handler instance
function M.new(connection, send_callback)
	validate_dependencies()

	local self = setmetatable({}, M)
	self.connection = connection
	self.handlers = require("claude-code-ide.rpc.handlers")
	self.protocol = require("claude-code-ide.rpc.protocol")
	self._send_callback = send_callback

	-- Optional dependencies (graceful degradation)
	local ok, session = pcall(require, "claude-code-ide.session")
	self.session = ok and session or nil

	self.pending_requests = {}
	self.next_id = 1
	self.session_id = connection and connection.id or generate_session_id()

	-- Initialize request cleanup timer
	self:_setup_cleanup_timer()

	return self
end

-- Setup cleanup timer for expired requests
function M:_setup_cleanup_timer()
	local timer = vim.loop.new_timer()
	timer:start(
		5000,
		5000,
		vim.schedule_wrap(function()
			self:_cleanup_expired_requests()
		end)
	)
	self.cleanup_timer = timer
end

-- Cleanup expired pending requests
function M:_cleanup_expired_requests()
	local now = vim.loop.hrtime() / 1000000 -- Convert to milliseconds
	local expired = {}

	for id, request in pairs(self.pending_requests) do
		if now - request.timestamp > CONFIG.REQUEST_TIMEOUT_MS then
			table.insert(expired, id)
		end
	end

	for _, id in ipairs(expired) do
		local request = self.pending_requests[id]
		self.pending_requests[id] = nil
		request.reject({ code = -32603, message = "Request timeout" })
	end
end

-- Cleanup resources
function M:cleanup()
	if self.cleanup_timer then
		self.cleanup_timer:stop()
		self.cleanup_timer:close()
		self.cleanup_timer = nil
	end

	-- Reject all pending requests
	for id, request in pairs(self.pending_requests) do
		request.reject({ code = -32603, message = "Connection closed" })
	end
	self.pending_requests = {}
end

-- Process incoming JSON-RPC message with full error boundary
---@param message string Raw JSON message
function M:process_message(message)
	local success, error_msg = pcall(self._process_message_internal, self, message)
	if not success then
		log.error("RPC", "Critical error processing message", { error = error_msg })
		self:_send_error(nil, self.protocol.errors.INTERNAL_ERROR, "Internal server error")
	end
end

-- Internal message processing with validation
---@param message string Raw JSON message
function M:_process_message_internal(message)
	-- Validate input
	if type(message) ~= "string" or #message == 0 then
		self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Empty or invalid message")
		return
	end

	if #message > 1024 * 1024 then -- 1MB limit
		self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Message too large")
		return
	end

	local ok, request = pcall(vim.json.decode, message)
	if not ok then
		self:_send_error(nil, self.protocol.errors.PARSE_ERROR, "JSON parse error")
		return
	end

	-- Validate JSON-RPC structure
	if not self.protocol.validate_message(request) then
		self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Invalid JSON-RPC structure")
		return
	end

	-- Route message by type
	if request.method and request.id then
		self:_handle_request(request)
	elseif request.method and not request.id then
		self:_handle_notification(request)
	elseif request.result or request.error then
		self:_handle_response(request)
	else
		self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Unknown message type")
	end
end

-- Handle request with error boundary
---@param request table JSON-RPC request
function M:_handle_request(request)
	-- Validate method name
	if not request.method or type(request.method) ~= "string" or #request.method == 0 then
		self:_send_error(request.id, self.protocol.errors.INVALID_REQUEST, "Invalid method name")
		return
	end

	local handler = self.handlers.get_handler(request.method)
	if not handler then
		self:_send_error(request.id, self.protocol.errors.METHOD_NOT_FOUND, "Method not found: " .. request.method)
		return
	end

	-- For tool calls, delegate to the job system
	if request.method == "tools/call" then
		-- Create a job for this tool call
		-- The job will handle sending the response
		handler(self, request.params or {}, request.id)
		return
	end

	-- For non-tool methods, handle synchronously as before
	local ok, result = pcall(handler, self, request.params or {})

	if ok then
		log.info("RPC", "Handler result", {
			method = request.method,
			result_type = type(result),
			has_result = result ~= nil,
		})

		local validated_result = self.protocol.validate_result(result)
		self:_send_response(request.id, validated_result)
	else
		local error_msg = tostring(result)
		log.error("RPC", "Handler error", { method = request.method, error = error_msg })
		self:_send_error(request.id, self.protocol.errors.INTERNAL_ERROR, error_msg)
	end
end

-- Handle notification with error boundary
---@param notification table JSON-RPC notification
function M:_handle_notification(notification)
	local handler = self.handlers.get_notification_handler(notification.method)
	if handler then
		local ok, err = pcall(handler, self, notification.params or {})
		if not ok then
			log.warn("RPC", "Notification handler error", { method = notification.method, error = tostring(err) })
		end
	end
end

-- Handle response message
---@param response table JSON-RPC response
function M:_handle_response(response)
	local pending = self.pending_requests[response.id]
	if pending then
		self.pending_requests[response.id] = nil

		if response.error then
			pending.reject(response.error)
		else
			pending.resolve(response.result)
		end
	end
end

-- Send request to client with timeout
---@param method string Method name
---@param params table? Method parameters
---@return table promise Promise that resolves to response
function M:request(method, params)
	return async.wrap(function(callback)
		-- Check pending request limit
		if vim.tbl_count(self.pending_requests) >= CONFIG.MAX_PENDING_REQUESTS then
			callback({ code = -32603, message = "Too many pending requests" }, nil)
			return
		end

		local id = self.next_id
		self.next_id = self.next_id + 1

		local request = self.protocol.create_request(id, method, params)

		self.pending_requests[id] = {
			timestamp = vim.loop.hrtime() / 1000000,
			resolve = function(result)
				callback(nil, result)
			end,
			reject = function(error)
				callback(error, nil)
			end,
		}

		local ok, err = pcall(self._send, self, request)
		if not ok then
			self.pending_requests[id] = nil
			callback({ code = -32603, message = "Send failed: " .. tostring(err) }, nil)
		end
	end, 1)()
end

-- Send notification to client
---@param method string Method name
---@param params table? Method parameters
function M:notify(method, params)
	local notification = self.protocol.create_notification(method, params)
	pcall(self._send, self, notification)
end

-- Send progress notification
---@param token string|number Progress token
---@param progress number Progress value (0-100)
---@param message string? Optional progress message
function M:notify_progress(token, progress, message)
	self:notify("notifications/progress", {
		progressToken = token,
		progress = progress,
		total = 100,
		message = message,
	})
end

-- Start a progress operation
---@param token string|number Progress token
---@param message string Initial message
function M:start_progress(token, message)
	self:notify_progress(token, 0, message)
end

-- Update progress
---@param token string|number Progress token
---@param progress number Progress value (0-100)
---@param message string? Optional progress message
function M:update_progress(token, progress, message)
	self:notify_progress(token, progress, message)
end

-- Complete a progress operation
---@param token string|number Progress token
---@param message string? Final message
function M:complete_progress(token, message)
	self:notify_progress(token, 100, message or "Complete")
end

-- Send response
---@param id number Request ID
---@param result any Response result
function M:_send_response(id, result)
	local response = self.protocol.create_response(id, result)
	pcall(self._send, self, response)
end

-- Send error response
---@param id number? Request ID
---@param code number Error code
---@param message string Error message
function M:_send_error(id, code, message)
	local response = self.protocol.create_error_response(id, code, message)
	pcall(self._send, self, response)
end

-- Send message over WebSocket
---@param message table Message to send
function M:_send(message)
	if not self._send_callback then
		log.error("RPC", "Cannot send message, no send_callback configured.")
		return
	end

	local json = vim.json.encode(message)

	log.debug("RPC", "Sending message", {
		method = message.method,
		id = message.id,
		size = #json,
	})

	self._send_callback(self.connection, json)
end

return M
