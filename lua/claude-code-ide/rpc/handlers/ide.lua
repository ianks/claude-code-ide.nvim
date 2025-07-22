-- IDE-specific handlers for claude-code-ide.nvim with enhanced validation
-- These are non-standard MCP extensions used by Claude CLI

local log = require("claude-code-ide.log")
local events = require("claude-code-ide.events")

local M = {}

-- Configuration constants
local CONFIG = {
	MAX_PID_VALUE = 999999999, -- Reasonable PID limit
}

-- Validate PID parameter
---@param pid number? Process ID to validate
---@return boolean valid, string? error_message
local function validate_pid(pid)
	if pid == nil then
		return true, nil -- PID is optional
	end

	if type(pid) ~= "number" then
		return false, "PID must be a number"
	end

	if pid <= 0 or pid > CONFIG.MAX_PID_VALUE then
		return false, "PID must be a positive number within valid range"
	end

	if math.floor(pid) ~= pid then
		return false, "PID must be an integer"
	end

	return true, nil
end

-- Handle ide_connected notification (not a request - no response expected)
---@param rpc table RPC instance
---@param params table Parameters containing pid
function M.ide_connected(rpc, params)
	log.debug("IDE", "ide_connected notification received", params)

	-- Validate RPC instance
	if not rpc or not rpc.connection then
		log.warn("IDE", "Invalid RPC instance in ide_connected notification")
		return
	end

	-- Validate parameters
	if params and type(params) ~= "table" then
		log.warn("IDE", "Invalid parameters in ide_connected notification")
		return
	end

	local pid = params and params.pid

	-- Validate PID if provided
	local valid, error_msg = validate_pid(pid)
	if not valid then
		log.warn("IDE", "Invalid PID in ide_connected notification: " .. error_msg)
		return
	end

	-- Store the connected PID safely
	if pid then
		rpc.connection.client_pid = pid
		log.debug("IDE", "Client PID stored", {
			pid = pid,
			connection_id = rpc.connection.id,
		})
	else
		log.debug("IDE", "IDE connected without PID", {
			connection_id = rpc.connection.id,
		})
	end

	-- Emit connected event with error handling
	local event_data = {
		pid = pid,
		connection_id = rpc.connection.id,
	}

	local ok, err = pcall(events.emit, "Connected", event_data)
	if not ok then
		log.warn("IDE", "Failed to emit Connected event", {
			error = err,
			event_data = event_data,
		})
	else
		log.debug("IDE", "Connected event emitted successfully", event_data)
	end

	-- Notifications don't return anything
end

return M
