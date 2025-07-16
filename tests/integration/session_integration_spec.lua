-- Integration tests for session management and end-to-end scenarios
-- Tests real session lifecycle and multi-step workflows

local helpers = require("tests.integration.helpers.setup")

describe("Session Integration", function()
	it("maintains session state across multiple tool calls", function()
		helpers.with_temp_workspace(function(workspace)
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Initialize with session info
				local init_response = client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = {
						name = "Test Client",
						version = "1.0.0",
					},
				})
				client:notify("initialized", {})

				-- First tool call - open a file
				local response1 = client:request("tools/call", {
					name = "openFile",
					arguments = {
						filePath = workspace .. "/test1.lua",
					},
				})
				assert.truthy(response1.result)

				-- Second tool call - get diagnostics for the same session
				local response2 = client:request("tools/call", {
					name = "getDiagnostics",
					arguments = {},
				})
				assert.truthy(response2.result)

				-- Third tool call - get open editors
				local response3 = client:request("tools/call", {
					name = "getOpenEditors",
					arguments = {},
				})

				-- Verify the opened file appears in editors
				local result = helpers.assert_successful_response(response3)
				local content = vim.json.decode(result.content[1].text)
				local found = false
				for _, editor in ipairs(content.editors) do
					if editor.uri:match("test1%.lua$") then
						found = true
						break
					end
				end
				assert.is_true(found, "Previously opened file should appear in open editors")

				client:close()
			end)
		end)
	end)

	it("handles diff workflow end-to-end", function()
		helpers.with_temp_workspace(function(workspace)
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Initialize
				client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = { name = "Test", version = "1.0" },
				})
				client:notify("initialized", {})

				-- Step 1: Open original file
				client:request("tools/call", {
					name = "openFile",
					arguments = {
						filePath = workspace .. "/test1.lua",
					},
				})

				-- Step 2: Create a diff
				local diff_response = client:request("tools/call", {
					name = "openDiff",
					arguments = {
						old_file_path = workspace .. "/test1.lua",
						new_file_path = workspace .. "/test1_modified.lua",
						new_file_contents = "-- Test file 1 (modified)\nprint('Hello, World!')\nreturn { modified = true }",
						tab_name = "Test Modifications",
					},
				})

				-- Should get DIFF_REJECTED (pending user action)
				local result = helpers.assert_successful_response(diff_response)
				assert.equals("DIFF_REJECTED", result.content[1].text)

				-- Step 3: Close all diff tabs
				local close_response = client:request("tools/call", {
					name = "closeAllDiffTabs",
					arguments = {},
				})

				-- Should handle gracefully even if no tabs to close
				assert.truthy(close_response.result)

				client:close()
			end)
		end)
	end)

	it("handles concurrent sessions from different clients", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)

			-- Create two clients representing different sessions
			local client1 = helpers.create_client(server.port, lock_file.authToken)
			local client2 = helpers.create_client(server.port, lock_file.authToken)

			-- Initialize both
			for _, client in ipairs({ client1, client2 }) do
				client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = { name = "Test", version = "1.0" },
				})
				client:notify("initialized", {})
			end

			-- Create different buffers in each session
			local buf1 = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf1, "session1.lua")
			vim.api.nvim_buf_set_lines(buf1, 0, -1, false, { "-- Session 1 buffer" })

			local buf2 = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_name(buf2, "session2.lua")
			vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "-- Session 2 buffer" })

			-- Both clients request open editors
			local response1 = client1:request("tools/call", {
				name = "getOpenEditors",
				arguments = {},
			})
			local response2 = client2:request("tools/call", {
				name = "getOpenEditors",
				arguments = {},
			})

			-- Both should see all buffers (sessions share vim state)
			local editors1 = vim.json.decode(response1.result.content[1].text).editors
			local editors2 = vim.json.decode(response2.result.content[1].text).editors

			-- Find our test buffers
			local found1_in_1, found2_in_1 = false, false
			local found1_in_2, found2_in_2 = false, false

			for _, editor in ipairs(editors1) do
				if editor.uri:match("session1%.lua$") then
					found1_in_1 = true
				end
				if editor.uri:match("session2%.lua$") then
					found2_in_1 = true
				end
			end

			for _, editor in ipairs(editors2) do
				if editor.uri:match("session1%.lua$") then
					found1_in_2 = true
				end
				if editor.uri:match("session2%.lua$") then
					found2_in_2 = true
				end
			end

			-- Both sessions should see both buffers
			assert.is_true(found1_in_1 and found2_in_1)
			assert.is_true(found1_in_2 and found2_in_2)

			-- Cleanup
			vim.api.nvim_buf_delete(buf1, { force = true })
			vim.api.nvim_buf_delete(buf2, { force = true })
			client1:close()
			client2:close()
		end)
	end)

	it("handles resource subscription workflow", function()
		helpers.with_temp_workspace(function(workspace)
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Initialize
				client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = { name = "Test", version = "1.0" },
				})
				client:notify("initialized", {})

				-- List resources
				local list_response = client:request("resources/list", {})
				local resources = helpers.assert_successful_response(list_response).resources
				assert.is_true(#resources > 0)

				-- Find a file resource
				local file_resource = nil
				for _, resource in ipairs(resources) do
					if resource.uri:match("%.lua$") then
						file_resource = resource
						break
					end
				end

				if file_resource then
					-- Read the resource
					local read_response = client:request("resources/read", {
						uri = file_resource.uri,
					})

					local result = helpers.assert_successful_response(read_response)
					assert.truthy(result.contents)
					assert.is_true(#result.contents > 0)
					assert.equals("text", result.contents[1].type)

					-- Subscribe to the resource
					local sub_response = client:request("resources/subscribe", {
						uri = file_resource.uri,
					})
					assert.truthy(sub_response.result)

					-- Unsubscribe
					local unsub_response = client:request("resources/unsubscribe", {
						uri = file_resource.uri,
					})
					assert.truthy(unsub_response.result)
				end

				client:close()
			end)
		end)
	end)

	it("completes full development workflow", function()
		helpers.with_temp_workspace(function(workspace)
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = helpers.create_client(server.port, lock_file.authToken)

				-- Initialize
				client:request("initialize", {
					protocolVersion = "2025-06-18",
					capabilities = {},
					clientInfo = { name = "Claude", version = "1.0" },
				})
				client:notify("initialized", {})

				-- Step 1: Check workspace
				local workspace_response = client:request("tools/call", {
					name = "getWorkspaceFolders",
					arguments = {},
				})
				assert.truthy(workspace_response.result)

				-- Step 2: List available resources
				local resources_response = client:request("resources/list", {})
				assert.truthy(resources_response.result)

				-- Step 3: Open a file
				local open_response = client:request("tools/call", {
					name = "openFile",
					arguments = {
						filePath = workspace .. "/test2.lua",
					},
				})
				assert.truthy(open_response.result)

				-- Step 4: Get current selection (should be empty)
				local selection_response = client:request("tools/call", {
					name = "getCurrentSelection",
					arguments = {},
				})
				local selection = vim.json.decode(selection_response.result.content[1].text)
				assert.equals("", selection.text)

				-- Step 5: Check for diagnostics
				local diag_response = client:request("tools/call", {
					name = "getDiagnostics",
					arguments = {},
				})
				assert.truthy(diag_response.result)

				-- Step 6: Get all open editors
				local editors_response = client:request("tools/call", {
					name = "getOpenEditors",
					arguments = {},
				})
				local editors = vim.json.decode(editors_response.result.content[1].text)
				assert.is_true(#editors.editors > 0)

				-- Verify our file is open
				local found = false
				for _, editor in ipairs(editors.editors) do
					if editor.uri:match("test2%.lua$") then
						found = true
						break
					end
				end
				assert.is_true(found, "test2.lua should be in open editors")

				client:close()
			end)
		end)
	end)

	it("handles error recovery and reconnection", function()
		helpers.with_real_server({}, function(server, config)
			local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
			local client1 = helpers.create_client(server.port, lock_file.authToken)

			-- Initialize first client
			client1:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Test", version = "1.0" },
			})
			client1:notify("initialized", {})

			-- Make a successful request
			local response1 = client1:request("tools/list", {})
			assert.truthy(response1.result)

			-- Disconnect first client
			client1:close()

			-- Create new client and connect
			local client2 = helpers.create_client(server.port, lock_file.authToken)

			-- Should be able to initialize and work normally
			client2:request("initialize", {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Test2", version = "1.0" },
			})
			client2:notify("initialized", {})

			local response2 = client2:request("tools/list", {})
			assert.truthy(response2.result)
			assert.truthy(response2.result.tools)

			client2:close()
		end)
	end)
end)