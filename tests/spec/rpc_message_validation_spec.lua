-- Test for RPC message validation fix
local rpc_init = require("claude-code-ide.rpc.init")
local protocol = require("claude-code-ide.rpc.protocol")

describe("RPC Message Validation", function()
	it("should handle process_message without returning a value", function()
		-- Create a mock connection
		local mock_connection = {
			id = "test-connection",
		}

		-- Create RPC instance
		local rpc = rpc_init.new(mock_connection)

		-- Mock the websocket send_text function
		local sent_messages = {}
		package.loaded["claude-code.server.websocket"] = {
			send_text = function(conn, data)
				table.insert(sent_messages, data)
			end,
		}

		-- Send a valid tools/call request
		local request = vim.json.encode({
			jsonrpc = "2.0",
			id = 1,
			method = "tools/call",
			params = {
				name = "openDiff",
				arguments = {
					old_file_path = "/test/old.lua",
					new_file_path = "/test/new.lua",
					new_file_contents = "-- new content",
					tab_name = "Test Diff",
				},
			},
		})

		-- Process the message - should not return anything
		local result = rpc:process_message(request)
		assert.is_nil(result, "process_message should not return a value")

		-- Wait a bit for async processing
		vim.wait(100)

		-- Should have sent a response
		assert.is_true(#sent_messages > 0, "Should have sent at least one response")

		-- Parse the response
		local response = vim.json.decode(sent_messages[1])
		assert.equals("2.0", response.jsonrpc)
		assert.equals(1, response.id)
		-- Should have either result or error
		assert.is_true(response.result ~= nil or response.error ~= nil, "Response must have result or error")
	end)

	it("should validate messages correctly", function()
		-- Valid request
		assert.is_true(protocol.validate_message({
			jsonrpc = "2.0",
			method = "test",
			id = 1,
		}))

		-- Valid notification
		assert.is_true(protocol.validate_message({
			jsonrpc = "2.0",
			method = "test",
		}))

		-- Valid response with result
		assert.is_true(protocol.validate_message({
			jsonrpc = "2.0",
			id = 1,
			result = {},
		}))

		-- Valid error response
		assert.is_true(protocol.validate_message({
			jsonrpc = "2.0",
			id = 1,
			error = { code = -32600, message = "Invalid request" },
		}))

		-- Invalid - no method or result/error
		assert.is_false(protocol.validate_message({
			jsonrpc = "2.0",
			id = 1,
		}))

		-- Invalid - wrong version
		assert.is_false(protocol.validate_message({
			jsonrpc = "1.0",
			method = "test",
		}))
	end)
end)
