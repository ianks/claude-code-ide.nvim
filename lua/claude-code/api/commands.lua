-- User commands for claude-code.nvim

local M = {}
local notify = require("claude-code.ui.notify")

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

		notify.info(table.concat(lines, "\n"), { title = "Claude Code Status" })
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

	-- Command palette
	vim.api.nvim_create_user_command("ClaudeCodePalette", function()
		require("claude-code.ui.picker").show_commands()
	end, {
		desc = "Show Claude Code command palette",
	})

	-- Cache statistics
	vim.api.nvim_create_user_command("ClaudeCodeCacheStats", function()
		local cache = require("claude-code.cache")
		local stats = cache.get_all_stats()

		local lines = { "Cache Statistics:" }

		for name, stat in pairs(stats) do
			table.insert(lines, "")
			table.insert(lines, "  " .. name .. ":")
			table.insert(lines, "    Entries: " .. stat.total_entries .. "/" .. stat.max_size)
			table.insert(lines, "    Expired: " .. stat.expired_entries)
			table.insert(lines, "    Total Hits: " .. stat.total_hits)
			table.insert(lines, "    Size: ~" .. math.floor(stat.estimated_size / 1024) .. "KB")
		end

		if vim.tbl_isempty(stats) then
			table.insert(lines, "  No caches active")
		end

		notify.info(table.concat(lines, "\n"), { title = "Cache Statistics" })
	end, {
		desc = "Show cache statistics",
	})

	-- Clear cache
	vim.api.nvim_create_user_command("ClaudeCodeCacheClear", function()
		local cache = require("claude-code.cache")
		cache.invalidate_all()
		notify.info("All caches cleared", { title = "Cache Cleared" })
	end, {
		desc = "Clear all caches",
	})
end

return M
