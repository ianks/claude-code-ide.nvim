-- Real WebSocket client for integration testing
-- Uses vim.loop (libuv) for actual TCP connections

local uv = vim.loop
local bit = require("bit")

local M = {}
M.__index = M

-- WebSocket opcodes
local OPCODES = {
	CONTINUATION = 0x0,
	TEXT = 0x1,
	BINARY = 0x2,
	CLOSE = 0x8,
	PING = 0x9,
	PONG = 0xA,
}

-- Generate WebSocket accept key
local function generate_accept_key(key)
	local magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	local sha1 = vim.fn.system("echo -n '" .. key .. magic .. "' | openssl dgst -sha1 -binary | base64 | tr -d '\\n'")
	return sha1
end

-- Generate random WebSocket key
local function generate_ws_key()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local key = ""
	for i = 1, 16 do
		local idx = math.random(1, #chars)
		key = key .. chars:sub(idx, idx)
	end
	return key .. "=="
end

-- Create WebSocket frame
local function create_frame(opcode, payload, masked)
	local frame = ""
	local payload_len = #payload

	-- FIN (1) + RSV (000) + Opcode
	local byte1 = bit.bor(0x80, opcode)
	frame = frame .. string.char(byte1)

	-- Mask bit + payload length
	local mask_bit = masked and 0x80 or 0x00
	if payload_len < 126 then
		frame = frame .. string.char(bit.bor(mask_bit, payload_len))
	elseif payload_len < 65536 then
		frame = frame .. string.char(bit.bor(mask_bit, 126))
		frame = frame .. string.char(bit.rshift(payload_len, 8))
		frame = frame .. string.char(bit.band(payload_len, 0xFF))
	else
		error("Payload too large for test client")
	end

	-- Masking key (if masked)
	local masking_key = ""
	if masked then
		for i = 1, 4 do
			masking_key = masking_key .. string.char(math.random(0, 255))
		end
		frame = frame .. masking_key
	end

	-- Payload (masked if necessary)
	if masked then
		local masked_payload = ""
		for i = 1, #payload do
			local payload_byte = string.byte(payload, i)
			local mask_byte = string.byte(masking_key, ((i - 1) % 4) + 1)
			masked_payload = masked_payload .. string.char(bit.bxor(payload_byte, mask_byte))
		end
		frame = frame .. masked_payload
	else
		frame = frame .. payload
	end

	return frame
end

-- Parse WebSocket frame
local function parse_frame(data)
	if #data < 2 then
		return nil, "Incomplete frame"
	end

	local byte1 = string.byte(data, 1)
	local byte2 = string.byte(data, 2)

	local fin = bit.band(byte1, 0x80) == 0x80
	local opcode = bit.band(byte1, 0x0F)
	local masked = bit.band(byte2, 0x80) == 0x80
	local payload_len = bit.band(byte2, 0x7F)

	local idx = 3
	if payload_len == 126 then
		if #data < 4 then
			return nil, "Incomplete frame"
		end
		payload_len = bit.lshift(string.byte(data, 3), 8) + string.byte(data, 4)
		idx = 5
	elseif payload_len == 127 then
		return nil, "64-bit payload length not supported in test client"
	end

	-- Skip masking key if present
	if masked then
		idx = idx + 4
	end

	if #data < idx + payload_len - 1 then
		return nil, "Incomplete frame"
	end

	local payload = string.sub(data, idx, idx + payload_len - 1)

	return {
		fin = fin,
		opcode = opcode,
		masked = masked,
		payload = payload,
		total_length = idx + payload_len - 1,
	}
end

function M.new()
	local self = setmetatable({
		tcp = nil,
		connected = false,
		buffer = "",
		pending_requests = {},
		next_id = 1,
		debug = false,
	}, M)
	return self
end

function M:connect(host, port, auth_token)
	assert(not self.connected, "Already connected")

	-- Create TCP socket
	self.tcp = uv.new_tcp()
	local connect_event = vim.loop.new_async(vim.schedule_wrap(function() end))

	-- Connect to server
	self.tcp:connect(host, port, function(err)
		assert(not err, "Connection failed: " .. (err or "unknown error"))

		-- Send WebSocket handshake
		local ws_key = generate_ws_key()
		local handshake = table.concat({
			"GET / HTTP/1.1",
			"Host: " .. host .. ":" .. port,
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Key: " .. ws_key,
			"Sec-WebSocket-Version: 13",
			"x-claude-code-ide-authorization: " .. auth_token,
			"",
			"",
		}, "\r\n")

		self.tcp:write(handshake)

		-- Start reading
		self.tcp:read_start(function(read_err, data)
			assert(not read_err, "Read error: " .. (read_err or "unknown error"))
			if data then
				self:_handle_data(data)
			end
		end)

		self.connected = true
		connect_event:send()
	end)

	-- Wait for connection
	local timeout = vim.loop.new_timer()
	local connected = false
	timeout:start(
		5000,
		0,
		vim.schedule_wrap(function()
			if not self.connected then
				error("Connection timeout")
			end
			connected = true
		end)
	)

	-- Block until connected or timeout
	while not connected and not self.connected do
		vim.wait(10)
	end
	timeout:close()
	connect_event:close()

	-- Wait a bit for handshake to complete
	vim.wait(100)
end

function M:_handle_data(data)
	self.buffer = self.buffer .. data

	-- Check for HTTP response first (handshake)
	if self.buffer:match("^HTTP/1.1") then
		local header_end = self.buffer:find("\r\n\r\n")
		if header_end then
			local headers = self.buffer:sub(1, header_end - 1)
			self.buffer = self.buffer:sub(header_end + 4)

			-- Verify upgrade success
			assert(headers:match("HTTP/1.1 101"), "WebSocket upgrade failed")
			if self.debug then
				print("WebSocket handshake completed")
			end
		end
	end

	-- Process WebSocket frames
	while #self.buffer > 0 do
		local frame, err = parse_frame(self.buffer)
		if not frame then
			break
		end

		self.buffer = self.buffer:sub(frame.total_length + 1)

		if frame.opcode == OPCODES.TEXT then
			self:_handle_message(frame.payload)
		elseif frame.opcode == OPCODES.CLOSE then
			self:close()
			break
		elseif frame.opcode == OPCODES.PING then
			self:_send_frame(OPCODES.PONG, frame.payload)
		end
	end
end

function M:_handle_message(payload)
	local ok, msg = pcall(vim.json.decode, payload)
	if not ok then
		print("Failed to decode message:", payload)
		return
	end

	if self.debug then
		print("Received:", vim.inspect(msg))
	end

	-- Handle response to request
	if msg.id and self.pending_requests[msg.id] then
		local callback = self.pending_requests[msg.id]
		self.pending_requests[msg.id] = nil
		callback(msg)
	end
end

function M:_send_frame(opcode, payload)
	assert(self.connected, "Not connected")
	local frame = create_frame(opcode, payload, true) -- Client must mask
	self.tcp:write(frame)
end

function M:send(message)
	local json = vim.json.encode(message)
	if self.debug then
		print("Sending:", json)
	end
	self:_send_frame(OPCODES.TEXT, json)
end

function M:request(method, params, timeout_ms)
	timeout_ms = timeout_ms or 5000
	local id = self.next_id
	self.next_id = self.next_id + 1

	local response = nil
	local done = false

	self.pending_requests[id] = function(msg)
		response = msg
		done = true
	end

	self:send({
		jsonrpc = "2.0",
		id = id,
		method = method,
		params = params,
	})

	-- Wait for response
	local waited = 0
	while not done and waited < timeout_ms do
		vim.wait(10)
		waited = waited + 10
	end

	if not done then
		self.pending_requests[id] = nil
		error("Request timeout: " .. method)
	end

	if response.error then
		error("Request error: " .. vim.inspect(response.error))
	end

	return response
end

function M:notify(method, params)
	self:send({
		jsonrpc = "2.0",
		method = method,
		params = params,
	})
end

function M:close()
	if self.tcp and not self.tcp:is_closing() then
		-- Send close frame
		self:_send_frame(OPCODES.CLOSE, "")
		vim.wait(50) -- Give server time to receive
		self.tcp:close()
	end
	self.connected = false
end

function M:set_debug(enabled)
	self.debug = enabled
end

return M
