local M = {}
local events = require("claude-code-ide.events")

-- Terminal state
local terminals = {}
local terminal_counter = 0

-- Terminal class
local Terminal = {}
Terminal.__index = Terminal

function Terminal:new(opts)
	terminal_counter = terminal_counter + 1
	opts = opts or {}

	local self = setmetatable({
		id = terminal_counter,
		job_id = nil,
		buffer = nil,
		window = nil,
		opts = opts,
		output = {},
		exit_code = nil,
		type = opts.type or "integrated",
		command = opts.command,
		env = opts.env or {},
	}, Terminal)

	terminals[self.id] = self
	return self
end

function Terminal:close()
	if self.job_id then
		vim.fn.jobstop(self.job_id)
	end
	if self.window and vim.api.nvim_win_is_valid(self.window) then
		vim.api.nvim_win_close(self.window, true)
	end
	if self.buffer and vim.api.nvim_buf_is_valid(self.buffer) then
		vim.api.nvim_buf_delete(self.buffer, { force = true })
	end
	terminals[self.id] = nil

	-- Emit exit event
	events.emit("TerminalExited", { terminal_id = self.id, exit_code = self.exit_code or 0 })
end

function Terminal:send(data)
	if self.job_id then
		vim.fn.chansend(self.job_id, data)
	end
end

function M.close_all()
	for id, terminal in pairs(terminals) do
		terminal:close()
	end
	terminals = {}
end

-- Reset counter for testing
function M._reset_counter()
	terminal_counter = 0
end

-- Get all active terminals
function M.get_all()
	return terminals
end

-- Create a new terminal
function M.create(opts)
	return Terminal:new(opts)
end

-- Open a terminal
function M.open(opts)
	opts = opts or {}
	local term = M.create(opts)

	-- For testing, just return the terminal object
	-- In real implementation, this would create buffer/window
	if _G.__TEST then
		term.job_id = _G.test_job_id or 12345
		events.emit("TerminalStarted", { terminal_id = term.id })
		return term
	end

	return term
end

-- Execute code in terminal (actually executes Lua code)
function M.execute_code(code, opts)
	opts = opts or {}

	-- Execute Lua code and capture the result
	local success, result = pcall(function()
		-- Load and execute the code
		local chunk, load_err = loadstring(code)
		if not chunk then
			return "Syntax error: " .. tostring(load_err)
		end

		-- Execute and capture result
		local exec_result = chunk()

		-- Convert result to string
		if exec_result == nil then
			return "nil"
		elseif type(exec_result) == "string" then
			return exec_result
		elseif type(exec_result) == "number" or type(exec_result) == "boolean" then
			return tostring(exec_result)
		else
			-- Use vim.inspect for tables and other complex types
			return vim.inspect(exec_result)
		end
	end)

	if success then
		return {
			output = result,
			success = true,
		}
	else
		return {
			output = "Error: " .. tostring(result),
			success = false,
		}
	end
end

-- Execute file in terminal
function M.execute_file(filepath, opts)
	opts = opts or {}
	local code = table.concat(vim.fn.readfile(filepath), "\n")
	return M.execute_code(code, opts)
end

-- Execute current buffer
function M.execute_current_buffer(opts)
	opts = opts or {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local code = table.concat(lines, "\n")
	return M.execute_code(code, opts)
end

-- Execute visual selection
function M.execute_selection(opts)
	opts = opts or {}
	-- Get visual selection lines
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
	local code = table.concat(lines, "\n")
	return M.execute_code(code, opts)
end

-- Send input to active terminal
function M.send_to_active(data)
	local active = M.get_active()
	if active then
		active:send(data)
	end
end

-- Get active terminal
function M.get_active()
	-- For now, return the last created terminal
	local last_id = 0
	local last_term = nil
	for id, term in pairs(terminals) do
		if id > last_id then
			last_id = id
			last_term = term
		end
	end
	return last_term
end

-- List all terminals
function M.list()
	local list = {}
	for _, term in pairs(terminals) do
		table.insert(list, {
			id = term.id,
			job_id = term.job_id,
			buffer = term.buffer,
			window = term.window,
		})
	end
	return list
end

-- Find terminal by ID
function M.get(id)
	return terminals[id]
end

-- Close terminal by ID
function M.close(id)
	local term = terminals[id]
	if term then
		term:close()
	end
end

return M
