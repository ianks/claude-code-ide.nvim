-- JSON-RPC 2.0 protocol implementation with enhanced validation

local M = {}

-- Protocol configuration constants
local CONFIG = {
	VERSION = "2.0",
	MAX_METHOD_LENGTH = 128,
	MAX_ERROR_MESSAGE_LENGTH = 512,
}

-- JSON-RPC 2.0 error codes
M.errors = {
	PARSE_ERROR = -32700,
	INVALID_REQUEST = -32600,
	METHOD_NOT_FOUND = -32601,
	INVALID_PARAMS = -32602,
	INTERNAL_ERROR = -32603,
}

-- Protocol version
M.VERSION = CONFIG.VERSION

-- Validate method name
---@param method string Method name to validate
---@return boolean valid
local function validate_method_name(method)
	return type(method) == "string"
		and #method > 0
		and #method <= CONFIG.MAX_METHOD_LENGTH
		and method:match("^[%w_/.-]+$") -- Allow alphanumeric, underscore, slash, dot, dash
end

-- Validate JSON-RPC message structure
---@param message table Message to validate
---@return boolean valid
function M.validate_message(message)
	-- Must be a table
	if type(message) ~= "table" then
		return false
	end

	-- Must have correct jsonrpc version
	if message.jsonrpc ~= M.VERSION then
		return false
	end

	-- Request/notification: must have valid method
	if message.method then
		if not validate_method_name(message.method) then
			return false
		end

		-- If it has an id, it's a request; if not, it's a notification
		return true
	end

	-- Response: must have result or error and an id
	if message.result ~= nil or message.error ~= nil then
		return message.id ~= nil
	end

	return false
end

-- Validate and sanitize result data
---@param result any Result to validate
---@return any sanitized_result
function M.validate_result(result)
	-- Handle nil results
	if result == nil then
		return vim.empty_dict()
	end

	-- Handle empty tables that should be objects
	if type(result) == "table" and vim.tbl_isempty(result) then
		return vim.empty_dict()
	end

	-- For arrays, ensure proper encoding
	if type(result) == "table" and vim.tbl_islist(result) then
		return result
	end

	-- For objects, ensure properties are properly encoded
	if type(result) == "table" then
		local sanitized = {}
		for k, v in pairs(result) do
			-- Recursively validate nested structures
			if type(v) == "table" then
				sanitized[k] = M.validate_result(v)
			else
				sanitized[k] = v
			end
		end

		-- Ensure empty tables become empty objects
		if vim.tbl_isempty(sanitized) then
			return vim.empty_dict()
		end

		return sanitized
	end

	return result
end

-- Create request object
---@param id number Request ID
---@param method string Method name
---@param params table? Method parameters
---@return table request
function M.create_request(id, method, params)
	-- Validate inputs
	if not validate_method_name(method) then
		error("Invalid method name: " .. tostring(method))
	end

	if type(id) ~= "number" then
		error("Request ID must be a number")
	end

	local request = {
		jsonrpc = M.VERSION,
		method = method,
		id = id,
	}

	if params ~= nil then
		request.params = params
	end

	return request
end

-- Create notification object
---@param method string Method name
---@param params table? Method parameters
---@return table notification
function M.create_notification(method, params)
	-- Validate inputs
	if not validate_method_name(method) then
		error("Invalid method name: " .. tostring(method))
	end

	local notification = {
		jsonrpc = M.VERSION,
		method = method,
	}

	if params ~= nil then
		notification.params = params
	end

	return notification
end

-- Create response object
---@param id number Request ID
---@param result any Response result
---@return table response
function M.create_response(id, result)
	-- Validate inputs
	if type(id) ~= "number" then
		error("Request ID must be a number")
	end

	-- Validate and sanitize result
	local sanitized_result = M.validate_result(result)

	return {
		jsonrpc = M.VERSION,
		id = id,
		result = sanitized_result,
	}
end

-- Create error response object
---@param id number? Request ID
---@param code number Error code
---@param message string Error message
---@param data any? Additional error data
---@return table response
function M.create_error_response(id, code, message, data)
	-- Validate inputs
	if type(code) ~= "number" then
		error("Error code must be a number")
	end

	if type(message) ~= "string" then
		error("Error message must be a string")
	end

	-- Truncate overly long error messages
	if #message > CONFIG.MAX_ERROR_MESSAGE_LENGTH then
		message = message:sub(1, CONFIG.MAX_ERROR_MESSAGE_LENGTH - 3) .. "..."
	end

	local error_obj = {
		code = code,
		message = message,
	}

	if data ~= nil then
		error_obj.data = data
	end

	return {
		jsonrpc = M.VERSION,
		id = id,
		error = error_obj,
	}
end

return M
