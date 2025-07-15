-- Log-related commands for claude-code.nvim

local M = {}

function M.setup()
	local log = require("claude-code.log")

	-- Open log file
	vim.api.nvim_create_user_command("ClaudeCodeLog", function()
		log.open()
	end, { desc = "Open Claude Code log file" })

	-- Tail log file
	vim.api.nvim_create_user_command("ClaudeCodeLogTail", function(opts)
		local lines = tonumber(opts.args) or 50
		local content = log.tail(lines)

		-- Create a scratch buffer
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = "log"

		-- Open in a split
		vim.cmd("split")
		vim.api.nvim_win_set_buf(0, buf)
		vim.cmd("normal! G")
	end, {
		desc = "Tail Claude Code log file",
		nargs = "?",
	})

	-- Clear log file
	vim.api.nvim_create_user_command("ClaudeCodeLogClear", function()
		log.clear()
		vim.notify("Claude Code log cleared", vim.log.levels.INFO)
	end, { desc = "Clear Claude Code log file" })

	-- Set log level
	vim.api.nvim_create_user_command("ClaudeCodeLogLevel", function(opts)
		local level = opts.args:upper()
		if log.levels[level] then
			log.set_level(level)
			vim.notify("Claude Code log level set to " .. level, vim.log.levels.INFO)
		else
			vim.notify("Invalid log level. Use: TRACE, DEBUG, INFO, WARN, ERROR, or OFF", vim.log.levels.ERROR)
		end
	end, {
		desc = "Set Claude Code log level",
		nargs = 1,
		complete = function()
			return { "TRACE", "DEBUG", "INFO", "WARN", "ERROR", "OFF" }
		end,
	})

	-- Show current log level
	vim.api.nvim_create_user_command("ClaudeCodeLogStatus", function()
		local level = log.get_level()
		local file = log.get_file()
		vim.notify(string.format("Log level: %s\nLog file: %s", level, file), vim.log.levels.INFO)
	end, { desc = "Show Claude Code log status" })
end

return M
