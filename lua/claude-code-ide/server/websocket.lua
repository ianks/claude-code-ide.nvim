-- WebSocket protocol implementation for claude-code-ide.nvim
-- Based on RFC 6455 - Protocol handling only

local events = require("claude-code-ide.events")
local log = require("claude-code-ide.log")
local auth = require("claude-code-ide.server.auth")

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

-- Maximum frame size (1MB)
local MAX_FRAME_SIZE = 1024 * 1024

-- Connection timeout (30 seconds)
local CONNECTION_TIMEOUT = 30000

-- Handle new WebSocket connection
---@param client userdata UV TCP handle
---@param server table Server instance
function M.handle_connection(client, server)
	local connection = {
		socket = client,
		server = server,
		state = "connecting",
		buffer = "",
		timeout_timer = nil,
	}

	-- Set connection timeout
	connection.timeout_timer = vim.uv.new_timer()
	if connection.timeout_timer then
		connection.timeout_timer:start(CONNECTION_TIMEOUT, 0, function()
			M._close_connection(connection, "Connection timeout")
		end)
	end

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
			M._handle_frames(connection)
		end
	end)
end

-- Handle WebSocket handshake
---@param connection table Connection object
function M._handle_handshake(connection)
	local headers, header_end = M._parse_http_headers(connection.buffer)
	if not headers then
		return -- Not enough data yet
	end

	log.debug("WEBSOCKET", "Received handshake headers", headers)

	-- Validate WebSocket upgrade request
	if not M._validate_upgrade_request(headers) then
		M._send_error_response(connection, 400, "Bad Request")
		return
	end

	-- Check authorization using auth module
	local token = auth.extract_token(headers)
	log.info("WEBSOCKET", "Auth check", {
		has_token = token ~= nil,
		token_preview = token and token:sub(1, 8) .. "...",
		expected_token_preview = connection.server.auth_token and connection.server.auth_token:sub(1, 8) .. "...",
		headers_auth = headers["authorization"],
	})
	if not auth.validate_token(token, connection.server.auth_token) then
		events.emit(events.events.AUTHENTICATION_FAILED, {
			client_ip = connection.socket:getpeername() and connection.socket:getpeername().ip,
			reason = "Invalid token",
		})
		M._send_error_response(connection, 401, "Unauthorized")
		return
	end

	-- Defer the WebSocket accept key calculation to avoid fast event context
	vim.schedule(function()
		-- Create upgrade response using auth module
		local accept_key, err = auth.create_websocket_accept(headers["sec-websocket-key"])
		if not accept_key then
			M._send_error_response(connection, 500, "Internal Server Error: " .. (err or "Unknown"))
			return
		end

		local response = M._create_upgrade_response(accept_key, headers)
		connection.socket:write(response)

		-- Update connection state
		connection.state = "connected"
		connection.buffer = connection.buffer:sub(header_end + 1) -- Remove handshake data

		-- Cancel timeout timer
		if connection.timeout_timer then
			connection.timeout_timer:close()
			connection.timeout_timer = nil
		end

		-- Generate client ID and register with server
		local client_id = headers["sec-websocket-key"]:gsub("[^%w]", ""):sub(1, 16)
		connection.id = client_id
		connection.server:add_client(client_id, connection)

		-- Emit client connected event
		events.emit(events.events.CLIENT_CONNECTED, {
			client_id = client_id,
			client_ip = connection.socket:getpeername() and connection.socket:getpeername().ip,
		})

		-- Initialize RPC handler, injecting the send function to break circular dependency
		local rpc = require("claude-code-ide.rpc.init")
		connection.rpc = rpc.new(connection, M.send_text)

		-- Start heartbeat to keep connection alive
		connection.heartbeat_timer = vim.loop.new_timer()
		connection.heartbeat_timer:start(
			30000,
			30000,
			vim.schedule_wrap(function()
				if connection.state == "connected" then
					M.send_frame(connection, OPCODES.PING, "heartbeat")
				end
			end)
		)

		log.info("WEBSOCKET", "WebSocket handshake complete", {
			client_id = client_id,
			auth_token_preview = auth.AUTH_TOKEN and auth.AUTH_TOKEN:sub(1, 8) .. "...",
		})

		-- Send initial notifications to Claude
		vim.defer_fn(function()
			local notifications = require("claude-code-ide.editor_notifications")
			notifications.notify_ide_connected()
			notifications.notify_selection_changed()
		end, 100)
	end)
