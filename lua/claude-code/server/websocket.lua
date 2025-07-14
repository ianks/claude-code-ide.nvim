-- WebSocket protocol implementation for claude-code.nvim
-- Based on RFC 6455

local M = {}

-- WebSocket opcodes
local OPCODES = {
  CONTINUATION = 0x0,
  TEXT = 0x1,
  BINARY = 0x2,
  CLOSE = 0x8,
  PING = 0x9,
  PONG = 0xA,
}

-- WebSocket magic string for handshake
local WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- Handle new WebSocket connection
---@param client userdata UV TCP handle
---@param server table Server instance
function M.handle_connection(client, server)
  local connection = {
    socket = client,
    server = server,
    state = "connecting",
    buffer = "",
  }

  -- Read data from client
  client:read_start(function(err, data)
    if err then
      M._close_connection(connection, "Read error: " .. err)
      return
    end

    if not data then
      M._close_connection(connection, "Client disconnected")
      return
    end

    connection.buffer = connection.buffer .. data

    if connection.state == "connecting" then
      M._handle_handshake(connection)
    elseif connection.state == "connected" then
      M._handle_frame(connection)
    end
  end)
end

-- Handle WebSocket handshake
---@param connection table Connection object
function M._handle_handshake(connection)
  -- Parse HTTP headers
  local headers = M._parse_http_headers(connection.buffer)
  if not headers then
    return -- Not enough data yet
  end

  -- Validate WebSocket upgrade request
  if not M._validate_upgrade_request(headers) then
    M._send_error_response(connection, 400, "Bad Request")
    return
  end

  -- Check authorization
  local auth = require("claude-code.server.auth")
  if not auth.validate_token(headers["x-claude-code-ide-authorization"], connection.server.auth_token) then
    M._send_error_response(connection, 401, "Unauthorized")
    return
  end

  -- Send upgrade response
  local response = M._create_upgrade_response(headers["sec-websocket-key"])
  connection.socket:write(response)

  -- Update connection state
  connection.state = "connected"
  connection.buffer = "" -- Clear handshake data

  -- Generate client ID and register
  local client_id = vim.fn.sha256(headers["sec-websocket-key"])
  connection.id = client_id
  connection.server:add_client(client_id, connection)

  -- Initialize RPC handler
  local rpc = require("claude-code.rpc")
  connection.rpc = rpc.new(connection)
end

-- Parse HTTP headers from request
---@param data string Raw HTTP data
---@return table? headers Parsed headers or nil if incomplete
function M._parse_http_headers(data)
  local header_end = data:find("\r\n\r\n")
  if not header_end then
    return nil -- Headers incomplete
  end

  local headers = {}
  local lines = vim.split(data:sub(1, header_end), "\r\n")

  -- Parse request line
  local method, path, version = lines[1]:match("^(%S+)%s+(%S+)%s+(%S+)")
  headers.method = method
  headers.path = path
  headers.version = version

  -- Parse headers
  for i = 2, #lines do
    local key, value = lines[i]:match("^([^:]+):%s*(.+)")
    if key then
      headers[key:lower()] = value
    end
  end

  return headers
end

-- Validate WebSocket upgrade request
---@param headers table HTTP headers
---@return boolean valid
function M._validate_upgrade_request(headers)
  return headers.method == "GET"
    and headers["upgrade"] and headers["upgrade"]:lower() == "websocket"
    and headers["connection"] and headers["connection"]:lower():find("upgrade")
    and headers["sec-websocket-key"]
    and headers["sec-websocket-version"] == "13"
end

-- Create WebSocket upgrade response
---@param key string Client's Sec-WebSocket-Key
---@return string response HTTP response
function M._create_upgrade_response(key)
  -- Calculate accept key
  local sha1 = vim.fn.sha256(key .. WS_MAGIC)
  local accept = vim.base64.encode(sha1)

  return table.concat({
    "HTTP/1.1 101 Switching Protocols",
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Accept: " .. accept,
    "",
    "",
  }, "\r\n")
end

-- Handle WebSocket frame
---@param connection table Connection object
function M._handle_frame(connection)
  -- TODO: Implement frame parsing and handling
  -- This will parse WebSocket frames and dispatch to RPC handler
end

-- Send WebSocket frame
---@param connection table Connection object
---@param opcode number Frame opcode
---@param data string Frame payload
function M.send_frame(connection, opcode, data)
  -- TODO: Implement frame creation and sending
end

-- Send text frame
---@param connection table Connection object
---@param text string Text data
function M.send_text(connection, text)
  M.send_frame(connection, OPCODES.TEXT, text)
end

-- Close connection
---@param connection table Connection object
---@param reason string? Close reason
function M._close_connection(connection, reason)
  if connection.socket then
    connection.socket:close()
  end

  if connection.id and connection.server then
    connection.server:remove_client(connection.id)
  end

  if reason then
    vim.notify("WebSocket connection closed: " .. reason, vim.log.levels.DEBUG)
  end
end

-- Send HTTP error response
---@param connection table Connection object
---@param code number HTTP status code
---@param message string Status message
function M._send_error_response(connection, code, message)
  local response = string.format(
    "HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
    code,
    message
  )
  connection.socket:write(response)
  M._close_connection(connection, message)
end

return M