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
				roots = {}
			},
			clientInfo = {
				name = "claude-code",
				version = "1.0.53"
			}
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
						roots = {}
					},
					clientInfo = {
						name = "claude-code",
						version = "1.0.53"
					}
				})
				
				-- Verify response matches expected format
				local result = helpers.assert_successful_response(init_response)
				assert.equals("2025-06-18", result.protocolVersion)
				assert.truthy(result.capabilities)
				assert.truthy(result.capabilities.tools)
				assert.equals(true, result.capabilities.tools.listChanged)
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
				
				-- Send ide_connected notification
				client:notify("ide_connected", {
					pid = 27519
				})
				
				-- Small delay to ensure notification is processed
				vim.wait(50)
				
				-- Server should still be responsive
				local response = client:request("tools/list")
				helpers.assert_successful_response(response)
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
				
				-- Verify openFile schema matches
				local openFile = tool_names.openFile
				assert.equals("Open a file in the editor and optionally select text", openFile.description)
				assert.truthy(openFile.inputSchema)
				assert.equals("object", openFile.inputSchema.type)
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
						text = "",
						filePath = test_file,
						fileUrl = "file://" .. test_file,
						selection = {
							start = {
								line = 0,
								character = 0
							},
							["end"] = {
								line = 0,
								character = 0
							},
							isEmpty = true
						}
					})
					
					-- Server should still be responsive
					vim.wait(50)
					local response = client:request("tools/list")
					helpers.assert_successful_response(response)
				end)
			end)
		end)
		
		it("should handle log_event notifications", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)
				
				-- Send log_event notifications from the log
				client:notify("log_event", {
					eventName = "run_claude_command",
					eventData = {}
				})
				
				vim.wait(50)
				
				client:notify("log_event", {
					eventName = "quick_fix_command",
					eventData = {}
				})
				
				-- Server should still be responsive
				vim.wait(50)
				local response = client:request("tools/list")
				helpers.assert_successful_response(response)
			end)
		end)
	end)

	describe("Tool calls", function()
		it("should handle getDiagnostics without uri", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					-- Create a file with an error
					local test_file = workspace .. "/error.lua"
					helpers.write_file(test_file, "local x = y") -- y is undefined
					vim.cmd("edit " .. test_file)
					
					-- Call getDiagnostics without uri (gets all diagnostics)
					local response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {}
					})
					
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("text", result.content[1].type)
					
					-- Should return diagnostics in expected format
					local text = result.content[1].text
					assert.truthy(text)
				end)
			end)
		end)
		
		it("should handle getDiagnostics with specific uri", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					local test_file = workspace .. "/test.lua"
					helpers.write_file(test_file, "return 42")
					vim.cmd("edit " .. test_file)
					
					-- Call getDiagnostics with specific uri
					local response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {
							uri = "file://" .. test_file
						}
					})
					
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("text", result.content[1].type)
				end)
			end)
		end)
		
		it("should handle closeAllDiffTabs", function()
			helpers.with_real_server({}, function(server, config)
				local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
				local client = create_test_client(server, lock_file)
				
				local response = client:request("tools/call", {
					name = "closeAllDiffTabs",
					arguments = {}
				})
				
				local result = helpers.assert_successful_response(response)
				assert.truthy(result.content)
				assert.equals("text", result.content[1].type)
				-- VSCode returns "CLOSED_1_DIFF_TABS" format
				assert.truthy(result.content[1].text:match("CLOSED_%d+_DIFF_TABS") or 
				              result.content[1].text:match("No diff tabs"))
			end)
		end)
		
		it("should handle openDiff with full parameters", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					-- Create a test file
					local test_file = workspace .. "/README.md"
					helpers.write_file(test_file, "# Original Content\n\nThis is the original.")
					
					-- Open diff matching the log format
					local response = client:request("tools/call", {
						name = "openDiff",
						arguments = {
							old_file_path = test_file,
							new_file_path = test_file,
							new_file_contents = "# Modified Content\n\nThis is the modified version.",
							tab_name = "✻ [Claude Code] README.md (5a0ae4) ⧉"
						}
					})
					
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("text", result.content[1].type)
					assert.truthy(result.content[1].text:match("Diff shown for"))
				end)
			end)
		end)
		
		it("should handle close_tab", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					-- Create and open a file first
					local test_file = workspace .. "/test.lua"
					helpers.write_file(test_file, "return 42")
					vim.cmd("edit " .. test_file)
					vim.cmd("tabnew") -- Create a new tab
					
					local tabs_before = vim.api.nvim_list_tabpages()
					
					-- Close tab with specific name format from log
					local response = client:request("tools/call", {
						name = "close_tab",
						arguments = {
							tab_name = "✻ [Claude Code] README.md (1b0fb2) ⧉"
						}
					})
					
					local result = helpers.assert_successful_response(response)
					assert.truthy(result.content)
					assert.equals("text", result.content[1].type)
					assert.equals("Tab closed", result.content[1].text)
				end)
			end)
		end)
	end)

	describe("Multiple sequential operations", function()
		it("should handle rapid getDiagnostics calls like in the log", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					-- Create a file
					local test_file = workspace .. "/test.lua"
					helpers.write_file(test_file, "return 42")
					vim.cmd("edit " .. test_file)
					
					-- Make multiple rapid getDiagnostics calls as seen in log
					for i = 1, 5 do
						local response = client:request("tools/call", {
							name = "getDiagnostics",
							arguments = {}
						})
						
						local result = helpers.assert_successful_response(response)
						assert.truthy(result.content)
						assert.equals("text", result.content[1].type)
					end
				end)
			end)
		end)
		
		it("should handle diff creation, close attempts, and diagnostics sequence", function()
			helpers.with_temp_workspace(function(workspace)
				helpers.with_real_server({}, function(server, config)
					local lock_file = helpers.get_lock_file(server.port, config.lock_file_dir)
					local client = create_test_client(server, lock_file)
					
					local test_file = workspace .. "/README.md"
					helpers.write_file(test_file, "# Original")
					
					-- 1. Open diff
					local diff_response = client:request("tools/call", {
						name = "openDiff",
						arguments = {
							old_file_path = test_file,
							new_file_path = test_file,
							new_file_contents = "# Modified",
							tab_name = "✻ [Claude Code] README.md (test) ⧉"
						}
					})
					helpers.assert_successful_response(diff_response)
					
					-- 2. Try to close tab twice (as in log)
					for i = 1, 2 do
						local close_response = client:request("tools/call", {
							name = "close_tab",
							arguments = {
								tab_name = "✻ [Claude Code] README.md (test) ⧉"
							}
						})
						helpers.assert_successful_response(close_response)
					end
					
					-- 3. Get diagnostics for specific file
					local diag_response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {
							uri = "file://" .. test_file
						}
					})
					helpers.assert_successful_response(diag_response)
					
					-- 4. Get all diagnostics
					local all_diag_response = client:request("tools/call", {
						name = "getDiagnostics",
						arguments = {}
					})
					helpers.assert_successful_response(all_diag_response)
				end)
			end)
		end)
	end)
end)