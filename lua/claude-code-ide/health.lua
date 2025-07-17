local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
	start("claude-code-ide.nvim")

	-- Check Neovim version
	local nvim_version = vim.version()
	if nvim_version.major > 0 or nvim_version.minor >= 9 then
		ok(string.format("Neovim version %d.%d.%d", nvim_version.major, nvim_version.minor, nvim_version.patch))
	else
		error("Neovim 0.9.0+ required", "Install latest Neovim")
	end

	-- Check required dependencies
	start("Dependencies")

	-- plenary.nvim
	local has_plenary = pcall(require, "plenary")
	if has_plenary then
		ok("plenary.nvim found")
	else
		error("plenary.nvim not found", "Install with your package manager")
	end

	-- Optional dependencies
	local has_snacks = pcall(require, "snacks")
	if has_snacks then
		ok("snacks.nvim found (optional)")
	else
		info("snacks.nvim not found (optional UI enhancements)")
	end

	local has_nio = pcall(require, "nio")
	if has_nio then
		ok("nvim-nio found (optional)")
	else
		info("nvim-nio not found (optional async enhancements)")
	end

	-- Check system dependencies
	start("System Dependencies")

	-- openssl
	local openssl = vim.fn.executable("openssl")
	if openssl == 1 then
		local version = vim.fn.system("openssl version"):gsub("\n", "")
		ok("openssl: " .. version)
	else
		error("openssl not found", "Install openssl for WebSocket support")
	end

	-- Claude CLI
	local claude = vim.fn.executable("claude")
	if claude == 1 then
		ok("claude CLI found")
	else
		warn("claude CLI not found", "Install from https://claude.ai/download")
	end

	-- Check configuration
	start("Configuration")

	local config = require("claude-code-ide.config")
	local lock_dir = vim.fn.expand(config.options.lock_file_dir)
	
	-- Check lock file directory
	if vim.fn.isdirectory(lock_dir) == 1 then
		ok("Lock file directory exists: " .. lock_dir)
		
		-- Check permissions
		local stat = vim.loop.fs_stat(lock_dir)
		if stat and stat.mode then
			local perms = string.format("%o", stat.mode)
			info("Lock directory permissions: " .. perms)
		end
	else
		info("Lock file directory will be created: " .. lock_dir)
	end

	-- Check server status
	start("Server Status")

	local server = require("claude-code-ide.server")
	if server.is_running() then
		local status = server.get_status()
		ok(string.format("MCP server running on port %d", status.port))
		info(string.format("Lock file: %s", status.lock_file))
		
		-- Check if Claude is connected
		local client_count = status.client_count or 0
		if client_count > 0 then
			ok(string.format("%d client(s) connected", client_count))
		else
			info("No clients connected (run 'claude --ide' to connect)")
		end
	else
		info("MCP server not running (use :lua require('claude-code-ide').start())")
	end

	-- Check for common issues
	start("Common Issues")

	-- Port availability
	local test_port = config.options.port
	if test_port == 0 then
		info("Using random port (recommended)")
	else
		-- Try to check if port is available
		local tcp = vim.loop.new_tcp()
		local bind_ok = pcall(tcp.bind, tcp, "127.0.0.1", test_port)
		if bind_ok then
			ok(string.format("Port %d is available", test_port))
			tcp:close()
		else
			warn(string.format("Port %d may be in use", test_port), "Use port = 0 for random port")
		end
	end

	-- Log file
	local log_file = require("claude-code-ide.log").get_log_file()
	if vim.fn.filereadable(log_file) == 1 then
		local size = vim.fn.getfsize(log_file)
		if size > 10 * 1024 * 1024 then -- 10MB
			warn(string.format("Log file is large: %.1f MB", size / 1024 / 1024), "Consider clearing with :ClaudeCodeCacheClear")
		else
			info(string.format("Log file: %s (%.1f KB)", log_file, size / 1024))
		end
	end
end

return M