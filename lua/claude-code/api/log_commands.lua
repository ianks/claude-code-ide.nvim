-- Log-related commands for claude-code.nvim

local M = {}
local notify = require("claude-code.ui.notify")

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
		notify.info("Claude Code log cleared")
	end, { desc = "Clear Claude Code log file" })

	-- Set log level
	vim.api.nvim_create_user_command("ClaudeCodeLogLevel", function(opts)
		local level = opts.args:upper()
		if log.levels[level] then
			log.set_level(level)
			notify.info("Claude Code log level set to " .. level)
		else
			notify.error("Invalid log level. Use: TRACE, DEBUG, INFO, WARN, ERROR, or OFF")
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
		notify.info(string.format("Log level: %s\nLog file: %s", level, file))
	end, { desc = "Show Claude Code log status" })
end

return M
