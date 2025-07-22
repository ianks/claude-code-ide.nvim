-- Test RPC compatibility with real-world interactions
-- Validates schema format, protocol compliance, and response structure

local rpc_init = require("claude-code-ide.rpc.init")
local protocol = require("claude-code-ide.rpc.protocol")
local tools = require("claude-code-ide.tools")

describe("RPC Real-world Compatibility", function()
	-- Mock connection for testing
	local function create_mock_connection()
		return {
			id = "test-session-" .. math.random(10000),
		}
	end

	-- Mock websocket for response capture
	local function setup_response_capture()
		local captured_responses = {}
		package.loaded["claude-code-ide.server.websocket"] = {
			send_text = function(conn, data)
				table.insert(captured_responses, data)
			end,
		}
		return captured_responses
	end

	describe("Protocol compliance", function()
		it("should validate JSON-RPC 2.0 messages correctly", function()
			-- Valid initialize request from real logs
			assert.is_true(protocol.validate_message({
				jsonrpc = "2.0",
				id = 1,
				method = "initialize",
				params = {
					protocolVersion = "2025-06-18",
					capabilities = { roots = {} },
					clientInfo = { name = "claude-code", version = "1.0.53" },
				},
			}))

			-- Valid tools/call request from real logs
			assert.is_true(protocol.validate_message({
				jsonrpc = "2.0",
				id = 2,
				method = "tools/call",
				params = {
					name = "getWorkspaceFolders",
					arguments = {},
				},
			}))

			-- Valid notification from real logs
			assert.is_true(protocol.validate_message({
				jsonrpc = "2.0",
				method = "ide_connected",
				params = { pid = 27519 },
			}))

			-- Invalid message should fail
			assert.is_false(protocol.validate_message({
				jsonrpc = "1.0", -- Wrong version
				method = "test",
			}))
		end)

		it("should create responses in correct format", function()
			local response = protocol.create_response(1, { test = "data" })
			assert.equals("2.0", response.jsonrpc)
			assert.equals(1, response.id)
			assert.equals("data", response.result.test)
			assert.is_nil(response.error)
		end)

		it("should create error responses in correct format", function()
			local error_response = protocol.create_error_response(1, -32601, "Method not found")
			assert.equals("2.0", error_response.jsonrpc)
			assert.equals(1, error_response.id)
			assert.is_nil(error_response.result)
			assert.equals(-32601, error_response.error.code)
			assert.equals("Method not found", error_response.error.message)
		end)
	end)

	describe("Schema format compliance", function()
		it("should return tool schemas with required real-world format", function()
			-- Get all tools
			local tool_list = tools.list()
			assert.truthy(tool_list)
			assert.True(#tool_list > 0)

			-- Find openFile tool (key tool from real logs)
			local openFile = nil
			for _, tool in ipairs(tool_list) do
				if tool.name == "openFile" then
					openFile = tool
					break
				end
			end

			assert.truthy(openFile, "openFile tool should exist")

			-- Verify schema has all required real-world fields
			local schema = openFile.inputSchema
			assert.truthy(schema)
			assert.equals("object", schema.type)

			-- CRITICAL: These fields are required by real Claude Code
			assert.equals(false, schema.additionalProperties)
			assert.equals("http://json-schema.org/draft-07/schema#", schema["$schema"])

			-- Verify properties structure
			assert.truthy(schema.properties)
			assert.truthy(schema.properties.filePath)
			assert.equals("string", schema.properties.filePath.type)

			-- Verify required array
			assert.truthy(schema.required)
			assert.True(vim.tbl_contains(schema.required, "filePath"))
		end)

		it("should have consistent schema format across all tools", function()
			local tool_list = tools.list()

			for _, tool in ipairs(tool_list) do
				if tool.inputSchema then
					local schema = tool.inputSchema

					-- All schemas must have these fields for real-world compatibility
					assert.equals("object", schema.type, "Tool " .. tool.name .. " schema type")
					assert.equals(false, schema.additionalProperties, "Tool " .. tool.name .. " additionalProperties")
					assert.equals(
						"http://json-schema.org/draft-07/schema#",
						schema["$schema"],
						"Tool " .. tool.name .. " $schema"
					)

					-- Properties and required should be present
					assert.truthy(schema.properties, "Tool " .. tool.name .. " should have properties")
					assert.truthy(schema.required, "Tool " .. tool.name .. " should have required array")
				end
			end
		end)
	end)

	describe("Handler registry compliance", function()
		it("should handle initialize request with both tools and resources capabilities", function()
			local mock_conn = create_mock_connection()
			local responses = setup_response_capture()
			local rpc = rpc_init.new(mock_conn)

			-- Send initialize request like real Claude Code
			local request = vim.json.encode({
				jsonrpc = "2.0",
				id = 1,
				method = "initialize",
				params = {
					protocolVersion = "2025-06-18",
					capabilities = { roots = {} },
					clientInfo = { name = "claude-code", version = "1.0.53" },
				},
			})

			rpc:process_message(request)
			vim.wait(50) -- Allow async processing

			assert.True(#responses > 0, "Should send initialize response")

			local response = vim.json.decode(responses[1])
			assert.equals("2.0", response.jsonrpc)
			assert.equals(1, response.id)
			assert.truthy(response.result)

			-- CRITICAL: Must have both capabilities from real logs
			assert.truthy(response.result.capabilities.tools)
			assert.equals(true, response.result.capabilities.tools.listChanged)
			assert.truthy(response.result.capabilities.resources)
			assert.equals(true, response.result.capabilities.resources.listChanged)
		end)

		it("should handle ide_connected notification without response", function()
			local mock_conn = create_mock_connection()
			local responses = setup_response_capture()
			local rpc = rpc_init.new(mock_conn)

			-- Send ide_connected notification (no id = notification)
			local notification = vim.json.encode({
				jsonrpc = "2.0",
				method = "ide_connected",
				params = { pid = 27519 },
			})

			rpc:process_message(notification)
			vim.wait(50)

			-- Notifications should not generate responses
			assert.equals(0, #responses, "Notifications should not generate responses")
		end)
	end)

	describe("Tools/call compatibility", function()
		it("should return MCP-compliant content format", function()
			local mock_conn = create_mock_connection()
			local responses = setup_response_capture()
			local rpc = rpc_init.new(mock_conn)

			-- Test getWorkspaceFolders which should work reliably
			local request = vim.json.encode({
				jsonrpc = "2.0",
				id = 1,
				method = "tools/call",
				params = {
					name = "getWorkspaceFolders",
					arguments = {},
				},
			})

			rpc:process_message(request)
			vim.wait(100) -- Allow async processing

			assert.True(#responses > 0, "Should send tool response")

			local response = vim.json.decode(responses[1])
			assert.equals("2.0", response.jsonrpc)
			assert.equals(1, response.id)
			assert.truthy(response.result)

			-- CRITICAL: Must follow MCP content format from real logs
			assert.truthy(response.result.content)
			assert.equals("table", type(response.result.content))

			-- Each content item must have type and text
			for _, content_item in ipairs(response.result.content) do
				assert.truthy(content_item.type)
				assert.truthy(content_item.text)
				assert.equals("text", content_item.type)
			end
		end)
	end)
end)
