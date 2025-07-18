-- Conversation persistence for claude-code-ide.nvim
-- Saves and restores conversation history across sessions

local M = {}
local notify = require("claude-code-ide.ui.notify")
local events = require("claude-code-ide.events")

-- Default paths
local function get_data_dir()
	return vim.fn.stdpath("data") .. "/claude-code-ide"
end

local function get_conversations_dir()
	return get_data_dir() .. "/conversations"
end

local function get_active_session_file()
	return get_data_dir() .. "/active_session.json"
end

-- Ensure directories exist
local function ensure_dirs()
	vim.fn.mkdir(get_data_dir(), "p")
	vim.fn.mkdir(get_conversations_dir(), "p")
end

-- Generate conversation filename
local function get_conversation_filename(session_id)
	local timestamp = os.date("%Y%m%d_%H%M%S")
	return string.format("%s/conversation_%s_%s.json", get_conversations_dir(), timestamp, session_id or "default")
end

-- Save conversation to file
function M.save_conversation(messages, metadata)
	ensure_dirs()
	
	metadata = metadata or {}
	metadata.saved_at = os.time()
	metadata.neovim_version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch
	
	local data = {
		version = 1,
		metadata = metadata,
		messages = messages
	}
	
	local filename = get_conversation_filename(metadata.session_id)
	local file = io.open(filename, "w")
	if file then
		file:write(vim.json.encode(data))
		file:close()
		
		-- Save as active session
		M.save_active_session({
			filename = filename,
			session_id = metadata.session_id,
			saved_at = metadata.saved_at
		})
		
		events.emit(events.events.CONVERSATION_SAVED, { filename = filename })
		return filename
	else
		notify.error("Failed to save conversation")
		return nil
	end
end

-- Load conversation from file
function M.load_conversation(filename)
	local file = io.open(filename, "r")
	if not file then
		notify.error("Failed to load conversation: " .. filename)
		return nil
	end
	
	local content = file:read("*all")
	file:close()
	
	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		notify.error("Failed to parse conversation file")
		return nil
	end
	
	return data
end

-- Save active session info
function M.save_active_session(session_info)
	ensure_dirs()
	
	local file = io.open(get_active_session_file(), "w")
	if file then
		file:write(vim.json.encode(session_info))
		file:close()
		return true
	end
	return false
end

-- Load active session info
function M.load_active_session()
	local file = io.open(get_active_session_file(), "r")
	if not file then
		return nil
	end
	
	local content = file:read("*all")
	file:close()
	
	local ok, data = pcall(vim.json.decode, content)
	if ok then
		return data
	end
	return nil
end

-- Clear active session
function M.clear_active_session()
	local file = get_active_session_file()
	if vim.fn.filereadable(file) == 1 then
		os.remove(file)
	end
end

-- List saved conversations
function M.list_conversations()
	local dir = get_conversations_dir()
	local files = vim.fn.glob(dir .. "/conversation_*.json", false, true)
	
	local conversations = {}
	for _, file in ipairs(files) do
		local data = M.load_conversation(file)
		if data then
			table.insert(conversations, {
				filename = file,
				metadata = data.metadata,
				message_count = #(data.messages or {})
			})
		end
	end
	
	-- Sort by saved_at descending
	table.sort(conversations, function(a, b)
		return (a.metadata.saved_at or 0) > (b.metadata.saved_at or 0)
	end)
	
	return conversations
end

-- Delete old conversations (retention policy)
function M.cleanup_old_conversations(days_to_keep)
	days_to_keep = days_to_keep or 30
	local cutoff_time = os.time() - (days_to_keep * 24 * 60 * 60)
	
	local conversations = M.list_conversations()
	local deleted = 0
	
	for _, conv in ipairs(conversations) do
		if conv.metadata.saved_at and conv.metadata.saved_at < cutoff_time then
			os.remove(conv.filename)
			deleted = deleted + 1
		end
	end
	
	if deleted > 0 then
		notify.info(string.format("Cleaned up %d old conversations", deleted))
	end
end

-- Auto-save setup
function M.setup_autosave(conversation_module)
	-- Save on certain events
	local events_to_save = {
		events.events.CLIENT_DISCONNECTED,
		events.events.TOOL_EXECUTED,
	}
	
	for _, event in ipairs(events_to_save) do
		events.on(event, function()
			vim.defer_fn(function()
				-- Get current conversation from the module
				if conversation_module and conversation_module._state and conversation_module._state.messages then
					M.save_conversation(conversation_module._state.messages, {
						session_id = conversation_module._state.client_id,
						auto_saved = true
					})
				end
			end, 1000) -- Delay to avoid saving too frequently
		end)
	end
	
	-- Auto-save periodically
	local timer = vim.loop.new_timer()
	timer:start(60000, 60000, vim.schedule_wrap(function()
		if conversation_module and conversation_module._state and conversation_module._state.messages then
			M.save_conversation(conversation_module._state.messages, {
				session_id = conversation_module._state.client_id,
				auto_saved = true,
				periodic = true
			})
		end
	end))
	
	-- Clean up old conversations on startup
	M.cleanup_old_conversations()
end

-- Restore last session
function M.restore_last_session()
	local session_info = M.load_active_session()
	if not session_info or not session_info.filename then
		return nil
	end
	
	-- Check if file still exists
	if vim.fn.filereadable(session_info.filename) ~= 1 then
		M.clear_active_session()
		return nil
	end
	
	local data = M.load_conversation(session_info.filename)
	if data then
		notify.info("Restored previous conversation")
		return data
	end
	
	return nil
end

-- Show conversation picker
function M.show_picker()
	local conversations = M.list_conversations()
	if #conversations == 0 then
		notify.warn("No saved conversations found")
		return
	end
	
	local items = {}
	for _, conv in ipairs(conversations) do
		local date = os.date("%Y-%m-%d %H:%M", conv.metadata.saved_at or 0)
		local label = string.format("%s - %d messages", date, conv.message_count)
		table.insert(items, label)
	end
	
	vim.ui.select(items, {
		prompt = "Select conversation to load:",
	}, function(choice, idx)
		if choice and conversations[idx] then
			local data = M.load_conversation(conversations[idx].filename)
			if data then
				-- TODO: Load into conversation UI
				notify.success("Loaded conversation from " .. os.date("%Y-%m-%d %H:%M", data.metadata.saved_at or 0))
			end
		end
	end)
end

return M