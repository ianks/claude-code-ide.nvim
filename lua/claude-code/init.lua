-- claude-code.nvim main module
-- Integration between Claude AI and Neovim

local M = {}
local notify = require("claude-code.ui.notify")

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
		server_name = "claude-code.nvim",
		server_version = "0.1.0",
		keymaps = {}, -- Default keymaps enabled
		autocmds = {}, -- Default autocmds enabled
	}, opts or {})

	-- Set up logging
	local log = require("claude-code.log")
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
		local keymaps = require("claude-code.keymaps")
		keymaps.setup(M._state.config.keymaps)
	end

	-- Setup autocommands unless disabled
	if M._state.config.autocmds ~= false then
		local autocmds = require("claude-code.autocmds")
		autocmds.setup(M._state.config.autocmds)
	end

	-- Setup resources system
	local resources = require("claude-code.resources")
	resources.setup()

	-- Setup cache system
	local cache = require("claude-code.cache")
	cache.setup()

	-- Setup statusline integration
	local statusline = require("claude-code.statusline")
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
	local server = require("claude-code.server")
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
	local server = require("claude-code.server")
	server.stop()
	M._state.server = nil

	-- Cleanup autocommands
	if M._state.config and M._state.config.autocmds ~= false then
		local autocmds = require("claude-code.autocmds")
		autocmds.cleanup()
	end

	-- Cleanup statusline
	local statusline = require("claude-code.statusline")
	statusline.stop()

	-- Shutdown cache system
	local cache = require("claude-code.cache")
	cache.shutdown()
end

-- Get current status
function M.status()
	local server = require("claude-code.server").get_server()
	return {
		initialized = M._state.initialized,
		server_running = server and server.running or false,
		config = M._state.config,
	}
end

return M
