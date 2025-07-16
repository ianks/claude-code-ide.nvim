-- Integration tests for claude-code server
-- Tests real WebSocket connections and MCP protocol flow

local helpers = require("tests.integration.helpers.setup")

describe("Server Integration", function()
	it("starts server and creates lock file", function()
		helpers.with_real_server({}, function(server, config)
			-- Verify server is running
			assert.truthy(server)
			assert.truthy(server.port)
			assert.equals("running", server.state)

			-- Verify lock file exists
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			assert.truthy(lock_file)
			assert.equals(server.port, lock_file.port)
			assert.truthy(lock_file.authToken)
			assert.equals("test-server", lock_file.name)
			assert.equals("0.1.0", lock_file.version)
		end)
	end)

	it("completes full MCP handshake", function()
		helpers.with_real_server({}, function(server, config)
			-- Get auth token from lock file
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			assert.truthy(lock_file)

			-- Create real WebSocket client
			local client = helpers.create_client(server.port, lock_file.authToken)

			-- Send initialize request
			local response = client:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = {
					name = "Test Client",
					version = "1.0.0",
				},
			})

			-- Verify response
			local result = helpers.assert_successful_response(response)
			assert.equals("2025-06-18", result.protocolVersion)
			assert.equals("claude-code.nvim", result.serverInfo.name)
			assert.truthy(result.serverInfo.version)
			assert.truthy(result.capabilities)

			-- Send initialized notification
			client:notify("initialized", {})

			-- Clean shutdown
			client:close()
		end)
	end)

	it("lists available tools", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			local client = helpers.create_client(server.port, lock_file.authToken)

			-- Initialize connection
			client:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Test", version = "1.0" },
			})
			client:notify("initialized", {})

			-- List tools
			local response = client:request("tools/list", {})
			local result = helpers.assert_successful_response(response)

			-- Verify tools
			assert.truthy(result.tools)
			assert.is_true(#result.tools > 0)

			-- Check for expected tools
			local tool_names = {}
			for _, tool in ipairs(result.tools) do
				tool_names[tool.name] = true
			end

			assert.truthy(tool_names["openFile"])
			assert.truthy(tool_names["openDiff"])
			assert.truthy(tool_names["getDiagnostics"])
			assert.truthy(tool_names["getCurrentSelection"])
			assert.truthy(tool_names["getOpenEditors"])
			assert.truthy(tool_names["getWorkspaceFolders"])

			client:close()
		end)
	end)

	it("handles multiple concurrent connections", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)

			-- Create multiple clients
			local clients = {}
			for i = 1, 3 do
				clients[i] = helpers.create_client(server.port, lock_file.authToken)
			end

			-- Initialize all clients
			for i, client in ipairs(clients) do
				local response = client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = { name = "Test " .. i, version = "1.0" },
				})
				assert.truthy(response.result)
			end

			-- Make concurrent requests
			local responses = {}
			for i, client in ipairs(clients) do
				-- Use coroutine to make requests concurrently
				local co = coroutine.create(function()
					client:notify("initialized", {})
					local resp = client:request("tools/list", {})
					responses[i] = resp
				end)
				coroutine.resume(co)
			end

			-- Wait for all responses
			vim.wait(500, function()
				return #responses == 3
			end)

			-- Verify all got valid responses
			for i = 1, 3 do
				assert.truthy(responses[i])
				assert.truthy(responses[i].result)
				assert.truthy(responses[i].result.tools)
			end

			-- Cleanup
			for _, client in ipairs(clients) do
				client:close()
			end
		end)
	end)

	it("rejects unauthorized connections", function()
		helpers.with_real_server({}, function(server, config)
			-- Try to connect with wrong auth token
			local client = require("tests.integration.helpers.websocket_client").new()

			-- This should fail during handshake
			local ok, err = pcall(function()
				client:connect("127.0.0.1", server.port, "wrong-token")
			end)

			assert.is_false(ok)
			-- Connection should be rejected
		end)
	end)

	it("handles server shutdown gracefully", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			local client = helpers.create_client(server.port, lock_file.authToken)

			-- Initialize
			client:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Test", version = "1.0" },
			})

			-- Stop server
			server:stop()

			-- Verify server state
			assert.equals("stopped", server.state)

			-- Lock file should be removed
			vim.wait(100)
			local lock_file_after = helpers.get_lock_file(server.port, config.lock_file_dir)
			assert.is_nil(lock_file_after)

			-- Client operations should fail
			local ok = pcall(function()
				client:request("tools/list", {})
			end)
			assert.is_false(ok)
		end)
	end)

	it("handles malformed requests", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			local client = helpers.create_client(server.port, lock_file.authToken)

			-- Send malformed request (missing required fields)
			local response = client:request("initialize", {
				-- Missing protocolVersion
				capabilities = {},
			})

			-- Should get error response
			assert.truthy(response.error)
			assert.equals(-32602, response.error.code) -- Invalid params

			client:close()
		end)
	end)

	it("supports batch requests", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			local client = helpers.create_client(server.port, lock_file.authToken)

			-- Initialize first
			client:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Test", version = "1.0" },
			})
			client:notify("initialized", {})

			-- Send batch request
			client:send({
				{
					jsonrpc = "2.0",
					id = 100,
					method = "tools/list",
					params = {},
				},
				{
					jsonrpc = "2.0",
					id = 101,
					method = "resources/list",
					params = {},
				},
			})

			-- Wait for both responses
			local responses = {}
			client.pending_requests[100] = function(msg)
				responses[100] = msg
			end
			client.pending_requests[101] = function(msg)
				responses[101] = msg
			end

			vim.wait(1000, function()
				return responses[100] and responses[101]
			end)

			-- Verify both responses
			assert.truthy(responses[100])
			assert.truthy(responses[100].result.tools)
			assert.truthy(responses[101])
			assert.truthy(responses[101].result.resources)

			client:close()
		end)
	end)
end)