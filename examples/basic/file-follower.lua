-- File follower example for claude-code.nvim
-- Automatically follows files that Claude Code opens via the MCP server

local M = {}

-- Module state
local state = {
	enabled = false,
	autocmd_id = nil,
	last_opened_file = nil,
	follow_delay = 100, -- milliseconds
}

-- Setup the file follower
function M.setup(opts)
	opts = opts or {}

	-- Merge options
	state.follow_delay = opts.follow_delay or state.follow_delay

	-- Subscribe to FILE_OPENED events
	local events = require("claude-code.events")
	state.autocmd_id = events.on(events.events.FILE_OPENED, function(data)
		if state.enabled and data and data.file_path then
			M.follow_file(data)
		end
	end, {
		desc = "Follow files opened by Claude Code",
	})

	-- Create user commands
	vim.api.nvim_create_user_command("ClaudeFollowEnable", function()
		M.enable()
	end, { desc = "Enable automatic file following for Claude Code" })

	vim.api.nvim_create_user_command("ClaudeFollowDisable", function()
		M.disable()
	end, { desc = "Disable automatic file following for Claude Code" })

	vim.api.nvim_create_user_command("ClaudeFollowToggle", function()
		M.toggle()
	end, { desc = "Toggle automatic file following for Claude Code" })

	vim.api.nvim_create_user_command("ClaudeFollowStatus", function()
		M.show_status()
	end, { desc = "Show Claude Code file follower status" })
end

-- Follow a file opened by Claude
function M.follow_file(data)
	-- Store the last opened file
	state.last_opened_file = data.file_path

	-- Delay slightly to ensure Claude's operation completes
	vim.defer_fn(function()
		-- Check if file exists
		if vim.fn.filereadable(data.file_path) ~= 1 then
			vim.notify("File follower: File not found - " .. data.file_path, vim.log.levels.WARN)
			return
		end

		-- Get current window before switching
		local current_win = vim.api.nvim_get_current_win()

		-- Determine how to open the file based on preview flag
		if data.preview then
			-- If it's a preview, open in a split
			vim.cmd("split " .. vim.fn.fnameescape(data.file_path))
			vim.api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.3))
		else
			-- Regular file open - check if we should use a new window
			local claude_win = M.find_claude_window()

			if claude_win and claude_win ~= current_win then
				-- If Claude has its own window, open there
				vim.api.nvim_set_current_win(claude_win)
			end

			vim.cmd("edit " .. vim.fn.fnameescape(data.file_path))
		end

		-- Handle text selection if provided
		if data.selection then
			vim.schedule(function()
				if data.selection.start_text then
					local start_pos = vim.fn.searchpos(vim.fn.escape(data.selection.start_text, "\\"), "w")
					if start_pos[1] > 0 then
						vim.api.nvim_win_set_cursor(0, start_pos)

						-- If end text is provided, select the range
						if data.selection.end_text then
							local end_pos = vim.fn.searchpos(vim.fn.escape(data.selection.end_text, "\\"), "w")
							if end_pos[1] > 0 then
								vim.fn.setpos("'<", { 0, start_pos[1], start_pos[2], 0 })
								vim.fn.setpos("'>", { 0, end_pos[1], end_pos[2] + #data.selection.end_text - 1, 0 })
								vim.cmd("normal! gv")
							end
						end
					end
				end
			end)
		end

		-- Notify user
		local msg = string.format("Following Claude to: %s", vim.fn.fnamemodify(data.file_path, ":~:."))
		vim.notify(msg, vim.log.levels.INFO, { title = "Claude File Follower" })
	end, state.follow_delay)
end

-- Find window that might be used by Claude
function M.find_claude_window()
	-- Look for windows with Claude-related buffers
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)

		-- Check if this looks like a Claude-related window
		if name:match("claude") or name:match("Claude") then
			return win
		end
	end

	return nil
end

-- Enable file following
function M.enable()
	state.enabled = true
	vim.notify("Claude file following enabled", vim.log.levels.INFO)
end

-- Disable file following
function M.disable()
	state.enabled = false
	vim.notify("Claude file following disabled", vim.log.levels.INFO)
end

-- Toggle file following
function M.toggle()
	if state.enabled then
		M.disable()
	else
		M.enable()
	end
end

-- Show current status
function M.show_status()
	local status = {
		enabled = state.enabled,
		last_file = state.last_opened_file or "none",
		follow_delay = state.follow_delay .. "ms",
	}

	vim.notify(vim.inspect(status), vim.log.levels.INFO, { title = "Claude File Follower Status" })
end

-- Check if file following is enabled
function M.is_enabled()
	return state.enabled
end

-- Get the last opened file
function M.get_last_file()
	return state.last_opened_file
end

-- Cleanup function
function M.cleanup()
	if state.autocmd_id then
		local events = require("claude-code.events")
		events.off(state.autocmd_id)
		state.autocmd_id = nil
	end
end

return M
