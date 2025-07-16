-- Session management for claude-code.nvim
-- Provides session-scoped state management for MCP connections

local M = {}

-- Session storage keyed by session ID
local sessions = {}

-- Create or get session
---@param session_id string Session identifier
---@return table Session data
function M.get_session(session_id)
	if not sessions[session_id] then
		sessions[session_id] = {
			id = session_id,
			initialized = false,
			data = {},
			created_at = os.time(),
			last_accessed = os.time(),
		}
	else
		-- Update last accessed time
		sessions[session_id].last_accessed = os.time()
	end
	return sessions[session_id]
end

-- Update session data
---@param session_id string Session identifier
---@param key string Data key
---@param value any Data value
function M.set_session_data(session_id, key, value)
	local session = M.get_session(session_id)
	session.data[key] = value
end

-- Get session data
---@param session_id string Session identifier
---@param key string Data key
---@return any Data value
function M.get_session_data(session_id, key)
	local session = M.get_session(session_id)
	return session.data[key]
end

-- Mark session as initialized
---@param session_id string Session identifier
function M.set_initialized(session_id)
	local session = M.get_session(session_id)
	session.initialized = true
end

-- Check if session is initialized
---@param session_id string Session identifier
---@return boolean
function M.is_initialized(session_id)
	local session = M.get_session(session_id)
	return session.initialized
end

-- Clear session
---@param session_id string Session identifier
function M.clear_session(session_id)
	sessions[session_id] = nil
end

-- Clear all sessions
function M.clear_all_sessions()
	sessions = {}
end

-- Get all active sessions
---@return table<string, table> All sessions
function M.get_all_sessions()
	return sessions
end

-- Clean up old sessions (older than 24 hours)
function M.cleanup_old_sessions()
	local now = os.time()
	local day_in_seconds = 24 * 60 * 60

	for session_id, session in pairs(sessions) do
		if now - session.last_accessed > day_in_seconds then
			sessions[session_id] = nil
		end
	end
end

return M
