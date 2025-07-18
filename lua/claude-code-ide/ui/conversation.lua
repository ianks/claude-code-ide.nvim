-- Conversation UI for claude-code-ide.nvim
-- Manages the Claude conversation window and interactions

local M = {}
local events = require("claude-code-ide.events")
local notify = require("claude-code-ide.ui.notify")

-- Module state
M._state = {
	window = nil,
	buffer = nil,
	client_id = nil,
	messages = {}, -- Store conversation history
}

-- Create conversation buffer
local function create_buffer()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "claude-conversation"
	
	-- Add welcome message
	local lines = {
		"# Claude Code Connected",
		"",
		"Welcome! Claude is now connected to your Neovim session.",
		"",
		"## Quick Tips:",
		"- Use visual selection to send code to Claude",
		"- Press 'q' to close this window",
		"- Press 'c' to clear the conversation",
		"- Press 's' to save the conversation",
		"- Press '?' for help",
		"",
		"## Keyboard Shortcuts:",
		"- <leader>cc - Send current selection/line to Claude",
		"- <leader>cf - Send current function to Claude",
		"- <leader>cb - Send current buffer to Claude",
		"",
		"## Buffer Shortcuts (this window only):",
		"- q - Close window",
		"- c - Clear conversation",
		"- s - Save conversation",
		"- r - Refresh",
		"- y - Copy message",
		"- <CR> - Send line",
		"- ? - Show this help",
		"",
		"---",
		"",
	}
	
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	
	return buf
end

-- Create conversation window
local function create_window(buf)
	-- Use Snacks.win if available
	local ok, snacks = pcall(require, "Snacks")
	if ok and snacks.win then
		return snacks.win({
			buf = buf,
			title = " Claude Conversation ",
			border = "rounded",
			width = 80,
			height = 0.8,
			row = 0.1,
			col = 0.5,
			zindex = 50,
			keys = {
				q = "close",
				c = function(win)
					M.clear()
				end,
				s = function(win)
					M.save()
				end,
			},
		})
	else
		-- Fallback to native window
		local width = math.min(80, vim.o.columns - 4)
		local height = math.min(30, vim.o.lines - 4)
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)
		
		local win = vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			border = "rounded",
			title = " Claude Conversation ",
			title_pos = "center",
		})
		
		-- Set buffer-local mappings
		vim.api.nvim_buf_set_keymap(buf, "n", "q", ":q<CR>", { silent = true, noremap = true, desc = "Close conversation" })
		vim.api.nvim_buf_set_keymap(buf, "n", "c", ":lua require('claude-code-ide.ui.conversation').clear()<CR>", { silent = true, noremap = true, desc = "Clear conversation" })
		vim.api.nvim_buf_set_keymap(buf, "n", "s", ":lua require('claude-code-ide.ui.conversation').save()<CR>", { silent = true, noremap = true, desc = "Save conversation" })
		
		-- Additional convenience mappings
		local helpers = require("claude-code-ide.ui.conversation_helpers")
		vim.api.nvim_buf_set_keymap(buf, "n", "r", ":lua require('claude-code-ide.ui.conversation_helpers').refresh()<CR>", { silent = true, noremap = true, desc = "Refresh conversation" })
		vim.api.nvim_buf_set_keymap(buf, "n", "?", ":lua require('claude-code-ide.ui.conversation_helpers').show_help()<CR>", { silent = true, noremap = true, desc = "Show help" })
		vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", ":lua require('claude-code-ide.ui.conversation_helpers').send_line()<CR>", { silent = true, noremap = true, desc = "Send current line" })
		vim.api.nvim_buf_set_keymap(buf, "n", "y", ":lua require('claude-code-ide.ui.conversation_helpers').copy_message()<CR>", { silent = true, noremap = true, desc = "Copy message under cursor" })
		
		return { win = win, close = function() vim.api.nvim_win_close(win, true) end }
	end
end

-- Show conversation window
function M.show(client_id)
	-- Store client ID for this conversation
	M._state.client_id = client_id
	
	-- Create buffer if needed
	if not M._state.buffer or not vim.api.nvim_buf_is_valid(M._state.buffer) then
		M._state.buffer = create_buffer()
	end
	
	-- Create window if needed
	if not M._state.window or (M._state.window.win and not vim.api.nvim_win_is_valid(M._state.window.win)) then
		M._state.window = create_window(M._state.buffer)
		
		-- Emit event
		events.emit(events.events.UI_CONVERSATION_OPENED, {
			client_id = client_id,
			buffer = M._state.buffer,
		})
	else
		-- Focus existing window
		if M._state.window.win then
			vim.api.nvim_set_current_win(M._state.window.win)
		elseif M._state.window.focus then
			M._state.window:focus()
		end
	end
	
	return M._state.window
end

-- Hide conversation window
function M.hide()
	if M._state.window then
		if M._state.window.close then
			M._state.window.close()
		elseif M._state.window.win and vim.api.nvim_win_is_valid(M._state.window.win) then
			vim.api.nvim_win_close(M._state.window.win, true)
		end
		
		-- Emit event
		events.emit(events.events.UI_CONVERSATION_CLOSED, {
			client_id = M._state.client_id,
		})
	end
	M._state.window = nil
end

