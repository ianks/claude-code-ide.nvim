-- JSON-RPC 2.0 protocol implementation

local M = {}

-- JSON-RPC 2.0 error codes
M.errors = {
  PARSE_ERROR = -32700,
  INVALID_REQUEST = -32600,
  METHOD_NOT_FOUND = -32601,
  INVALID_PARAMS = -32602,
  INTERNAL_ERROR = -32603,
}

-- Protocol version
M.VERSION = "2.0"

-- Validate JSON-RPC message structure
---@param message table Message to validate
---@return boolean valid
function M.validate_message(message)
  -- Must have jsonrpc version
  if message.jsonrpc ~= M.VERSION then
    return false
  end

  -- Request: must have method
  if message.method then
    return type(message.method) == "string"
  end

  -- Response: must have result or error
  if message.result ~= nil or message.error ~= nil then
    return message.id ~= nil
  end

  return false
end

-- Create request object
---@param id number Request ID
---@param method string Method name
---@param params table? Method parameters
---@return table request
function M.create_request(id, method, params)
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
  return {
    jsonrpc = M.VERSION,
    id = id,
    result = result,
  }
end

-- Create error response object
---@param id number? Request ID
---@param code number Error code
---@param message string Error message
---@param data any? Additional error data
---@return table response
function M.create_error_response(id, code, message, data)
  local error = {
    code = code,
    message = message,
  }

  if data ~= nil then
    error.data = data
  end

  return {
    jsonrpc = M.VERSION,
    id = id,
    error = error,
  }
end

return M