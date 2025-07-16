-- WebSocket protocol implementation for claude-code.nvim
-- Based on RFC 6455

local events = require("claude-code.events")
local log = require("claude-code.log")
local notify = require("claude-code.ui.notify")

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

	log.debug("WEBSOCKET", "Received handshake headers", headers)

	-- Validate WebSocket upgrade request
	if not M._validate_upgrade_request(headers) then
		M._send_error_response(connection, 400, "Bad Request")
		return
	end

	-- Check authorization
	local auth = require("claude-code.server.auth")
	if not auth.validate_token(headers["x-claude-code-ide-authorization"], connection.server.auth_token) then
		events.emit(events.events.AUTHENTICATION_FAILED, {
			client_ip = connection.socket:getpeername(),
			reason = "Invalid token",
		})
		M._send_error_response(connection, 401, "Unauthorized")
		return
	end

	-- Send upgrade response
	local response = M._create_upgrade_response(headers["sec-websocket-key"], headers)
	connection.socket:write(response)

	-- Update connection state
	connection.state = "connected"
	connection.buffer = "" -- Clear handshake data

	-- Generate client ID and register
	-- Use a simple hash of the key for client ID to avoid vim.fn in fast context
	local client_id = headers["sec-websocket-key"]:gsub("[^%w]", ""):sub(1, 16)
	connection.id = client_id
	connection.server:add_client(client_id, connection)

	-- Emit client connected event
	events.emit(events.events.CLIENT_CONNECTED, {
		client_id = client_id,
		client_ip = connection.socket:getpeername(),
	})

	-- Initialize RPC handler
	local rpc = require("claude-code.rpc.init")
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
			-- Trim whitespace from key and value
			key = key:match("^%s*(.-)%s*$")
			value = value:match("^%s*(.-)%s*$")
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
		and headers["upgrade"]
		and headers["upgrade"]:lower() == "websocket"
		and headers["connection"]
		and headers["connection"]:lower():find("upgrade")
		and headers["sec-websocket-key"]
		and headers["sec-websocket-version"] == "13"
end

-- Base64 encoding table
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Base64 encode function
local function base64_encode(data)
	local result = {}
	local padding = ""

	for i = 1, #data, 3 do
		local b1, b2, b3 = string.byte(data, i, i + 2)
		b2 = b2 or 0
		b3 = b3 or 0

		local n = bit.lshift(b1, 16) + bit.lshift(b2, 8) + b3

		table.insert(result, b64chars:sub(bit.rshift(n, 18) + 1, bit.rshift(n, 18) + 1))
		table.insert(result, b64chars:sub(bit.band(bit.rshift(n, 12), 0x3F) + 1, bit.band(bit.rshift(n, 12), 0x3F) + 1))

		if i + 1 <= #data then
			table.insert(
				result,
				b64chars:sub(bit.band(bit.rshift(n, 6), 0x3F) + 1, bit.band(bit.rshift(n, 6), 0x3F) + 1)
			)
		else
			padding = padding .. "="
		end

		if i + 2 <= #data then
			table.insert(result, b64chars:sub(bit.band(n, 0x3F) + 1, bit.band(n, 0x3F) + 1))
		else
			padding = padding .. "="
		end
	end

	return table.concat(result) .. padding
end

-- Create WebSocket upgrade response
---@param key string Client's Sec-WebSocket-Key
---@param headers table HTTP headers from request
---@return string response HTTP response
function M._create_upgrade_response(key, headers)
	local concatenated = key .. WS_MAGIC

	log.trace("WEBSOCKET", "Creating upgrade response", {
		key = key,
		magic = WS_MAGIC,
		concatenated = concatenated,
	})

	-- Use openssl command to compute SHA1 and base64
	-- First get the SHA1 hex digest
	local sha1_cmd = "printf '%s' '"
		.. concatenated:gsub("'", "'\\''")
		.. "' | openssl dgst -sha1 -binary | openssl base64 -A"

	log.trace("WEBSOCKET", "Running SHA1 command", { command = sha1_cmd })

	local handle = io.popen(sha1_cmd, "r")
	local accept = ""
	if handle then
		local output = handle:read("*a")
		accept = output:gsub("%s+$", "") -- Remove only trailing whitespace
		handle:close()

		log.trace("WEBSOCKET", "SHA1 result", {
			raw_output = output,
			trimmed = accept,
		})
	else
		-- Fallback if openssl is not available
		error("WebSocket handshake failed: openssl command not available")
	end

	log.debug("WEBSOCKET", "Computed Sec-WebSocket-Accept", { accept = accept })

	-- Include subprotocol if requested
	local response_lines = {
		"HTTP/1.1 101 Switching Protocols",
		"Upgrade: websocket",
		"Connection: Upgrade",
		"Sec-WebSocket-Accept: " .. accept,
	}

	-- Echo back the requested subprotocol
	if headers["sec-websocket-protocol"] then
		table.insert(response_lines, "Sec-WebSocket-Protocol: " .. headers["sec-websocket-protocol"])
	end

	table.insert(response_lines, "")
	table.insert(response_lines, "")

	local response = table.concat(response_lines, "\r\n")

	log.trace("WEBSOCKET", "Full response", {
		response = response:gsub("\r", "\\r"):gsub("\n", "\\n"),
	})

	return response
