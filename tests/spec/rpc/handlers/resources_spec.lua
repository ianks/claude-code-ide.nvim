-- Tests for MCP resources RPC handlers

local resources_handler = require("claude-code-ide.rpc.handlers.resources")
local resources = require("claude-code-ide.resources")

describe("RPC Resources Handler", function()
	local mock_rpc

	before_each(function()
		-- Clear all resources
		for _, resource in ipairs(resources.list()) do
			resources.unregister(resource.uri)
		end

		-- Mock RPC instance
		mock_rpc = {
			connection = {},
		}

		-- Register some test resources
		resources.register("file:///test1.lua", "Test File 1", "First test file", "text/x-lua")
		resources.register("file:///test2.py", "Test File 2", "Second test file", "text/x-python")
		resources.register("template://test", "Test Template", "A test template", "text/plain")
	end)

	describe("list_resources", function()
		it("should return all registered resources", function()
			local result = resources_handler.list_resources(mock_rpc, {})

			assert.truthy(result.resources)
			assert.equals(3, #result.resources)

			-- Check resource format
			local resource = result.resources[1]
			assert.truthy(resource.uri)
			assert.truthy(resource.name)
			assert.truthy(resource.mimeType)
		end)

		it("should handle pagination for large resource lists", function()
			-- Register many resources
			for i = 1, 150 do
				resources.register("file:///test" .. i .. ".txt", "Test " .. i, nil, "text/plain")
			end

			-- First page
			local result1 = resources_handler.list_resources(mock_rpc, { cursor = "1" })
			assert.equals(100, #result1.resources)
			assert.truthy(result1.nextCursor)
			assert.equals("101", result1.nextCursor)

			-- Second page
			local result2 = resources_handler.list_resources(mock_rpc, { cursor = result1.nextCursor })
			assert.is_true(#result2.resources > 0)
			assert.is_nil(result2.nextCursor) -- No more pages
		end)

		it("should return all resources when no cursor provided", function()
			local result = resources_handler.list_resources(mock_rpc, {})
			assert.equals(3, #result.resources)
			assert.is_nil(result.nextCursor)
		end)
	end)

	describe("read_resource", function()
		it("should read a registered resource", function()
			-- Create a temp file
			local temp_file = vim.fn.tempname()
			local file = io.open(temp_file, "w")
			file:write("Test content")
			file:close()

			-- Register it
			resources.register("file://" .. temp_file, "Temp File", nil, "text/plain")

			-- Read it via RPC
			local result = resources_handler.read_resource(mock_rpc, { uri = "file://" .. temp_file })

			assert.truthy(result)
			assert.truthy(result.contents)
			assert.equals(1, #result.contents)
			assert.equals("Test content", result.contents[1].text)
			assert.equals("text/plain", result.contents[1].mimeType)

			-- Cleanup
			vim.fn.delete(temp_file)
		end)

		it("should handle dynamic file resources", function()
			-- Create a temp file without registering it
			local temp_file = vim.fn.tempname()
			local file = io.open(temp_file, "w")
			file:write("Dynamic content")
			file:close()

			-- Read it via RPC (should auto-register)
			local result = resources_handler.read_resource(mock_rpc, { uri = "file://" .. temp_file })

			assert.truthy(result)
			assert.equals("Dynamic content", result.contents[1].text)

			-- Cleanup
			vim.fn.delete(temp_file)
		end)

		it("should error on missing uri parameter", function()
			assert.has_error(function()
				resources_handler.read_resource(mock_rpc, {})
			end, "Missing required parameter: uri")
		end)

		it("should handle non-existent resources gracefully", function()
			local result = resources_handler.read_resource(mock_rpc, { uri = "file:///non-existent.txt" })
			assert.truthy(result)
			assert.truthy(result.contents[1].text:match("File not found"))
		end)
	end)

	describe("subscribe_resources", function()
		it("should mark connection as subscribed", function()
			local result = resources_handler.subscribe_resources(mock_rpc, {})

			assert.truthy(result)
			assert.is_true(mock_rpc.connection.subscribed_to_resources)
		end)
	end)

	describe("unsubscribe_resources", function()
		it("should mark connection as unsubscribed", function()
			-- First subscribe
			mock_rpc.connection.subscribed_to_resources = true

			local result = resources_handler.unsubscribe_resources(mock_rpc, {})

			assert.truthy(result)
			assert.is_false(mock_rpc.connection.subscribed_to_resources)
		end)
	end)
end)
