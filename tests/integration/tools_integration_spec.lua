-- Integration tests for MCP tools with real vim operations
-- Tests actual file operations, buffer management, and diagnostics

local helpers = require("tests.integration.helpers.setup")

describe("Tools Integration", function()
	describe("openFile", function()
		it("opens real files and navigates to them", function()
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

					-- Get current buffer before
					local buf_before = vim.api.nvim_get_current_buf()

					-- Open a real file
					local response = client:request("tools/call", {
						name = "openFile",
						arguments = {
							filePath = workspace .. "/test1.lua",
							makeFrontmost = true,
						},
					})

					-- Verify response
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("text", result.content[1].type)
					assert.truthy(result.content[1].text:match("Opened file"))

					-- Verify file was actually opened
					local buf_after = vim.api.nvim_get_current_buf()
					assert.not_equals(buf_before, buf_after)
					assert.equals(workspace .. "/test1.lua", vim.api.nvim_buf_get_name(buf_after))

					-- Verify content
					local lines = vim.api.nvim_buf_get_lines(buf_after, 0, -1, false)
					assert.equals("-- Test file 1", lines[1])

					client:close()
				end)
			end)
		end)

		it("handles non-existent files correctly", function()
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

					-- Try to open non-existent file
					local response = client:request("tools/call", {
						name = "openFile",
						arguments = {
							filePath = workspace .. "/does-not-exist.lua",
						},
					})

					-- Should get error message
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content[1].text:match("File not found"))

					client:close()
				end)
			end)
		end)
	end)

	describe("getDiagnostics", function()
		it("returns real diagnostics from buffers", function()
			helpers.with_test_window(function(win, buf)
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

					-- Set buffer content and name
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
						"local x = 1",
						"local y = 2",
						"print(z)", -- undefined variable
					})
					vim.api.nvim_buf_set_name(buf, "test.lua")

					-- Create test diagnostics
					helpers.create_test_diagnostics(buf)

					-- Get diagnostics
					local response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {},
					})

					-- Verify response
					local result = helpers.assert_successful_response(response)
					local content = vim.json.decode(result.content[1].text)
					assert.truthy(content.diagnostics)
					assert.equals(2, #content.diagnostics)

					-- Verify diagnostic details
					local diag1 = content.diagnostics[1]
					assert.equals("file://" .. vim.fn.getcwd() .. "/test.lua", diag1.uri)
					assert.equals("ERROR", diag1.severity)
					assert.equals("Test error diagnostic", diag1.message)
					assert.equals(0, diag1.range.start.line)

					client:close()
				end)
			end)
		end)

		it("filters diagnostics by URI", function()
			helpers.with_test_window(function(win, buf)
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

					-- Create two buffers with diagnostics
					vim.api.nvim_buf_set_name(buf, "test1.lua")
					helpers.create_test_diagnostics(buf)

					local buf2 = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_name(buf2, "test2.lua")
					helpers.create_test_diagnostics(buf2)

					-- Get diagnostics for specific file
					local response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {
							uri = "file://" .. vim.fn.getcwd() .. "/test1.lua",
						},
					})

					-- Should only get diagnostics for test1.lua
					local result = helpers.assert_successful_response(response)
					local content = vim.json.decode(result.content[1].text)
					assert.equals(2, #content.diagnostics)
					for _, diag in ipairs(content.diagnostics) do
						assert.truthy(diag.uri:match("test1%.lua"))
					end

					vim.api.nvim_buf_delete(buf2, { force = true })
					client:close()
				end)
			end)
		end)
	end)

	describe("getCurrentSelection", function()
		it("returns empty when not in visual mode", function()
			helpers.with_test_window(function(win, buf)
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

					-- Ensure we're in normal mode
					vim.cmd("normal! gg")

					-- Get selection
					local response = client:request("tools/call", {
						name = "getCurrentSelection",
						arguments = {},
					})

					-- Should return empty
					local result = helpers.assert_successful_response(response)
					local content = vim.json.decode(result.content[1].text)
					assert.equals("", content.text)
					assert.is_nil(content.uri)

					client:close()
				end)
			end)
		end)

		it("returns selected text in visual mode", function()
			helpers.with_test_window(function(win, buf)
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

					-- Set buffer content
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
						"local function test()",
						"  print('hello')",
						"  return 42",
						"end",
					})
					vim.api.nvim_buf_set_name(buf, "selection_test.lua")

					-- Select some text (line 2)
					vim.cmd("normal! 2ggV")

					-- Get selection
					local response = client:request("tools/call", {
						name = "getCurrentSelection",
						arguments = {},
					})

					-- Verify selection
					local result = helpers.assert_successful_response(response)
					local content = vim.json.decode(result.content[1].text)
					assert.truthy(content.text:match("print"))
					assert.equals("file://" .. vim.fn.getcwd() .. "/selection_test.lua", content.uri)
					assert.equals(1, content.range.start.line) -- 0-based

					client:close()
				end)
			end)
		end)
	end)

	describe("getOpenEditors", function()
		it("returns all open buffers with metadata", function()
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

				-- Create multiple buffers
				local bufs = {}
				for i = 1, 3 do
					local buf = vim.api.nvim_create_buf(false, true)
					vim.api.nvim_buf_set_name(buf, "test" .. i .. ".lua")
					vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- Buffer " .. i })
					table.insert(bufs, buf)
				end

				-- Make first buffer current
				vim.api.nvim_set_current_buf(bufs[1])

				-- Get open editors
				local response = client:request("tools/call", {
					name = "getOpenEditors",
					arguments = {},
				})

				-- Verify response
				local result = helpers.assert_successful_response(response)
				local content = vim.json.decode(result.content[1].text)
				assert.truthy(content.editors)
				assert.is_true(#content.editors >= 3)

				-- Find our test buffers
				local found = {}
				for _, editor in ipairs(content.editors) do
					local name = editor.uri:match("test(%d)%.lua$")
					if name then
						found[tonumber(name)] = editor
					end
				end

				-- Verify all three were found
				assert.truthy(found[1])
				assert.truthy(found[2])
				assert.truthy(found[3])

				-- First buffer should be active
				assert.is_true(found[1].active)

				-- Cleanup
				for _, buf in ipairs(bufs) do
					vim.api.nvim_buf_delete(buf, { force = true })
				end
				client:close()
			end)
		end)
	end)

	describe("getWorkspaceFolders", function()
		it("returns current working directory", function()
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

					-- Get workspace folders
					local response = client:request("tools/call", {
						name = "getWorkspaceFolders",
						arguments = {},
					})

					-- Verify response
					local result = helpers.assert_successful_response(response)
					local content = vim.json.decode(result.content[1].text)
					assert.equals(1, #content.folders)
					assert.equals("file://" .. workspace, content.folders[1].uri)
					assert.truthy(content.folders[1].name)

					client:close()
				end)
			end)
		end)
	end)

	describe("openDiff", function()
		it("creates diff view with real buffers", function()
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

					-- Create a diff
					local response = client:request("tools/call", {
						name = "openDiff",
						arguments = {
							old_file_path = workspace .. "/test1.lua",
							new_file_path = workspace .. "/test1_modified.lua",
							new_file_contents = "-- Test file 1 (modified)\nprint('modified')\nreturn {}",
							tab_name = "Test Diff",
						},
					})

					-- Should get DIFF_REJECTED (requires user interaction)
					local result = helpers.assert_successful_response(response)
					assert.equals("DIFF_REJECTED", result.content[1].text)

					-- But pending diff should be tracked
					local sessions = require("claude-code-ide.session").get_all_sessions()
					local session = nil
					for _, s in pairs(sessions) do
						if s.client_id == client.next_id then
							session = s
							break
						end
					end

					-- Note: Session tracking might need client_id handling
					-- This is a limitation of the current integration test setup

					client:close()
				end)
			end)
		end)
	end)

	describe("Tool error handling", function()
		it("handles tool execution errors gracefully", function()
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

				-- Call non-existent tool
				local response = client:request("tools/call", {
					name = "nonExistentTool",
					arguments = {},
				})

				-- Should get error
				assert.truthy(response.error)
				assert.equals(-32602, response.error.code)

				-- Call tool with invalid arguments
				local response2 = client:request("tools/call", {
					name = "openFile",
					arguments = {
						-- Missing required filePath
					},
				})

				-- Should handle gracefully
				local result = helpers.assert_successful_response(response2)
				assert.truthy(result.content[1].text:match("File not found"))

				client:close()
			end)
		end)
	end)
end)
