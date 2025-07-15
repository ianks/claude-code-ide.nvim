-- User commands for claude-code.nvim

local M = {}

-- Setup user commands
function M.setup()
	-- Main conversation toggle
	vim.api.nvim_create_user_command("ClaudeCodeToggle", function()
		require("claude-code.ui").toggle_conversation()
	end, {
		desc = "Toggle Claude Code conversation window",
	})

	-- Send current selection
	vim.api.nvim_create_user_command("ClaudeCodeSend", function(opts)
		local ui = require("claude-code.ui")

		if opts.range > 0 then
			-- Visual mode: send selection
			local start_line = opts.line1
			local end_line = opts.line2
			ui.send_selection(start_line, end_line)
		else
			-- Normal mode: send current line or file
			ui.send_current()
		end
	end, {
		range = true,
		desc = "Send selection or current context to Claude",
	})

	-- Show server status
	vim.api.nvim_create_user_command("ClaudeCodeStatus", function()
		local claude = require("claude-code")
		local status = claude.status()
		local server = require("claude-code.server").get_server()

		local lines = {
			"Claude Code Status:",
			"  Initialized: " .. tostring(status.initialized),
			"  Server Running: " .. tostring(status.server_running),
		}

		if server then
			table.insert(lines, "  Port: " .. server.port)
			table.insert(lines, "  Host: " .. server.host)
			table.insert(lines, "  Clients: " .. vim.tbl_count(server.clients))
		end

		if status.config then
			table.insert(lines, "  Debug: " .. tostring(status.config.debug or false))
		end

		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, {
		desc = "Show Claude Code server status",
	})

	-- Restart server
	vim.api.nvim_create_user_command("ClaudeCodeRestart", function()
		local claude = require("claude-code")
		claude.stop()
		vim.defer_fn(function()
			claude.setup()
		end, 100)
	end, {
		desc = "Restart Claude Code server",
	})

	-- Open diagnostics
	vim.api.nvim_create_user_command("ClaudeCodeDiagnostics", function()
		require("claude-code.ui").show_diagnostics()
	end, {
		desc = "Show workspace diagnostics in Claude",
	})

	-- Set up log commands
	require("claude-code.api.log_commands").setup()
end

return M
