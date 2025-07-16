-- Tests for terminal integration

local terminal = require("claude-code.terminal")
local config = require("claude-code.config")
local events = require("claude-code.events")

describe("Terminal Integration", function()
	local captured_events
	local event_handlers

	before_each(function()
		-- Reset configuration
		config.reset()
		config.setup({
			features = {
				code_execution = {
					enabled = true,
					terminal = "integrated",
					confirm_before_run = false,
					save_before_run = false,
				},
			},
		})

		-- Reset captured events
		captured_events = {}
		event_handlers = {}

		-- Capture terminal events
		local terminal_events = {
			"TerminalStarted",
			"TerminalExited",
		}

		for _, event in ipairs(terminal_events) do
			table.insert(
				event_handlers,
				events.on(event, function(data)
					table.insert(captured_events, { type = event, data = data })
				end)
			)
		end

		-- Mock vim.fn.termopen for integrated terminals
		_G.test_job_id = 12345
		_G.test_exit_callbacks = {}

		vim.fn.termopen = function(cmd, opts)
			-- Store callbacks
			test_exit_callbacks[test_job_id] = opts.on_exit

			-- Call stdout/stderr callbacks with test data
			if opts.on_stdout then
				opts.on_stdout(test_job_id, { "Test output line 1", "Test output line 2" }, "stdout")
			end

			return test_job_id
		end

		-- Mock vim.fn.chansend
		_G.test_sent_data = {}
		vim.fn.chansend = function(job_id, data)
			table.insert(test_sent_data, { job_id = job_id, data = data })
		end

		-- Mock vim.fn.jobstop
		vim.fn.jobstop = function(job_id)
			-- Trigger exit callback
			if test_exit_callbacks[job_id] then
				test_exit_callbacks[job_id](job_id, 0, "exit")
			end
		end

		-- Mock vim.fn.system for external terminals
		_G.test_shell_error = 0
		vim.fn.system = function(cmd)
			return ""
		end

		-- Override vim.v table to allow shell_error mocking
		local original_v = vim.v
		vim.v = setmetatable({}, {
			__index = function(t, k)
				if k == "shell_error" then
					return test_shell_error
				end
				return original_v[k]
			end,
			__newindex = function(t, k, v)
				if k == "shell_error" then
					test_shell_error = v
				else
					original_v[k] = v
				end
			end,
		})

		-- Mock vim.fn.executable
		vim.fn.executable = function(cmd)
			return 1
		end

		-- Mock vim.fn.has
		vim.fn.has = function(feature)
			if feature == "macunix" then
				return 0 -- Not macOS for testing
			elseif feature == "win32" then
				return 0 -- Not Windows for testing
			end
			return 0
		end
	end)

	after_each(function()
		-- Clean up event handlers
		for _, handler in ipairs(event_handlers) do
			events.off(handler)
		end

		-- Close all terminals
		terminal.close_all()

		-- Reset terminal counter for consistent IDs
		local Terminal = require("claude-code.terminal")
		Terminal._reset_counter = function()
			-- This is a hack to reset the counter for testing
			-- We'll need to add this method to the terminal module
		end

		-- Reset globals
		_G.test_job_id = nil
		_G.test_exit_callbacks = nil
		_G.test_sent_data = nil
		_G.test_shell_error = nil
	end)

	describe("Terminal Creation", function()
		it("should create integrated terminal", function()
			local term = terminal.open({
				type = "integrated",
				command = "echo hello",
			})

			assert.truthy(term)
			assert.equals("integrated", term.type)
			assert.equals("echo hello", term.command)
			assert.equals("running", term.state)
			assert.equals(test_job_id, term.job_id)
		end)

		it("should create external terminal", function()
			local term = terminal.open({
				type = "external",
				command = "echo hello",
			})

			-- Wait for deferred exit
			vim.wait(150)

			assert.truthy(term)
			assert.equals("external", term.type)
			assert.equals("exited", term.state)
		end)

		it("should handle terminal with custom environment", function()
			local term = terminal.open({
				env = { CUSTOM_VAR = "test_value" },
			})

			assert.truthy(term)
			assert.equals("test_value", term.env.CUSTOM_VAR)
		end)

		it("should emit events on terminal lifecycle", function()
			local term = terminal.open({
				command = "test command",
			})

			-- Wait for event to be emitted (scheduled)
			vim.wait(50)

			-- Check started event
			local found_start = false
			for _, event in ipairs(captured_events) do
				if event.type == "TerminalStarted" and event.data.id == term.id then
					found_start = true
					assert.equals(term.id, event.data.id)
					assert.equals("integrated", event.data.type)
					assert.equals("test command", event.data.command)
					break
				end
			end
			assert.is_true(found_start)

			-- Trigger exit
			test_exit_callbacks[test_job_id](test_job_id, 0, "exit")

			-- Wait for exit event
			vim.wait(50)

			-- Check exit event
			local found_exit = false
			for _, event in ipairs(captured_events) do
				if event.type == "TerminalExited" and event.data.id == term.id then
					found_exit = true
					assert.equals(term.id, event.data.id)
					assert.equals(0, event.data.exit_code)
					break
				end
			end
			assert.is_true(found_exit)
		end)
	end)

	describe("Code Execution", function()
		it("should execute code with auto-detected language", function()
			local term = terminal.execute_code("print('hello')", {
				language = "python",
			})

			assert.truthy(term)
			assert.truthy(term.command:match("python"))
		end)

		it("should execute code with custom command", function()
			local term = terminal.execute_code("console.log('hello')", {
				command = "node -e",
				use_temp_file = false,
			})

			assert.truthy(term)
			assert.equals("node -e", term.command)
		end)

		it("should create temporary file when requested", function()
			-- Mock tempname and file operations
			local temp_file = "/tmp/test_12345.py"
			vim.fn.tempname = function()
				return "/tmp/test_12345"
			end

			local written_content = nil
			_G.io = {
				open = function(path, mode)
					if mode == "w" then
						return {
							write = function(self, content)
								written_content = content
							end,
							close = function() end,
						}
					end
				end,
			}

			local term = terminal.execute_code("print('hello')", {
				language = "python",
				use_temp_file = true,
			})

			assert.truthy(term)
			assert.equals("print('hello')", written_content)
			assert.truthy(term.command:match(temp_file))
		end)

		it("should send code directly when not using temp file", function()
			test_sent_data = {}

			local term = terminal.execute_code("print('hello')", {
				language = "python",
				use_temp_file = false,
			})

			assert.truthy(term)
			assert.equals(1, #test_sent_data)
			assert.equals(test_job_id, test_sent_data[1].job_id)
			assert.equals("print('hello')\n", test_sent_data[1].data)
		end)

		it("should respect code execution disabled", function()
			config.set("features.code_execution.enabled", false)

			local term = terminal.execute_code("print('hello')", {
				language = "python",
			})

			assert.is_nil(term)
		end)

		it("should handle exit callbacks", function()
			local exit_called = false
			local exit_code = nil
			local output = nil

			local term = terminal.execute_code("echo test", {
				on_exit = function(code, out)
					exit_called = true
					exit_code = code
					output = out
				end,
			})

			-- Trigger exit
			test_exit_callbacks[test_job_id](test_job_id, 0, "exit")

			assert.is_true(exit_called)
			assert.equals(0, exit_code)
			assert.truthy(output:match("Test output"))
		end)
	end)

	describe("Terminal Operations", function()
		it("should send input to terminal", function()
			local term = terminal.open()
			test_sent_data = {}

			local success = term:send("test input\n")

			assert.is_true(success)
			assert.equals(1, #test_sent_data)
			assert.equals("test input\n", test_sent_data[1].data)
		end)

		it("should not send input to exited terminal", function()
			local term = terminal.open()
			term.state = "exited"

			local success = term:send("test input\n")

			assert.is_false(success)
		end)

		it("should get terminal output", function()
			local term = terminal.open()

			local output = term:get_output()

			assert.equals("Test output line 1\nTest output line 2", output)
		end)

		it("should focus terminal window", function()
			local term = terminal.open()
			term.win_id = 1001 -- Mock window ID

			-- Mock window validation
			vim.api.nvim_win_is_valid = function(win_id)
				return win_id == 1001
			end

			-- Mock set current window
			local set_win_called = false
			vim.api.nvim_set_current_win = function(win_id)
				set_win_called = true
			end

			local success = term:focus()

			assert.is_true(success)
			assert.is_true(set_win_called)
		end)

		it("should hide and show terminal", function()
			local term = terminal.open()
			term.win_id = 1001
			term.bufnr = 1

			-- Mock window operations
			vim.api.nvim_win_is_valid = function()
				return true
			end
			vim.api.nvim_buf_is_valid = function()
				return true
			end

			local closed = false
			vim.api.nvim_win_close = function()
				closed = true
			end

			-- Hide
			local success = term:hide()
			assert.is_true(success)
			assert.is_true(closed)
			assert.is_nil(term.win_id)

			-- Show
			vim.cmd = function(cmd)
				if cmd == "split" then
					term.win_id = 1002
				end
			end
			vim.api.nvim_get_current_win = function()
				return 1002
			end
			vim.api.nvim_win_set_buf = function() end

			success = term:show()
			assert.is_true(success)
			assert.equals(1002, term.win_id)
		end)

		it("should close terminal properly", function()
			local term = terminal.open()

			-- Mock buffer/window operations
			vim.api.nvim_win_is_valid = function()
				return true
			end
			vim.api.nvim_buf_is_valid = function()
				return true
			end
			vim.api.nvim_win_close = function() end
			vim.api.nvim_buf_delete = function() end

			term:close()

			assert.equals("closed", term.state)
			assert.is_nil(terminal.get(term.id))
		end)
	end)

	describe("Buffer and Selection Execution", function()
		it("should execute current buffer", function()
			-- Mock buffer content
			vim.api.nvim_buf_get_lines = function()
				return { "print('line 1')", "print('line 2')" }
			end
			vim.api.nvim_buf_get_option = function(bufnr, opt)
				if opt == "filetype" then
					return "python"
				elseif opt == "modified" then
					return false
				end
			end

			local term = terminal.execute_buffer()

			assert.truthy(term)
			assert.truthy(term.command:match("python"))
		end)

		it("should execute visual selection", function()
			-- Mock visual selection
			vim.fn.getpos = function(mark)
				if mark == "'<" then
					return { 0, 5, 1, 0 }
				elseif mark == "'>" then
					return { 0, 7, 1, 0 }
				end
			end

			vim.api.nvim_buf_get_lines = function(bufnr, start_line, end_line)
				return { "selected line 1", "selected line 2", "selected line 3" }
			end

			vim.api.nvim_buf_get_option = function(bufnr, opt)
				if opt == "filetype" then
					return "lua"
				end
			end

			local term = terminal.execute_selection()

			assert.truthy(term)
			assert.truthy(term.command:match("lua"))
		end)
	end)

	describe("Terminal Management", function()
		it("should list all terminals", function()
			local term1 = terminal.open({ command = "cmd1" })
			local term2 = terminal.open({ command = "cmd2" })

			local list = terminal.list()

			assert.equals(2, #list)

			-- Find our terminals in the list
			local found1 = false
			local found2 = false
			for _, t in ipairs(list) do
				if t.id == term1.id then
					found1 = true
					assert.equals("cmd1", t.command)
				elseif t.id == term2.id then
					found2 = true
					assert.equals("cmd2", t.command)
				end
			end

			assert.is_true(found1)
			assert.is_true(found2)
		end)

		it("should close all terminals", function()
			local term1 = terminal.open()
			local term2 = terminal.open()

			terminal.close_all()

			local list = terminal.list()
			assert.equals(0, #list)
		end)
	end)

	describe("MCP Tool Integration", function()
		it("should create executeCode tool", function()
			local tool = terminal.create_execute_tool()

			assert.equals("executeCode", tool.name)
			assert.truthy(tool.description)
			assert.truthy(tool.inputSchema)
			assert.equals("function", type(tool.handler))
		end)

		it("should execute code via MCP tool", function()
			local tool = terminal.create_execute_tool()

			-- Execute handler
			local result = tool.handler({
				code = "print('test')",
				language = "python",
			})

			-- Trigger exit to complete execution
			test_exit_callbacks[test_job_id](test_job_id, 0, "exit")

			assert.truthy(result)
			assert.truthy(result.content)
			assert.equals("text", result.content[1].type)

			local data = vim.json.decode(result.content[1].text)
			assert.equals(0, data.exit_code)
			assert.is_false(data.timed_out)
		end)
	end)

	describe("External Terminal Detection", function()
		it("should detect gnome-terminal on Linux", function()
			vim.fn.executable = function(cmd)
				return cmd == "gnome-terminal" and 1 or 0
			end

			local term = terminal.Terminal.new({ type = "external" })
			local terminal_cmd = term:_detect_terminal()

			assert.truthy(terminal_cmd)
			assert.equals("gnome-terminal", terminal_cmd.cmd)
			assert.equals("--working-directory", terminal_cmd.cwd_flag)
		end)

		it("should fall back to xterm", function()
			vim.fn.executable = function(cmd)
				return cmd == "xterm" and 1 or 0
			end

			local term = terminal.Terminal.new({ type = "external" })
			local terminal_cmd = term:_detect_terminal()

			assert.truthy(terminal_cmd)
			assert.equals("xterm", terminal_cmd.cmd)
			assert.equals("-e", terminal_cmd.exec_flag)
		end)

		it("should return nil when no terminal found", function()
			vim.fn.executable = function()
				return 0
			end
			vim.fn.has = function()
				return 0
			end

			local term = terminal.Terminal.new({ type = "external" })
			local terminal_cmd = term:_detect_terminal()

			assert.is_nil(terminal_cmd)
		end)
	end)
end)
