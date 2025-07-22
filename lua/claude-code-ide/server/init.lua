-- MCP Server implementation for claude-code-ide.nvim
-- Main server coordination and lifecycle management

local events = require("claude-code-ide.events")
local log = require("claude-code-ide.log")
local notify = require("claude-code-ide.ui.notify")
local config = require("claude-code-ide.config")
local auth = require("claude-code-ide.server.auth")

local M = {}

-- Server instance
local Server = {}
Server.__index = Server

function Server.new(full_config)
	local self = setmetatable({}, Server)

	self.config = full_config or {}
	-- Extract server-specific config
	local server_cfg = self.config.server or {}
	self.host = server_cfg.host or "127.0.0.1"
	self.port = server_cfg.port or 0 -- 0 means random port
	self.auth_token = auth.generate_token()
	self.clients = {}
	self.tcp_server = nil
	self.initialized = false
	self.running = false
	self.lock_file_path = nil

	-- MCP capabilities
	self.capabilities = {
		tools = { listChanged = true },
		resources = { listChanged = true },
	}

	-- Server info
	self.server_info = {
		name = "claude-code-ide.nvim",
		version = "0.1.0",
	}

	return self
end

-- Start the server
---@return boolean|nil success
---@return string|nil error
function Server:start()
	log.info("SERVER", "Starting MCP server", {
		host = self.host,
		port = self.port,
		has_config = self.config ~= nil,
		config_keys = self.config and vim.tbl_keys(self.config) or {},
	})

	-- Create TCP server
	self.tcp_server = vim.uv.new_tcp()
	if not self.tcp_server then
		return nil, "Failed to create TCP server"
	end

	local bind_ok, bind_err = self.tcp_server:bind(self.host, self.port)
	if not bind_ok then
		return nil, "Failed to bind server: " .. tostring(bind_err)
	end

	-- Get actual port if random was chosen
	local sockname = self.tcp_server:getsockname()
	if not sockname then
		return nil, "Failed to get socket name"
	end
	self.port = sockname.port

	log.info("SERVER", "Server bound to port", { port = self.port })

	-- Start listening
	local listen_ok, listen_err = self.tcp_server:listen(128, function(err)
		if err then
			log.error("SERVER", "Failed to accept connection", { error = err })
			return
		end

		-- Accept new connection
		local client = vim.uv.new_tcp()
		if not client then
			log.error("SERVER", "Failed to create client TCP handle")
			return
		end

		local accept_ok, accept_err = self.tcp_server:accept(client)
		if not accept_ok then
			log.error("SERVER", "Failed to accept client", { error = accept_err })
			client:close()
			return
		end

		log.debug("SERVER", "New connection accepted")

		-- Handle WebSocket connection
		local websocket = require("claude-code-ide.server.websocket")
		websocket.handle_connection(client, self)
	end)

	if not listen_ok then
		return nil, "Failed to start listening: " .. tostring(listen_err)
	end

	-- Set required environment variables for Claude IDE integration
	vim.env.ENABLE_IDE_INTEGRATION = "true"
	vim.env.CLAUDE_CODE_SSE_PORT = tostring(self.port)
	vim.env.CLAUDECODE = "1"
	vim.env.CLAUDE_CODE_ENTRYPOINT = "cli"

	-- Create lock file
	local discovery = require("claude-code-ide.server.discovery")
	local lock_dir = self.config.lock_file and self.config.lock_file.dir or vim.fn.expand("~/.claude/ide")
	local lock_path = vim.fs.joinpath(lock_dir, tostring(self.port) .. ".lock")

	log.info("SERVER", "Creating lock file", {
		lock_dir = lock_dir,
		lock_path = lock_path,
		port = self.port,
	})

	local lock_ok, lock_err = discovery.create_lock_file(self.port, self.auth_token, lock_path)
	if not lock_ok then
		self:stop()
		return nil, "Failed to create lock file: " .. tostring(lock_err)
	end

	self.lock_file_path = lock_path
	self.running = true

	-- Only show notification in debug mode
	if self.config.debug and self.config.debug.enabled then
		notify.success(string.format("MCP server started on port %d", self.port))
	end

	-- Emit server started event
	events.emit(events.events.SERVER_STARTED, {
		port = self.port,
		host = self.host,
		auth_token = self.auth_token,
	})

	return true
end

-- Stop the server
function Server:stop()
	-- Close all client connections
	for _id, client in pairs(self.clients) do
		if client.socket then
			client.socket:close()
		end
	end
	self.clients = {}

	-- Close server socket
	if self.tcp_server then
		self.tcp_server:close()
		self.tcp_server = nil
	end

	-- Remove lock file
	if self.lock_file_path then
		local discovery = require("claude-code-ide.server.discovery")
		discovery.remove_lock_file(self.lock_file_path)
		self.lock_file_path = nil
	end

	self.running = false

	-- Only show notification in debug mode
	if self.config.debug and self.config.debug.enabled then
		notify.info("MCP server stopped")
	end

	-- Emit server stopped event
	events.emit(events.events.SERVER_STOPPED, {
		port = self.port,
	})
end

-- Add client connection
function Server:add_client(id, connection)
	self.clients[id] = connection
end

-- Remove client connection
function Server:remove_client(id)
	self.clients[id] = nil
end

-- Get server info for MCP
function Server:get_info()
	return {
		port = self.port,
		auth_token = self.auth_token,
		capabilities = self.capabilities,
		server_info = self.server_info,
		initialized = self.initialized,
	}
end

-- Module functions
local current_server = nil

---@param server_config table|nil
---@return table|nil server
---@return string|nil error
function M.start(server_config)
	if current_server then
		M.stop()
	end

	-- Create new server instance
	local ok, server_or_err = pcall(Server.new, server_config)
	if not ok then
		return nil, "Failed to create server: " .. tostring(server_or_err)
	end

	current_server = server_or_err
	local start_ok, start_err = current_server:start()
	if not start_ok then
		current_server = nil
		return nil, start_err
	end

	return current_server, nil
end

function M.stop()
	if current_server then
		current_server:stop()
		current_server = nil
	end
end

function M.get_server()
	return current_server
end

return M
