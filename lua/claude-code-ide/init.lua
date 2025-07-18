-- claude-code-ide.nvim main module
-- Integration between Claude AI and Neovim

local M = {}
local notify = require("claude-code-ide.ui.notify")

-- Module state
M._state = {
	initialized = false,
	server = nil,
	config = nil,
}

-- Setup function
---@param opts table? User configuration
function M.setup(opts)
	if M._state.initialized then
		notify.warn("Already initialized")
		return
	end

	-- Default configuration
	M._state.config = vim.tbl_deep_extend("force", {
		port = 0,
		host = "127.0.0.1",
		debug = false,
		lock_file_dir = vim.fn.expand("~/.claude/ide"),
		server_name = "claude-code-ide.nvim",
		server_version = "0.1.0",
		keymaps = {}, -- Default keymaps enabled
		autocmds = {}, -- Default autocmds enabled
		auto_start = true, -- Auto-start server on setup
		statusline = true, -- Enable statusline component by default
	}, opts or {})

	-- Set up logging
	local log = require("claude-code-ide.log")
	if M._state.config.debug then
		log.set_level("DEBUG")
	else
		log.set_level("INFO")
	end

	-- Set debug log file globally if provided (for backward compatibility)
	if M._state.config.debug_log_file then
		vim.g.claude_code_debug_log_file = M._state.config.debug_log_file
	end

	-- Setup keymaps unless disabled
	if M._state.config.keymaps ~= false then
		-- Try the full keymaps module first, fall back to simple if it fails
		local ok, keymaps = pcall(require, "claude-code-ide.keymaps")
		if ok and keymaps.setup then
			local keymap_config = type(M._state.config.keymaps) == "table" and M._state.config.keymaps or {
				enabled = true,
				prefix = "<leader>c",
				mappings = {},
			}
			keymaps.setup(keymap_config)
		else
			-- Fall back to simple keymaps
			local simple_keymaps = require("claude-code-ide.keymaps_simple")
			simple_keymaps.setup(M._state.config.keymaps)
		end
	end

	-- Setup autocommands unless disabled
	if M._state.config.autocmds ~= false then
		local autocmds = require("claude-code-ide.autocmds")
		autocmds.setup(M._state.config.autocmds)
	end

	-- Setup resources system
	local resources = require("claude-code-ide.resources")
	resources.setup()

	-- Setup cache system
	local cache = require("claude-code-ide.cache")
	cache.setup()

	-- Setup statusline integration (enabled by default)
	if M._state.config.statusline ~= false then
		local statusline = require("claude-code-ide.statusline")
		statusline.setup()
		
		-- Add to global statusline if possible
		vim.schedule(function()
			-- Check if user has a custom statusline
			local has_custom_statusline = vim.o.statusline ~= ""
			
			if not has_custom_statusline then
				-- Add Claude status to default statusline
				vim.o.statusline = vim.o.statusline .. "%=%{v:lua.require('claude-code-ide.statusline').get_status()}"
			else
				-- Notify user how to add it to their custom statusline
				notify.info_with_action(
					"Claude Code statusline is ready. Add to your statusline with: %{v:lua.require('claude-code-ide.statusline').get_status()}",
					"<leader>cs",
					"view statusline docs",
					function()
						vim.cmd("help claude-code-statusline")
					end
				)
			end
		end)
	end
	
	-- Setup conversation UI
	local conversation = require("claude-code-ide.ui.conversation")
	conversation.setup()

	M._state.initialized = true

	-- Auto-start server if enabled (default: true for zero-friction experience)
	if M._state.config.auto_start ~= false then
		vim.defer_fn(function()
			M.start()
			notify.info("Claude Code server started automatically")
		end, 100)
	end
end

-- Start the server
function M.start()
	if not M._state.initialized then
		notify.error("Call setup() first")
		return
	end

	-- Initialize server
	local server = require("claude-code-ide.server")
	M._state.server = server.start(M._state.config)

	-- Setup commands if they exist
	local ok, commands = pcall(require, "claude-code.api.commands")
	if ok then
		commands.setup()
	end

	return M._state.server
end

-- Stop the server
function M.stop()
	local server = require("claude-code-ide.server")
	server.stop()
	M._state.server = nil

	-- Cleanup autocommands
	if M._state.config and M._state.config.autocmds ~= false then
		local autocmds = require("claude-code-ide.autocmds")
		autocmds.cleanup()
	end

	-- Cleanup statusline
	local statusline = require("claude-code-ide.statusline")
	statusline.stop()

	-- Shutdown cache system
	local cache = require("claude-code-ide.cache")
	cache.shutdown()
end

-- Get current status
function M.status()
	local server = require("claude-code-ide.server").get_server()
	return {
		initialized = M._state.initialized,
		server_running = server and server.running or false,
		config = M._state.config,
	}
end

return M