end

-- Parse HTTP headers from request
---@param data string Raw HTTP data
---@return table|nil headers Parsed headers or nil if incomplete
---@return number|nil end_pos Position after headers
function M._parse_http_headers(data)
	local header_end = data:find("\r\n\r\n")
	if not header_end then
		return nil -- Headers incomplete
	end

	local headers = {}
	local lines = vim.split(data:sub(1, header_end), "\r\n")

	-- Parse request line
	if #lines > 0 then
		local method, path, version = lines[1]:match("^(%S+)%s+(%S+)%s+(%S+)")
		headers.method = method
		headers.path = path
		headers.version = version
	end

	-- Parse headers
	for i = 2, #lines do
		local key, value = lines[i]:match("^([^:]+):%s*(.+)")
		if key and value then
			headers[key:lower():match("^%s*(.-)%s*$")] = value:match("^%s*(.-)%s*$")
		end
	end

	return headers, header_end + 3
end

-- Validate WebSocket upgrade request
---@param headers table HTTP headers
---@return boolean valid
function M._validate_upgrade_request(headers)
	return headers.method == "GET"
		and headers["upgrade"]
		and headers["upgrade"]:lower() == "websocket"
		and headers["connection"]
		and headers["connection"]:lower():find("upgrade")
		and headers["sec-websocket-key"]
		and headers["sec-websocket-version"] == "13"
end

-- Create WebSocket upgrade response
---@param accept_key string Computed Sec-WebSocket-Accept value
---@param headers table HTTP headers from request
---@return string response HTTP response
function M._create_upgrade_response(accept_key, headers)
	local response_lines = {
		"HTTP/1.1 101 Switching Protocols",
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Accept: " .. accept_key,
	}

	-- Echo back the requested subprotocol if any
	if headers["sec-websocket-protocol"] then
		table.insert(response_lines, "Sec-WebSocket-Protocol: " .. headers["sec-websocket-protocol"])
	end

	table.insert(response_lines, "")
	table.insert(response_lines, "")

	return table.concat(response_lines, "\r\n")
end

-- Handle WebSocket frames
---@param connection table Connection object
function M._handle_frames(connection)
	while #connection.buffer >= 2 do
		local frame_data, bytes_consumed = M._parse_frame(connection.buffer)
		if not frame_data then
			return -- Need more data
		end

		-- Check frame size limit
		if frame_data.payload_len > MAX_FRAME_SIZE then
			M._close_connection(connection, "Frame too large")
			return
		end

		-- Remove processed frame from buffer
		connection.buffer = connection.buffer:sub(bytes_consumed + 1)

		-- Handle frame by opcode
		if frame_data.opcode == OPCODES.TEXT then
			log.info("WEBSOCKET", "Received TEXT frame", {
				client_id = connection.id,
				payload_len = #frame_data.payload,
				payload_preview = frame_data.payload:sub(1, 100),
			})
			-- Process JSON-RPC message in async context
			vim.schedule(function()
				if connection.rpc then
					connection.rpc:process_message(frame_data.payload)
				else
					log.error("WEBSOCKET", "No RPC handler for connection", { client_id = connection.id })
				end
			end)
		elseif frame_data.opcode == OPCODES.CLOSE then
			M._close_connection(connection, "Client requested close")
			return
		elseif frame_data.opcode == OPCODES.PING then
			M.send_frame(connection, OPCODES.PONG, frame_data.payload)
		end
	end
end

