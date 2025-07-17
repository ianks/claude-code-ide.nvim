-- MCP Specification DSL
-- Provides a declarative way to specify and test MCP server behavior

local M = {}

-- Storage for spec definitions
M._specs = {
	server_info = nil,
	discovery = nil,
	connection = nil,
	environment_variables = {},
	initialization = nil,
	tools = {},
	security = nil,
	response_format = nil,
}

-- Current test context
local current_context = nil

-- Main describe function
function M.describe(name, fn)
	describe(name, function()
		current_context = name
		fn()
		current_context = nil
	end)
end

-- Server info specification
function M.server_info(info)
	M._specs.server_info = info

	it("should have correct server info", function()
		assert.is_string(info.name)
		assert.is_string(info.version)
		assert.equals("2025-06-18", info.protocol_version)
	end)
end

-- Discovery specification
function M.discovery(config)
	M._specs.discovery = config

	describe("discovery", function()
		it("should use correct lock file pattern", function()
			assert.equals("~/.claude/ide/<port>.lock", config.lock_file_pattern)
		end)

		it("should have valid lock file schema", function()
			local schema = config.lock_file_schema
			assert.equals("number", schema.pid)
			assert.equals("array", schema.workspaceFolders)
			assert.equals("string", schema.ideName)
			assert.equals("string", schema.transport)
			assert.equals("boolean", schema.runningInWindows)
			assert.equals("string", schema.authToken)
		end)

		it("should use correct port range", function()
			assert.equals(10000, config.port_range.min)
			assert.equals(65535, config.port_range.max)
		end)
	end)
end

-- Connection specification
function M.connection(config)
	M._specs.connection = config

	describe("connection", function()
		it("should use WebSocket transport", function()
			assert.equals("websocket", config.transport)
		end)

		it("should bind to localhost only", function()
			assert.equals("127.0.0.1", config.host)
		end)

		it("should use correct auth header", function()
			assert.equals("x-claude-code-ide-authorization", config.auth_header)
			assert.equals("uuid", config.auth_type)
		end)
	end)
end

-- Environment variables specification
function M.environment_variables(vars)
	M._specs.environment_variables = vars

	describe("environment variables", function()
		it("should set required environment variables", function()
			local expected = {
				ENABLE_IDE_INTEGRATION = "true",
				CLAUDE_CODE_SSE_PORT = "<port>",
			}

			for _, var in ipairs(vars) do
				assert.equals(expected[var.name], var.value)
			end
		end)
	end)
end

-- Initialization specification
function M.initialization(config)
	M._specs.initialization = config

	describe("initialization", function()
		it("should handle initialize request", function()
			local req = config.request
			assert.equals("initialize", req.method)
			assert.equals("2025-06-18", req.params.protocolVersion)
			assert.is_table(req.params.capabilities)
			assert.equals("Claude CLI", req.params.clientInfo.name)
		end)

		it("should send correct initialize response", function()
			local res = config.response
			assert.equals("2025-06-18", res.protocolVersion)
			assert.is_true(res.capabilities.tools.listChanged)
			assert.is_true(res.capabilities.resources.listChanged)
			assert.equals("claude-code-ide.nvim", res.serverInfo.name)
			assert.equals("0.1.0", res.serverInfo.version)
		end)
	end)
end

-- Tool specification
function M.tool(name, config)
	M._specs.tools[name] = config

	describe("tool: " .. name, function()
		it("should have required fields", function()
			assert.is_string(config.description)
			assert.is_table(config.input_schema)
			assert.is_string(config.response_format)
		end)

		if config.input_schema then
			it("should have valid input schema", function()
				for field, spec in pairs(config.input_schema) do
					if type(spec) == "table" then
						assert.is_string(spec.type)
						-- Check if required fields are marked
						if spec.required then
							assert.is_true(spec.required)
						end
					end
				end
			end)
		end

		if config.response_schema then
			it("should have valid response schema", function()
				assert.is_table(config.response_schema)
			end)
		end

		if config.implementation_notes then
			it("should have implementation notes", function()
				assert.is_table(config.implementation_notes)
				assert.is_true(#config.implementation_notes > 0)
			end)
		end
	end)
end

-- Security specification
function M.security(config)
	M._specs.security = config

	describe("security", function()
		it("should require correct lock file permissions", function()
			assert.equals("600", config.lock_file_permissions)
		end)

		it("should bind to localhost only", function()
			assert.equals("127.0.0.1", config.bind_address)
		end)

		it("should require authentication", function()
			assert.is_true(config.auth_required)
		end)

		it("should validate paths", function()
			assert.is_true(config.path_validation)
		end)
	end)
end

-- Response format specification
function M.response_format(config)
	M._specs.response_format = config

	describe("response format", function()
		it("should use MCP content format", function()
			assert.equals("content", config.type)
			assert.is_table(config.schema.content)
			assert.equals("array", config.schema.content.type)
		end)
	end)
end

-- Helper to generate implementation stubs from specs
function M.generate_implementation_stub(tool_name)
	local tool = M._specs.tools[tool_name]
	if not tool then
		error("Tool not found: " .. tool_name)
	end

	local stub = string.format(
		[[
-- Implementation for %s tool
-- %s

local M = {}

function M.handle_%s(params)
  -- Input parameters:
]],
		tool_name,
		tool.description,
		tool_name
	)

	for param, spec in pairs(tool.input_schema) do
		local info = type(spec) == "table" and spec or { type = spec }
		stub = stub .. string.format("  -- %s: %s%s\n", param, info.type, info.required and " (required)" or "")
	end

	stub = stub .. "\n  -- Implementation notes:\n"
	if tool.implementation_notes then
		for _, note in ipairs(tool.implementation_notes) do
			stub = stub .. "  -- * " .. note .. "\n"
		end
	end

	stub = stub
		.. [[

  -- TODO: Implement
  
  return {
    content = {
      {
        type = "text",
        text = "Not implemented"
      }
    }
  }
end

return M
]]

	return stub
end

-- Export specs for use by implementation
function M.get_specs()
	return vim.deepcopy(M._specs)
end

return M
