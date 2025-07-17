-- MCP Server implementation for claude-code-ide.nvim
-- Main server coordination and lifecycle management

local uv = vim.loop
local json = vim.json
local events = require("claude-code-ide.events")
local log = require("claude-code-ide.log")
local notify = require("claude-code-ide.ui.notify")
local config = require("claude-code-ide.config")

local M = {}

-- Server instance
local Server = {}
Server.__index = Server

function Server.new(config)
	local self = setmetatable({}, Server)

	self.config = config or {}
	self.host = (self.config.server and self.config.server.host) or "127.0.0.1"
	self.port = (self.config.server and self.config.server.port) or 0 -- 0 means random port
	self.auth_token = vim.fn.sha256(tostring(os.time()) .. vim.fn.getpid())
	self.clients = {}
	self.tcp_server = nil
	self.initialized = false
	self.running = false

	-- MCP capabilities
	self.capabilities = {
		tools = { listChanged = true },
		resources = { listChanged = true },
	}

	-- Server info
	self.server_info = {
		name = self.config.server_name or "claude-code-ide.nvim",
		version = self.config.server_version or "0.1.0",
	}

	return self
end

-- Start the server
function Server:start()
	log.info("SERVER", "Starting MCP server", { host = self.host, port = self.port })

	-- Create TCP server
	self.tcp_server = uv.new_tcp()
	self.tcp_server:bind(self.host, self.port)

	-- Get actual port if random was chosen
	local sockname = self.tcp_server:getsockname()
	self.port = sockname.port

	log.info("SERVER", "Server bound to port", { port = self.port })

	-- Start listening
	self.tcp_server:listen(128, function(err)
		if err then
			log.error("SERVER", "Failed to start server", { error = err })
			notify.error("Failed to start server: " .. err)
			return
		end

		-- Accept new connection
		local client = uv.new_tcp()
		if client == nil then
			log.error("SERVER", "Failed to create client TCP handle")
			return
		end
		self.tcp_server:accept(client)

		log.debug("SERVER", "New connection accepted")

		-- Handle WebSocket connection
		local websocket = require("claude-code-ide.server.websocket")
		websocket.handle_connection(client, self)
	end)

	-- Set required environment variables for Claude IDE integration
	vim.env.ENABLE_IDE_INTEGRATION = "true"
	vim.env.CLAUDE_CODE_SSE_PORT = tostring(self.port)
	vim.env.CLAUDECODE = "1"
	vim.env.CLAUDE_CODE_ENTRYPOINT = "cli"

	-- Log environment setup in debug mode
	log.debug("SERVER", "Environment variables set", {
		ENABLE_IDE_INTEGRATION = "true",
		CLAUDE_CODE_SSE_PORT = tostring(self.port),
		CLAUDECODE = "1",
		CLAUDE_CODE_ENTRYPOINT = "cli",
	})

	-- Create lock file
	local discovery = require("claude-code-ide.discovery")
	local workspace = vim.fn.getcwd()
	self.lock_file_path = discovery.create_lock_file(self.port, self.auth_token, workspace)

	self.running = true
	-- Only show notification in debug mode
	if config.get("debug") then
		notify.success(string.format("MCP server started on port %d", self.port))
	end

	-- Emit server started event
	events.emit(events.events.SERVER_STARTED, {
		port = self.port,
		host = self.host,
		auth_token = self.auth_token,
	})

	return self
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
	if self.port then
		local discovery = require("claude-code-ide.discovery")
		discovery.delete_lock_file(self.port)
	end

	self.running = false
	-- Only show notification in debug mode
	if config.get("debug") then
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

function M.start(config)
	if current_server then
		M.stop()
	end

	current_server = Server.new(config)
	current_server:start()

	return current_server
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
