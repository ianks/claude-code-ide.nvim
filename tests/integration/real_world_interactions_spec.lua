-- Integration tests based on real-world MCP interactions from tmp/logs.json
-- This test file validates our implementation against actual Claude Code behavior

local helpers = require("tests.integration.helpers.setup")
local async = require("plenary.async")

describe("Real-world MCP interactions", function()
	local function create_test_client(server, lock_file)
		local client = helpers.create_client(server.port, lock_file.authToken)

		-- Initialize the connection as Claude Code does
		local init_response = client:request("initialize", {
			protocolVersion = "2025-06-18",
			capabilities = {
				roots = {},
			},
			clientInfo = {
				name = "claude-code",
				version = "1.0.53",
			},
		})

		helpers.assert_successful_response(init_response)

		-- Send initialized notification
		client:notify("notifications/initialized")

		return client
	end

	describe("Connection handshake", function()
		it("should complete initialize/initialized handshake like Claude Code", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Initialize request
				local init_response = client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {
						roots = {},
					},
					clientInfo = {
						name = "claude-code",
						version = "1.0.53",
					},
				})

				-- Verify response matches expected format
				local result = helpers.assert_successful_response(init_response)
				assert.equals("2025-06-18", result.protocolVersion)
				assert.truthy(result.capabilities)

				-- CRITICAL: Must have BOTH tools AND resources capabilities (from real logs)
				assert.truthy(result.capabilities.tools)
				assert.equals(true, result.capabilities.tools.listChanged)
				assert.truthy(result.capabilities.resources)
				assert.equals(true, result.capabilities.resources.listChanged)

				assert.truthy(result.serverInfo)
				assert.equals("claude-code-ide.nvim", result.serverInfo.name)
				assert.truthy(result.serverInfo.version)

				-- Send initialized notification
				client:notify("notifications/initialized")

				-- Small delay to ensure notification is processed
				vim.wait(50)
			end)
		end)

		it("should handle ide_connected notification", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				-- Send ide_connected notification (no response expected)
				client:notify("ide_connected", {
					pid = 27519,
				})

				-- Small delay to ensure notification is processed
				vim.wait(50)

				-- Server should still be responsive
				local response = client:request("tools/list")
				helpers.assert_successful_response(response)
			end)
		end)
	end)

	describe("Schema format compatibility", function()
		it("should return tool schemas with exact real-world format", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				local response = client:request("tools/list")
				local result = helpers.assert_successful_response(response)

				assert.truthy(result.tools)
				assert.True(#result.tools > 0)

				-- Find openFile tool to test schema format
				local openFile = nil
				for _, tool in ipairs(result.tools) do
					if tool.name == "openFile" then
						openFile = tool
						break
					end
				end

				assert.truthy(openFile, "openFile tool should exist")

				-- Verify exact schema format from real logs
				local schema = openFile.inputSchema
				assert.truthy(schema)
				assert.equals("object", schema.type)
				assert.equals(false, schema.additionalProperties) -- CRITICAL: Must be false
				assert.equals("http://json-schema.org/draft-07/schema#", schema["$schema"]) -- CRITICAL: Must have $schema

				-- Verify properties structure
				assert.truthy(schema.properties)
				assert.truthy(schema.properties.filePath)
				assert.equals("string", schema.properties.filePath.type)

				-- Verify required array format
				assert.truthy(schema.required)
				assert.True(#schema.required >= 1)
				assert.True(vim.tbl_contains(schema.required, "filePath"))
			end)
		end)

		it("should return resource schemas with correct format", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				local response = client:request("resources/list")
				local result = helpers.assert_successful_response(response)

				assert.truthy(result.resources)
				-- Resources may be empty but should be valid array
				assert.equals("table", type(result.resources))
			end)
		end)
	end)

	describe("Tool execution compatibility", function()
		it("should return MCP-compliant content format for tool responses", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)

					-- Test getWorkspaceFolders which should have deterministic output
					local response = client:request("tools/call", {
						name = "getWorkspaceFolders",
						arguments = {},
					})

					local result = helpers.assert_successful_response(response)

					-- CRITICAL: Must follow MCP content format from real logs
					assert.truthy(result.content)
					assert.equals("array", type(result.content))
					assert.True(#result.content > 0)

					-- Each content item must have type and text
					for _, content_item in ipairs(result.content) do
						assert.truthy(content_item.type)
						assert.truthy(content_item.text)
						assert.equals("text", content_item.type) -- Real logs show "text" type
					end
				end)
			end)
		end)

		it("should handle tool execution errors in MCP format", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				-- Call openFile with invalid arguments
				local response = client:request("tools/call", {
					name = "openFile",
					arguments = {
						filePath = "/nonexistent/file/that/should/not/exist.txt",
					},
				})

				-- Should still return success with error content, not JSON-RPC error
				local result = helpers.assert_successful_response(response)
				assert.truthy(result.content)
				assert.equals("array", type(result.content))
			end)
		end)

		it("should handle getDiagnostics with optional parameters", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)

					-- Test getDiagnostics without uri parameter (should be optional)
					local response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {},
					})

					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("array", type(result.content))
				end)
			end)
		end)
	end)

	describe("Tools listing", function()
		it("should return all expected tools in the same format as VSCode", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				local response = client:request("tools/list")
				local result = helpers.assert_successful_response(response)

				assert.truthy(result.tools)
				assert.True(#result.tools > 0)

				-- Check for expected tools from the log
				local tool_names = {}
				for _, tool in ipairs(result.tools) do
					tool_names[tool.name] = tool
				end

				-- Verify tools match those in the log
				assert.truthy(tool_names.openDiff)
				assert.truthy(tool_names.getDiagnostics)
				assert.truthy(tool_names.close_tab)
				assert.truthy(tool_names.closeAllDiffTabs)
				assert.truthy(tool_names.openFile)
				assert.truthy(tool_names.getOpenEditors)
				assert.truthy(tool_names.getWorkspaceFolders)
				assert.truthy(tool_names.getCurrentSelection)

				-- Verify openFile schema matches exactly
				local openFile = tool_names.openFile
				assert.equals("Open a file in the editor and optionally select text", openFile.description)
				assert.truthy(openFile.inputSchema)
				assert.equals("object", openFile.inputSchema.type)
				assert.equals(false, openFile.inputSchema.additionalProperties)
				assert.equals("http://json-schema.org/draft-07/schema#", openFile.inputSchema["$schema"])

				assert.truthy(openFile.inputSchema.properties.filePath)
				assert.truthy(openFile.inputSchema.properties.preview)
				assert.truthy(openFile.inputSchema.properties.startText)
				assert.truthy(openFile.inputSchema.properties.endText)
				assert.truthy(openFile.inputSchema.properties.makeFrontmost)

				-- Verify getDiagnostics schema
				local getDiagnostics = tool_names.getDiagnostics
				assert.truthy(getDiagnostics.inputSchema)
				assert.truthy(getDiagnostics.inputSchema.properties.uri)
				-- The uri parameter is optional (not in required array)
				assert.truthy(getDiagnostics.inputSchema.required)
				assert.equals(0, #getDiagnostics.inputSchema.required)
			end)
		end)
	end)

	describe("JSON-RPC 2.0 compliance", function()
		it("should handle malformed requests gracefully", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Send malformed JSON-RPC request
				local response = client:send_raw('{"jsonrpc":"2.0","method":"invalid_method","id":1}')

				-- Should receive proper JSON-RPC error
				assert.truthy(response)
				assert.truthy(response.error)
				assert.equals(-32601, response.error.code) -- Method not found
			end)
		end)

		it("should validate request ID types correctly", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				-- Test with string ID
				local response = client:request_with_id("tools/list", {}, "string-id")
				local result = helpers.assert_successful_response(response)
				assert.truthy(result.tools)

				-- Test with number ID
				local response2 = client:request_with_id("tools/list", {}, 12345)
				local result2 = helpers.assert_successful_response(response2)
				assert.truthy(result2.tools)
			end)
		end)
	end)

	describe("Event notifications", function()
		it("should handle selection_changed notifications", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)

					-- Create and open a test file
					local test_file = workspace .. "/test.lua"
					helpers.write_file(test_file, "local hello = 'world'")
					vim.cmd("edit " .. test_file)

					-- Send selection_changed notification matching log format
					client:notify("selection_changed", {
						file = test_file,
						selection = {
							start = { line = 1, character = 0 },
							["end"] = { line = 1, character = 5 },
						},
					})

					-- Small delay to ensure notification is processed
					vim.wait(50)

					-- Server should still be responsive
					local response = client:request("tools/list")
					helpers.assert_successful_response(response)
				end)
			end)
		end)

		it("should handle text_changed notifications", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)

					-- Create and open a test file
					local test_file = workspace .. "/test.lua"
					helpers.write_file(test_file, "local hello = 'world'")
					vim.cmd("edit " .. test_file)

					-- Send text_changed notification
					client:notify("text_changed", {
						file = test_file,
						content = "local hello = 'universe'",
					})

					-- Small delay to ensure notification is processed
					vim.wait(50)

					-- Server should still be responsive
					local response = client:request("tools/list")
					helpers.assert_successful_response(response)
				end)
			end)
		end)
	end)

	describe("Performance and reliability", function()
		it("should handle rapid tool requests without errors", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				-- Send multiple rapid requests
				local responses = {}
				for i = 1, 10 do
					responses[i] = client:request("getWorkspaceFolders", {})
				end

				-- All should succeed
				for i = 1, 10 do
					local result = helpers.assert_successful_response(responses[i])
					assert.truthy(result.content)
				end
			end)
		end)

		it("should maintain session state across multiple requests", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)

				-- Multiple requests should maintain consistent session
				local response1 = client:request("tools/list")
				local result1 = helpers.assert_successful_response(response1)

				local response2 = client:request("tools/list")
				local result2 = helpers.assert_successful_response(response2)

				-- Should return identical tool lists
				assert.equals(#result1.tools, #result2.tools)
			end)
		end)
	end)
end)
