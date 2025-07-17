-- IDE-specific handlers for claude-code-ide.nvim
-- These are non-standard MCP extensions used by Claude CLI

local M = {}

-- Handle ide_connected request
---@param rpc table RPC instance
---@param params table Parameters containing pid
---@return table result
function M.ide_connected(rpc, params)
	-- Store the connected PID
	if params and params.pid then
		rpc.connection.client_pid = params.pid
	end

	-- Emit connected event
	local events = require("claude-code-ide.events")
	events.emit("Connected", {
		pid = params and params.pid,
		connection_id = rpc.connection.id,
	})

	-- Return empty result
	return vim.empty_dict()
end

return M
