-- JSON-RPC 2.0 dispatcher for claude-code.nvim

local M = {}
M.__index = M

-- Create new RPC handler
---@param connection table WebSocket connection
---@return table rpc RPC handler instance
function M.new(connection)
  local self = setmetatable({}, M)
  self.connection = connection
  self.handlers = require("claude-code.rpc.handlers")
  self.protocol = require("claude-code.rpc.protocol")
  self.pending_requests = {}
  self.next_id = 1
  
  -- Initialize the connection
  self:_initialize()
  
  return self
end

-- Process incoming JSON-RPC message
---@param message string Raw JSON message
function M:process_message(message)
  local ok, request = pcall(vim.json.decode, message)
  
  if not ok then
    self:_send_error(nil, self.protocol.errors.PARSE_ERROR, "Parse error")
    return
  end

  -- Validate JSON-RPC structure
  if not self.protocol.validate_message(request) then
    self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Invalid request")
    return
  end

  -- Handle different message types
  if request.method and request.id then
    -- Request
    self:_handle_request(request)
  elseif request.method and not request.id then
    -- Notification
    self:_handle_notification(request)
  elseif request.result or request.error then
    -- Response
    self:_handle_response(request)
  else
    self:_send_error(nil, self.protocol.errors.INVALID_REQUEST, "Invalid message type")
  end
end

-- Handle request message
---@param request table JSON-RPC request
function M:_handle_request(request)
  local handler = self.handlers.get_handler(request.method)
  
  if not handler then
    self:_send_error(request.id, self.protocol.errors.METHOD_NOT_FOUND, "Method not found: " .. request.method)
    return
  end

  -- Execute handler asynchronously
  local async = require("plenary.async")
  async.run(function()
    local ok, result = pcall(handler, self, request.params or {})
    
    if ok then
      self:_send_response(request.id, result)
    else
      self:_send_error(request.id, self.protocol.errors.INTERNAL_ERROR, tostring(result))
    end
  end)
end

-- Handle notification message
---@param notification table JSON-RPC notification
function M:_handle_notification(notification)
  local handler = self.handlers.get_notification_handler(notification.method)
  
  if handler then
    -- Notifications don't send responses
    pcall(handler, self, notification.params or {})
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

-- Initialize the RPC connection
function M:_initialize()
  -- Wait for initialize request from client
  -- This is handled by the initialize handler
end

-- Send request to client
---@param method string Method name
---@param params table? Method parameters
---@return table promise Promise that resolves to response
function M:request(method, params)
  local async = require("plenary.async")
  
  return async.wrap(function(callback)
    local id = self.next_id
    self.next_id = self.next_id + 1
    
    local request = self.protocol.create_request(id, method, params)
    
    self.pending_requests[id] = {
      resolve = function(result) callback(nil, result) end,
      reject = function(error) callback(error, nil) end,
    }
    
    self:_send(request)
  end, 1)()
end

-- Send notification to client
---@param method string Method name
---@param params table? Method parameters
function M:notify(method, params)
  local notification = self.protocol.create_notification(method, params)
  self:_send(notification)
end

-- Send response
---@param id number Request ID
---@param result any Response result
function M:_send_response(id, result)
  local response = self.protocol.create_response(id, result)
  self:_send(response)
end

-- Send error response
---@param id number? Request ID
---@param code number Error code
---@param message string Error message
function M:_send_error(id, code, message)
  local response = self.protocol.create_error_response(id, code, message)
  self:_send(response)
end

-- Send message over WebSocket
---@param message table Message to send
function M:_send(message)
  local websocket = require("claude-code.server.websocket")
  local json = vim.json.encode(message)
  websocket.send_text(self.connection, json)
end

return M