end

-- Handle WebSocket frame
---@param connection table Connection object
function M._handle_frame(connection)
	while #connection.buffer >= 2 do
		-- Parse frame header
		local byte1 = string.byte(connection.buffer, 1)
		local byte2 = string.byte(connection.buffer, 2)

		local fin = bit.band(byte1, 0x80) ~= 0
		local opcode = bit.band(byte1, 0x0F)
		local masked = bit.band(byte2, 0x80) ~= 0
		local payload_len = bit.band(byte2, 0x7F)

		-- Client frames must be masked
		if not masked then
			M._close_connection(connection, "Client frames must be masked")
			return
		end

		local header_len = 2
		local mask_key_start = 2

		-- Extended payload length
		if payload_len == 126 then
			if #connection.buffer < 4 then
				return
			end -- Need more data
			payload_len = bit.lshift(string.byte(connection.buffer, 3), 8) + string.byte(connection.buffer, 4)
			header_len = 4
			mask_key_start = 4
		elseif payload_len == 127 then
			if #connection.buffer < 10 then
				return
			end -- Need more data
			-- For simplicity, we'll limit to 32-bit lengths
			payload_len = 0
			for i = 7, 10 do
				payload_len = bit.lshift(payload_len, 8) + string.byte(connection.buffer, i)
			end
			header_len = 10
			mask_key_start = 10
		end

		-- Check if we have the complete frame
		local total_len = header_len + 4 + payload_len -- 4 bytes for mask key
		if #connection.buffer < total_len then
			return -- Need more data
		end

		-- Extract mask key
		local mask_key = {}
		for i = 1, 4 do
			mask_key[i] = string.byte(connection.buffer, mask_key_start + i)
		end

		-- Extract and unmask payload
		local payload_start = mask_key_start + 5
		local payload = {}
		for i = 0, payload_len - 1 do
			local byte = string.byte(connection.buffer, payload_start + i)
			payload[i + 1] = string.char(bit.bxor(byte, mask_key[(i % 4) + 1]))
		end
		local data = table.concat(payload)

		-- Remove processed frame from buffer
		connection.buffer = connection.buffer:sub(total_len + 1)

		-- Handle frame by opcode
		if opcode == OPCODES.TEXT then
			-- Try to decode and pretty print JSON for logging
			local ok, decoded = pcall(vim.json.decode, data)
			if ok then
				log.debug("RPC", "Received message", decoded)
			else
				log.debug("RPC", "Received raw message", { data = data })
			end

			-- Process JSON-RPC message in async context to avoid fast event issues
			vim.schedule(function()
				connection.rpc:process_message(data)
			end)
		elseif opcode == OPCODES.CLOSE then
			-- Handle close frame
			M._close_connection(connection, "Client requested close")
			return
		elseif opcode == OPCODES.PING then
			-- Respond with pong
			M.send_frame(connection, OPCODES.PONG, data)
		end

		-- If not FIN, we should accumulate frames (not implemented for simplicity)
		if not fin then
			notify.warn("Fragmented frames not supported")
		end
	end
end

-- Send WebSocket frame
---@param connection table Connection object
---@param opcode number Frame opcode
---@param data string Frame payload
function M.send_frame(connection, opcode, data)
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
		-- For simplicity, we'll only support up to 32-bit lengths
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

-- Close connection
---@param connection table Connection object
---@param reason string? Close reason
function M._close_connection(connection, reason)
	if connection.socket then
		connection.socket:close()
	end

	if connection.id and connection.server then
		connection.server:remove_client(connection.id)

		-- Emit client disconnected event
		events.emit(events.events.CLIENT_DISCONNECTED, {
			client_id = connection.id,
			reason = reason,
		})
	end

	if reason then
		notify.debug("WebSocket connection closed: " .. reason)
	end
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
