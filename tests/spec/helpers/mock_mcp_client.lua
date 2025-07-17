-- Mock MCP Client for Testing
-- Simulates a Claude CLI client connecting to the MCP server

local uv = vim.loop
local json = vim.json

local M = {}

-- Mock MCP Server
local MockServer = {}
MockServer.__index = MockServer

function MockServer.new()
	local self = setmetatable({}, MockServer)
	self.port = math.random(10000, 65535)
	self.auth_token = vim.fn.sha256(tostring(os.time()))
	self.initialized = false
	self.clients = {}
	self.tools = {}

	-- Register default tools
	self:_register_default_tools()

	return self
end

function MockServer:_register_default_tools()
	-- Register tools based on SPEC.md
	local tools = {
		{
			name = "openFile",
			description = "Open a file in the editor",
			inputSchema = {
				type = "object",
				properties = {
					filePath = { type = "string" },
					preview = { type = "boolean" },
					startText = { type = "string" },
					endText = { type = "string" },
					makeFrontmost = { type = "boolean" },
				},
				required = { "filePath" },
			},
		},
		{
			name = "openDiff",
			description = "Open a diff view",
			inputSchema = {
				type = "object",
				properties = {
					old_file_path = { type = "string" },
					new_file_path = { type = "string" },
					new_file_contents = { type = "string" },
					tab_name = { type = "string" },
				},
				required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
			},
		},
		{
			name = "getDiagnostics",
			description = "Get language diagnostics",
			inputSchema = {
				type = "object",
				properties = {
					uri = { type = "string" },
				},
			},
		},
		{
			name = "getCurrentSelection",
			description = "Get current text selection",
			inputSchema = {
				type = "object",
				properties = {},
			},
		},
		{
			name = "getOpenEditors",
			description = "Get open editors",
			inputSchema = {
				type = "object",
				properties = {},
			},
		},
		{
			name = "getWorkspaceFolders",
			description = "Get workspace folders",
			inputSchema = {
				type = "object",
				properties = {},
			},
		},
	}

	for _, tool in ipairs(tools) do
		self.tools[tool.name] = tool
	end
end

function MockServer:is_initialized()
	return self.initialized
end

function MockServer:close()
	-- Cleanup
end

-- Mock MCP Client
local MockClient = {}
MockClient.__index = MockClient

function MockClient.new()
	local self = setmetatable({}, MockClient)
	self.state = "disconnected"
	self.messages = {}
	self.request_id = 0
	self.capture_mode = false
	self.captured_messages = {}

	return self
end

function MockClient:connect(port, auth_token)
	-- Simulate connection
	if auth_token ~= M._current_server.auth_token then
		self.state = "unauthorized"
		self.last_error_code = 401
		return false
	end

	self.state = "connected"
	self.port = port
	self.auth_token = auth_token
	return true
end

function MockClient:request(method, params)
	if self.state ~= "connected" then
		return {
			jsonrpc = "2.0",
			error = {
				code = -32002,
				message = "Not connected",
			},
			id = self.request_id,
		}
	end

	-- Check if server is initialized for non-init methods
	if not M._current_server.initialized and method ~= "initialize" then
		return {
			jsonrpc = "2.0",
			error = {
				code = -32002,
				message = "Server not initialized",
			},
			id = self.request_id,
		}
	end

	self.request_id = self.request_id + 1
	local request = {
		jsonrpc = "2.0",
		method = method,
		params = params,
		id = self.request_id,
	}

	if self.capture_mode then
		table.insert(self.captured_messages, json.encode(request))
	end

	-- Simulate server responses
	if method == "initialize" then
		return {
			jsonrpc = "2.0",
			result = {
				protocolVersion = "2025-06-18",
				capabilities = {
					tools = { listChanged = true },
					resources = { listChanged = true },
				},
				serverInfo = {
					name = "claude-code-ide.nvim",
					version = "0.1.0",
				},
				instructions = "Neovim MCP server for Claude integration",
			},
			id = request.id,
		}
	elseif method == "tools/list" then
		return {
			jsonrpc = "2.0",
			result = {
				tools = vim.tbl_values(M._current_server.tools),
			},
			id = request.id,
		}
	elseif method == "tools/call" then
		local tool = M._current_server.tools[params.name]
		if not tool then
			return {
				jsonrpc = "2.0",
				error = {
					code = -32601,
					message = "Tool not found: " .. params.name,
				},
				id = request.id,
			}
		end

		-- Validate required arguments
		if tool.inputSchema.required then
			for _, required in ipairs(tool.inputSchema.required) do
				if params.arguments[required] == nil then
					return {
						jsonrpc = "2.0",
						error = {
							code = -32602,
							message = "Missing required parameter: " .. required,
						},
						id = request.id,
					}
				end
			end
		end

		-- Return mock response
		return {
			jsonrpc = "2.0",
			result = {
				content = {
					{
						type = "text",
						text = "Mock response for " .. params.name,
					},
				},
			},
			id = request.id,
		}
	end

	return {
		jsonrpc = "2.0",
		error = {
			code = -32601,
			message = "Method not found",
		},
		id = request.id,
	}
end

function MockClient:notify(method, params)
	if method == "notifications/initialized" then
		M._current_server.initialized = true
	end

	local notification = {
		jsonrpc = "2.0",
		method = method,
		params = params,
	}

	if self.capture_mode then
		table.insert(self.captured_messages, json.encode(notification))
	end
end

function MockClient:request_batch(requests)
	local responses = {}
	for _, req in ipairs(requests) do
		-- Use the request's ID if provided
		local old_id = self.request_id
		if req.id then
			self.request_id = req.id - 1 -- Will be incremented in request()
		end
		local response = self:request(req.method, req.params)
		if req.id then
			response.id = req.id
			self.request_id = old_id
		end
		table.insert(responses, response)
	end
	return responses
end

function MockClient:capture_next_message(fn)
	self.capture_mode = true
	self.captured_messages = {}
	fn()
	self.capture_mode = false
	return self.captured_messages[1]
end

function MockClient:close()
	self.state = "disconnected"
end

-- Module functions
function M.create_server()
	local server = MockServer.new()
	M._current_server = server
	return server
end

function M.create_client()
	return MockClient.new()
end

return M
