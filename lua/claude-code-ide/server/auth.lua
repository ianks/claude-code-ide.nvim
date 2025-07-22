-- Authentication management for claude-code-ide.nvim

local M = {}

-- Try to load sha1 luarocks package
local has_sha1, sha1 = pcall(require, "sha1")

-- Pure Lua base64 encoding (shared utility)
---@param data string Data to encode
---@return string encoded Base64 encoded string
function M.base64_encode(data)
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local result = {}

	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		b = b or 0
		c = c or 0

		local n = a * 65536 + b * 256 + c

		result[#result + 1] = chars:sub(math.floor(n / 262144) + 1, math.floor(n / 262144) + 1)
		result[#result + 1] = chars:sub(math.floor((n % 262144) / 4096) + 1, math.floor((n % 262144) / 4096) + 1)
		result[#result + 1] = i + 1 <= #data
				and chars:sub(math.floor((n % 4096) / 64) + 1, math.floor((n % 4096) / 64) + 1)
			or "="
		result[#result + 1] = i + 2 <= #data and chars:sub((n % 64) + 1, (n % 64) + 1) or "="
	end

	return table.concat(result)
end

-- Create WebSocket accept key using proper crypto
---@param client_key string Client's Sec-WebSocket-Key
---@return string|nil accept_key
---@return string|nil error
function M.create_websocket_accept(client_key)
	if type(client_key) ~= "string" then
		return nil, "Invalid client key"
	end

	local magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	local combined = client_key .. magic

	-- WebSocket specifically requires SHA1, not SHA256
	local binary_hash

	if has_sha1 then
		-- Use luarocks sha1 package if available
		binary_hash = sha1.binary(combined)
	else
		-- Fallback to system command
		local cmd = "printf '%s' " .. vim.fn.shellescape(combined) .. " | shasum -a 1 | cut -d' ' -f1"
		local hex_hash = vim.fn.system(cmd):gsub("%s+", "")

		if vim.v.shell_error ~= 0 then
			return nil, "Failed to compute SHA1"
		end

		-- Convert hex to binary
		binary_hash = ""
		for i = 1, #hex_hash, 2 do
			local hex_pair = hex_hash:sub(i, i + 1)
			binary_hash = binary_hash .. string.char(tonumber(hex_pair, 16))
		end
	end

	return M.base64_encode(binary_hash)
end

-- Generate a cryptographically secure auth token
---@return string|nil token Generated auth token
---@return string|nil error
function M.generate_token()
	local random_bytes = vim.uv.random(32)
	if not random_bytes then
		return nil, "Failed to generate random bytes"
	end

	local hex_chars = {}
	for i = 1, #random_bytes do
		hex_chars[i] = string.format("%02x", random_bytes:byte(i))
	end
	local hex = table.concat(hex_chars)

	-- Format as UUID-like string for compatibility
	return string.format(
		"%s-%s-%s-%s-%s",
		hex:sub(1, 8),
		hex:sub(9, 12),
		hex:sub(13, 16),
		hex:sub(17, 20),
		hex:sub(21, 32)
	)
end

-- Validate an auth token using constant-time comparison
---@param provided string? Provided token
---@param expected string Expected token
---@return boolean valid
function M.validate_token(provided, expected)
	if type(provided) ~= "string" or type(expected) ~= "string" then
		return false
	end

	if #provided ~= #expected then
		return false
	end

	local result = 0
	for i = 1, #provided do
		local a = provided:byte(i)
		local b = expected:byte(i)
		-- Use simple comparison for constant-time behavior
		if a ~= b then
			result = 1
		end
	end

	return result == 0
end

-- Extract auth token from headers
---@param headers table HTTP headers
---@return string|nil token
function M.extract_token(headers)
	if type(headers) ~= "table" then
		return nil
	end
	return headers["x-claude-code-ide-authorization"]
end

return M
