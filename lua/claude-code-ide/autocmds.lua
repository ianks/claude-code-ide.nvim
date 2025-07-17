-- Autocommands for claude-code-ide.nvim
-- Provides intelligent automatic behaviors

local M = {}
local notify = require("claude-code-ide.ui.notify")
local events = require("claude-code-ide.events")

-- Autocommand group
local augroup = vim.api.nvim_create_augroup("ClaudeCode", { clear = true })

-- Default autocommands configuration
M.defaults = {
	-- Auto-open conversation on diagnostics
	auto_open_on_error = {
		enabled = false,
		severity = vim.diagnostic.severity.ERROR,
		desc = "Automatically open Claude conversation on errors",
	},

	-- Auto-follow file changes
	auto_follow_file = {
		enabled = true,
		desc = "Follow file changes in Claude conversation",
	},

	-- Auto-save conversation history
	auto_save_history = {
		enabled = false,
		interval = 300, -- 5 minutes
		desc = "Automatically save conversation history",
	},

	-- Auto-start server
	auto_start_server = {
		enabled = false,
		delay = 100,
		desc = "Automatically start MCP server on startup",
	},

	-- Auto-cleanup old sessions
	auto_cleanup_sessions = {
		enabled = true,
		interval = 3600, -- 1 hour
		desc = "Automatically cleanup old sessions",
	},
}

-- Timer handles
local timers = {}

-- Setup autocommands
---@param opts? table Custom autocommand configuration
function M.setup(opts)
	local config = vim.tbl_deep_extend("force", M.defaults, opts or {})

	-- Clear existing autocommands
	vim.api.nvim_clear_autocmds({ group = augroup })

	-- Auto-open on error
	if config.auto_open_on_error.enabled then
		vim.api.nvim_create_autocmd("DiagnosticChanged", {
			group = augroup,
			desc = config.auto_open_on_error.desc,
			callback = function()
				local diagnostics = vim.diagnostic.get(0, {
					severity = { min = config.auto_open_on_error.severity },
				})

				if #diagnostics > 0 then
					local ui = require("claude-code-ide.ui")
					-- Removed auto-open behavior - users should open Claude manually
					-- This was too intrusive and annoying
				end
			end,
		})
	end

	-- Auto-follow file changes
	if config.auto_follow_file.enabled then
		vim.api.nvim_create_autocmd("BufEnter", {
			group = augroup,
			desc = config.auto_follow_file.desc,
			callback = function(args)
				local ui = require("claude-code-ide.ui")
				if ui.state and ui.state.conversation and ui.state.conversation:valid() then
					local filename = vim.fn.expand("%:p")
					if filename ~= "" then
						events.emit(events.events.FILE_FOCUSED, {
							file = filename,
							bufnr = args.buf,
						})
					end
				end
			end,
		})
	end

	-- Auto-save conversation history
	if config.auto_save_history.enabled then
		-- Clear existing timer
		if timers.history then
			timers.history:stop()
			timers.history:close()
		end

		-- Create new timer
		timers.history = vim.loop.new_timer()
		timers.history:start(
			config.auto_save_history.interval * 1000,
			config.auto_save_history.interval * 1000,
			vim.schedule_wrap(function()
				-- TODO: Implement conversation history saving
				events.emit(events.events.CONVERSATION_SAVED, {
					timestamp = os.time(),
				})
			end)
		)
	end

	-- Auto-start server
	if config.auto_start_server.enabled then
		vim.api.nvim_create_autocmd("VimEnter", {
			group = augroup,
			desc = config.auto_start_server.desc,
			once = true,
			callback = function()
				vim.defer_fn(function()
					local claude = require("claude-code-ide")
					local status = claude.status()
					if not status.server_running then
						claude.start()
						-- Silent start - no notification
					end
				end, config.auto_start_server.delay)
			end,
		})
	end

	-- Auto-cleanup sessions
	if config.auto_cleanup_sessions.enabled then
		-- Clear existing timer
		if timers.cleanup then
			timers.cleanup:stop()
			timers.cleanup:close()
		end

		-- Create new timer
		timers.cleanup = vim.loop.new_timer()
		timers.cleanup:start(
			config.auto_cleanup_sessions.interval * 1000,
			config.auto_cleanup_sessions.interval * 1000,
			vim.schedule_wrap(function()
				local session = require("claude-code-ide.session")
				session.cleanup_old_sessions()
			end)
		)
	end

	-- Handle LSP attach for code actions integration
	vim.api.nvim_create_autocmd("LspAttach", {
		group = augroup,
		desc = "Setup Claude code actions on LSP attach",
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client and client.server_capabilities.codeActionProvider then
				-- Add Claude-specific code actions
				local bufnr = args.buf
				vim.keymap.set({ "n", "v" }, "<leader>ca", function()
					-- Show Claude-enhanced code actions
					require("claude-code-ide.ui.picker").show_commands()
				end, { buffer = bufnr, desc = "Claude code actions" })
			end
		end,
	})

	-- Track conversation window state
	vim.api.nvim_create_autocmd("User", {
		group = augroup,
		pattern = "ClaudeCode:*",
		desc = "Track Claude Code events",
		callback = function(args)
			-- Log important events
			-- Removed server status notifications - too noisy
		end,
	})

	-- Clean up on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = augroup,
		desc = "Cleanup Claude Code resources",
		callback = function()
			M.cleanup()
		end,
	})
end

-- Cleanup resources
function M.cleanup()
	-- Stop all timers
	for name, timer in pairs(timers) do
		if timer then
			timer:stop()
			timer:close()
			timers[name] = nil
		end
	end

	-- Clear autocommands
	vim.api.nvim_clear_autocmds({ group = augroup })
end

return M