-- Append message to conversation
function M.append(role, content)
	if not M._state.buffer or not vim.api.nvim_buf_is_valid(M._state.buffer) then
		return
	end
	
	-- Store message in history
	table.insert(M._state.messages, {
		role = role,
		content = content,
		timestamp = os.time()
	})
	
	-- Make buffer modifiable temporarily
	vim.bo[M._state.buffer].modifiable = true
	
	-- Format message
	local lines = {}
	local timestamp = os.date("%H:%M:%S")
	
	if role == "user" then
		table.insert(lines, string.format("**[%s] You:**", timestamp))
	elseif role == "assistant" then
		table.insert(lines, string.format("**[%s] Claude:**", timestamp))
	else
		table.insert(lines, string.format("**[%s] System:**", timestamp))
	end
	
	table.insert(lines, "")
	
	-- Split content into lines
	for line in content:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	
	table.insert(lines, "")
	table.insert(lines, "---")
	table.insert(lines, "")
	
	-- Append to buffer
	vim.api.nvim_buf_set_lines(M._state.buffer, -1, -1, false, lines)
	
	-- Scroll to bottom if window is visible
	if M._state.window and M._state.window.win and vim.api.nvim_win_is_valid(M._state.window.win) then
		local line_count = vim.api.nvim_buf_line_count(M._state.buffer)
		vim.api.nvim_win_set_cursor(M._state.window.win, {line_count, 0})
	end
	
	-- Make buffer read-only again
	vim.bo[M._state.buffer].modifiable = false
end

-- Clear conversation
function M.clear()
	if not M._state.buffer or not vim.api.nvim_buf_is_valid(M._state.buffer) then
		return
	end
	
	-- Save current conversation before clearing
	if #M._state.messages > 0 then
		local persistence = require("claude-code-ide.persistence")
		persistence.save_conversation(M._state.messages, {
			session_id = M._state.client_id,
			cleared = true
		})
	end
	
	-- Clear message history
	M._state.messages = {}
	
	-- Recreate buffer with welcome message
	local new_buf = create_buffer()
	
	-- Replace in window if visible
	if M._state.window and M._state.window.win and vim.api.nvim_win_is_valid(M._state.window.win) then
		vim.api.nvim_win_set_buf(M._state.window.win, new_buf)
	end
	
	-- Clean up old buffer
	vim.api.nvim_buf_delete(M._state.buffer, { force = true })
	M._state.buffer = new_buf
	
	notify.info("Conversation cleared")
end

-- Save conversation to file
function M.save()
	if #M._state.messages == 0 then
		notify.warn("No conversation to save")
		return
	end
	
	local persistence = require("claude-code-ide.persistence")
	local filename = persistence.save_conversation(M._state.messages, {
		session_id = M._state.client_id,
		manual_save = true
	})
	
	if filename then
		notify.success("Conversation saved")
	end
end

-- Setup auto-show on client connection
function M.setup()
	-- Set up persistence auto-save
	local persistence = require("claude-code-ide.persistence")
	persistence.setup_autosave(M)
	
	-- Show conversation window when Claude connects
	events.on(events.events.CLIENT_CONNECTED, function(data)
		vim.schedule(function()
			M.show(data.client_id)
			
			-- Try to restore last session
			local restored = persistence.restore_last_session()
			if restored and restored.messages then
				-- Restore message history
				M._state.messages = restored.messages
				
				-- Rebuild buffer with restored messages
				M._rebuild_buffer_from_history()
				
				notify.celebrate("Welcome back! Previous conversation restored.")
				M.append("system", "Claude connected! Previous conversation restored.")
			else
				M.append("system", "Claude connected successfully!")
				-- Celebrate first connection
				if not M._has_connected_before then
					M._has_connected_before = true
					notify.celebrate("Welcome to Claude Code! Ready to assist you.")
				end
			end
		end)
	end)
	
	-- Save conversation when Claude disconnects
	events.on(events.events.CLIENT_DISCONNECTED, function(data)
		vim.schedule(function()
			if M._state.client_id == data.client_id then
				M.append("system", "Claude disconnected.")
				
				-- Save conversation
				if #M._state.messages > 0 then
					local persistence = require("claude-code-ide.persistence")
					persistence.save_conversation(M._state.messages, {
						session_id = M._state.client_id,
						disconnected = true
					})
				end
			end
		end)
	end)
end

-- Rebuild buffer from message history
function M._rebuild_buffer_from_history()
	if not M._state.buffer or not vim.api.nvim_buf_is_valid(M._state.buffer) then
		return
	end
	
	-- Clear buffer and add header
	vim.bo[M._state.buffer].modifiable = true
	local lines = {
		"# Claude Code - Restored Conversation",
		"",
		"---",
		"",
	}
	vim.api.nvim_buf_set_lines(M._state.buffer, 0, -1, false, lines)
	
	-- Add each message
	for _, msg in ipairs(M._state.messages) do
		local msg_lines = {}
		local timestamp = os.date("%H:%M:%S", msg.timestamp)
		
		if msg.role == "user" then
			table.insert(msg_lines, string.format("**[%s] You:**", timestamp))
		elseif msg.role == "assistant" then
			table.insert(msg_lines, string.format("**[%s] Claude:**", timestamp))
		else
			table.insert(msg_lines, string.format("**[%s] System:**", timestamp))
		end
		
		table.insert(msg_lines, "")
		
		-- Split content into lines
		for line in msg.content:gmatch("[^\r\n]+") do
			table.insert(msg_lines, line)
		end
		
		table.insert(msg_lines, "")
		table.insert(msg_lines, "---")
		table.insert(msg_lines, "")
		
		vim.api.nvim_buf_set_lines(M._state.buffer, -1, -1, false, msg_lines)
	end
	
	vim.bo[M._state.buffer].modifiable = false
end

-- Load conversation from persistence
function M.load_conversation()
	local persistence = require("claude-code-ide.persistence")
	persistence.show_picker()
end

return M