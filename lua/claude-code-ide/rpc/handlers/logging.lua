-- MCP logging handler
-- Provides logging level control

local log = require("claude-code-ide.log")

local M = {}

-- Log level mapping
local LOG_LEVELS = {
	debug = vim.log.levels.DEBUG,
	info = vim.log.levels.INFO,
	notice = vim.log.levels.INFO, -- Map notice to info
	warning = vim.log.levels.WARN,
	error = vim.log.levels.ERROR,
	critical = vim.log.levels.ERROR, -- Map critical to error
	alert = vim.log.levels.ERROR, -- Map alert to error
	emergency = vim.log.levels.ERROR, -- Map emergency to error
}

-- Set logging level
---@param rpc table RPC instance
---@param params table Request parameters with level
---@return table Empty response
function M.set_level(rpc, params)
	log.debug("Logging", "set_level called", params)
	
	if not params or not params.level then
		error("Logging level is required")
	end
	
	local level = params.level
	local vim_level = LOG_LEVELS[level]
	
	if not vim_level then
		error("Invalid logging level: " .. tostring(level))
	end
	
	-- Update the log module's level
	local config = require("claude-code-ide.config")
	if config and config.state and config.state.log then
		config.state.log.level = vim_level
		log.info("Logging", "Log level changed", { level = level })
	else
		log.warn("Logging", "Unable to update log level - config not available")
	end
	
	-- Also update Neovim's log level
	vim.lsp.set_log_level(level)
	
	return vim.empty_dict()
end

return M