-- Helper functions for conversation buffer mappings
local M = {}
local notify = require("claude-code-ide.ui.notify")

-- Refresh conversation
function M.refresh()
	-- Placeholder for refresh functionality
	notify.info("Conversation refreshed")
end

-- Show help by scrolling to top
function M.show_help()
	local conversation = require("claude-code-ide.ui.conversation")
	local state = conversation._state
	
	if not state.buffer or not vim.api.nvim_buf_is_valid(state.buffer) then
		return
	end
	
	-- Scroll to top to show help
	if state.window and state.window.win and vim.api.nvim_win_is_valid(state.window.win) then
		vim.api.nvim_win_set_cursor(state.window.win, {1, 0})
	end
end

-- Send current line to Claude
function M.send_line()
	-- Get current line
	local line = vim.api.nvim_get_current_line()
	if line and line ~= "" and not line:match("^#") and not line:match("^%-%-%-") then
		-- TODO: Integrate with actual Claude API
		notify.info("Would send: " .. line)
	end
end

-- Copy message under cursor
function M.copy_message()
	-- TODO: Implement message copying based on cursor position
	notify.info("Message copy not yet implemented")
end

return M