-- Parse a single WebSocket frame
---@param buffer string Buffer containing frame data
---@return table|nil frame_data Parsed frame or nil if incomplete
---@return number|nil bytes_consumed Number of bytes consumed
function M._parse_frame(buffer)
	if #buffer < 2 then
		return nil
	end

	local byte1 = buffer:byte(1)
	local byte2 = buffer:byte(2)

	local fin = bit.band(byte1, 0x80) ~= 0
	local opcode = bit.band(byte1, 0x0F)
	local masked = bit.band(byte2, 0x80) ~= 0
	local payload_len = bit.band(byte2, 0x7F)

	-- Client frames must be masked
	if not masked then
		return nil, "Client frames must be masked"
	end

	local header_len = 2

	-- Extended payload length
	if payload_len == 126 then
		if #buffer < 4 then
			return nil
		end
		payload_len = bit.lshift(buffer:byte(3), 8) + buffer:byte(4)
		header_len = 4
	elseif payload_len == 127 then
		if #buffer < 10 then
			return nil
		end
		-- Handle 64-bit length (simplified to 32-bit)
		payload_len = 0
		for i = 7, 10 do
			payload_len = bit.lshift(payload_len, 8) + buffer:byte(i)
		end
		header_len = 10
	end

	-- Check if we have the complete frame
	local total_len = header_len + 4 + payload_len -- 4 bytes for mask key
	if #buffer < total_len then
		return nil
	end

	-- Extract mask key
	local mask_start = header_len + 1
	local mask_key = {}
	for i = 0, 3 do
		mask_key[i + 1] = buffer:byte(mask_start + i)
	end

	-- Extract and unmask payload
	local payload_start = mask_start + 4
	local payload_bytes = {}
	for i = 0, payload_len - 1 do
		local byte = buffer:byte(payload_start + i)
		payload_bytes[i + 1] = string.char(bit.bxor(byte, mask_key[(i % 4) + 1]))
	end

	return {
		fin = fin,
		opcode = opcode,
		payload_len = payload_len,
		payload = table.concat(payload_bytes),
	},
		total_len
end

-- Send WebSocket frame
---@param connection table Connection object
---@param opcode number Frame opcode
---@param data string Frame payload
function M.send_frame(connection, opcode, data)
	if not connection.socket or connection.state ~= "connected" then
		return
	end

	local frame = {}

	-- First byte: FIN = 1, RSV = 0, Opcode
	table.insert(frame, string.char(bit.bor(0x80, opcode)))

	-- Payload length (server frames are not masked)
	local len = #data
	if len < 126 then
		table.insert(frame, string.char(len))
	elseif len < 65536 then
		table.insert(frame, string.char(126))
		table.insert(frame, string.char(bit.rshift(len, 8)))
		table.insert(frame, string.char(bit.band(len, 0xFF)))
	else
		-- For larger payloads, use 64-bit length
		table.insert(frame, string.char(127))
		-- Simplified: support up to 32-bit lengths
		for i = 3, 0, -1 do
			table.insert(frame, string.char(0))
		end
		for i = 3, 0, -1 do
			table.insert(frame, string.char(bit.band(bit.rshift(len, i * 8), 0xFF)))
		end
	end

	-- Payload (unmasked for server)
	table.insert(frame, data)

	-- Send frame
	connection.socket:write(table.concat(frame))
end

-- Send text frame
---@param connection table Connection object
---@param text string Text data
function M.send_text(connection, text)
	M.send_frame(connection, OPCODES.TEXT, text)
end

-- Close connection (delegates to server for client management)
---@param connection table Connection object
---@param reason string? Close reason
function M._close_connection(connection, reason)
	-- Clean up connection-specific resources
	if connection.timeout_timer then
		connection.timeout_timer:close()
		connection.timeout_timer = nil
	end

	if connection.heartbeat_timer then
		connection.heartbeat_timer:close()
		connection.heartbeat_timer = nil
	end

	if connection.socket then
		connection.socket:close()
	end

	-- Delegate client management to server
	if connection.id and connection.server then
		connection.server:remove_client(connection.id)

		-- Emit client disconnected event
		events.emit(events.events.CLIENT_DISCONNECTED, {
			client_id = connection.id,
			reason = reason,
		})
	end

	vim.schedule(function()
		log.info("WEBSOCKET", "Connection closed", {
			client_id = connection.id,
			reason = reason or "unknown",
			state = connection.state,
		})
	end)
end

-- Send HTTP error response
---@param connection table Connection object
---@param code number HTTP status code
---@param message string Status message
function M._send_error_response(connection, code, message)
	local response = string.format("HTTP/1.1 %d %s\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", code, message)
	connection.socket:write(response)
	M._close_connection(connection, message)
end

return M
