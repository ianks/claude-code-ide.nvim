-- Integration test setup utilities
local M = {}

-- Run a test with a temporary workspace
function M.with_temp_workspace(fn)
	local temp_dir = vim.fn.tempname()
	vim.fn.mkdir(temp_dir, "p")
	local old_cwd = vim.fn.getcwd()
	vim.cmd("cd " .. vim.fn.fnameescape(temp_dir))

	-- Create some test files
	vim.fn.writefile({ "-- Test file 1", "return {}" }, temp_dir .. "/test1.lua")
	vim.fn.writefile({ "-- Test file 2", "local M = {}", "return M" }, temp_dir .. "/test2.lua")

	local ok, result = pcall(fn, temp_dir)

	-- Cleanup
	vim.cmd("cd " .. vim.fn.fnameescape(old_cwd))
	vim.fn.delete(temp_dir, "rf")

	if not ok then
		error(result)
	end
	return result
end

-- Run a test with a real running server
function M.with_real_server(config, fn)
	config = vim.tbl_extend("force", {
		port = 0, -- Random port
		host = "127.0.0.1",
		debug = false,
		server_name = "test-server",
		server_version = "0.1.0",
		-- Use temp directory for lock files
		lock_file_dir = vim.fn.tempname(),
	}, config or {})

	-- Create lock file directory
	vim.fn.mkdir(config.lock_file_dir, "p")
	
	-- Set the discovery module to use our test lock directory
	require("claude-code-ide.discovery")._set_lock_dir(config.lock_file_dir)

	-- Start the server
	local server = require("claude-code-ide.server").start(config)

	-- Wait for server to be ready
	vim.wait(100)

	-- Get the actual port if it was random
	local actual_port = server.port
	config.port = actual_port

	local ok, result = pcall(fn, server, config)

	-- Stop server
	server:stop()

	-- Cleanup lock file
	vim.fn.delete(config.lock_file_dir, "rf")

	if not ok then
		error(result)
	end
	return result
end

-- Create a connected WebSocket client
function M.create_client(server_port, auth_token, debug)
	local client = require("tests.integration.helpers.websocket_client").new()
	if debug then
		client:set_debug(true)
	end
	client:connect("127.0.0.1", server_port, auth_token)
	return client
end

-- Get lock file info for a running server
function M.get_lock_file(port, lock_dir)
	local lock_file_path = lock_dir .. "/" .. port .. ".lock"
	local content = vim.fn.readfile(lock_file_path)
	if #content > 0 then
		return vim.json.decode(table.concat(content, "\n"))
	end
	return nil
end

-- Wait for a condition with timeout
function M.wait_for(condition_fn, timeout_ms, check_interval_ms)
	timeout_ms = timeout_ms or 5000
	check_interval_ms = check_interval_ms or 50
	local waited = 0

	while waited < timeout_ms do
		if condition_fn() then
			return true
		end
		vim.wait(check_interval_ms)
		waited = waited + check_interval_ms
	end

	return false
end

-- Create a test buffer with content
function M.create_test_buffer(content, filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	if type(content) == "string" then
		content = vim.split(content, "\n")
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	if filetype then
		vim.api.nvim_buf_set_option(buf, "filetype", filetype)
	end
	return buf
end

-- Set up a test window
function M.with_test_window(fn)
	-- Save current window
	local original_win = vim.api.nvim_get_current_win()

	-- Create new window
	vim.cmd("new")
	local test_win = vim.api.nvim_get_current_win()
	local test_buf = vim.api.nvim_get_current_buf()

	local ok, result = pcall(fn, test_win, test_buf)

	-- Cleanup
	if vim.api.nvim_win_is_valid(test_win) then
		vim.api.nvim_win_close(test_win, true)
	end
	if vim.api.nvim_buf_is_valid(test_buf) then
		vim.api.nvim_buf_delete(test_buf, { force = true })
	end

	-- Restore original window
	if vim.api.nvim_win_is_valid(original_win) then
		vim.api.nvim_set_current_win(original_win)
	end

	if not ok then
		error(result)
	end
	return result
end

-- Assert JSON-RPC response is successful
function M.assert_successful_response(response)
	assert.is_nil(response.error, "Expected no error but got: " .. vim.inspect(response.error))
	assert.truthy(response.result, "Expected result in response")
	return response.result
end

-- Helper to write a file
function M.write_file(path, content)
	local file = io.open(path, "w")
	assert.truthy(file, "Failed to open file for writing: " .. path)
	file:write(content)
	file:close()
end

-- Create diagnostics for testing
function M.create_test_diagnostics(bufnr)
	local diagnostics = {
		{
			bufnr = bufnr,
			lnum = 0,
			col = 0,
			end_lnum = 0,
			end_col = 5,
			severity = vim.diagnostic.severity.ERROR,
			message = "Test error diagnostic",
			source = "test",
		},
		{
			bufnr = bufnr,
			lnum = 2,
			col = 4,
			end_lnum = 2,
			end_col = 10,
			severity = vim.diagnostic.severity.WARN,
			message = "Test warning diagnostic",
			source = "test",
		},
	}
	vim.diagnostic.set(vim.api.nvim_create_namespace("test_diagnostics"), bufnr, diagnostics)
	return diagnostics
end

return M