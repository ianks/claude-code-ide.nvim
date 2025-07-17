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
		local keymaps = require("claude-code-ide.keymaps")
		keymaps.setup(M._state.config.keymaps)
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

	-- Setup statusline integration
	local statusline = require("claude-code-ide.statusline")
	statusline.setup()

	M._state.initialized = true
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
