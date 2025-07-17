-- Lock file management for server discovery

local M = {}

-- Create lock file for server discovery
---@param port number Server port
---@param auth_token string Authentication token
---@param lock_path string Path to lock file
function M.create_lock_file(port, auth_token, lock_path)
	-- Prepare lock file content
	local content = vim.json.encode({
		pid = vim.uv.getpid(),
		workspaceFolders = { vim.fn.getcwd() },
		ideName = "Neovim",
		transport = "ws",
		runningInWindows = vim.fn.has("win32") == 1,
		authToken = auth_token,
		port = port,
		version = "0.1.0",
	})

	-- Ensure directory exists
	local dir = vim.fn.fnamemodify(lock_path, ":h")
	vim.fn.mkdir(dir, "p")

	-- Write lock file
	local file = io.open(lock_path, "w")
	if not file then
		error("Failed to create lock file: " .. lock_path)
	end

	file:write(content)
	file:close()

	-- Set permissions to 600 (owner read/write only)
	if vim.fn.has("unix") == 1 then
		os.execute(string.format("chmod 600 '%s'", lock_path))
	end
end

-- Remove lock file
---@param lock_path string Path to lock file
function M.remove_lock_file(lock_path)
	if vim.fn.filereadable(lock_path) == 1 then
		os.remove(lock_path)
	end
end

-- Read existing lock file
---@param lock_path string Path to lock file
---@return table? data Lock file data or nil
function M.read_lock_file(lock_path)
	if vim.fn.filereadable(lock_path) == 0 then
		return nil
	end

	local file = io.open(lock_path, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return nil
	end

	return data
end

-- Check if another server is running
---@param lock_path string Path to lock file
---@return boolean running
function M.is_server_running(lock_path)
	local data = M.read_lock_file(lock_path)
	if not data or not data.pid then
		return false
	end

	-- Check if process is still running
	-- This is platform-specific; using kill -0 on Unix
	if vim.fn.has("unix") == 1 then
		local result = os.execute(string.format("kill -0 %d 2>/dev/null", data.pid))
		return result == 0
	else
		-- On Windows, we'll assume the server is running if lock file exists
		-- TODO: Implement proper Windows process checking
		return true
	end
end

-- Clean stale lock files
---@param lock_path string Path to lock file
function M.clean_stale_lock(lock_path)
	if not M.is_server_running(lock_path) then
		M.remove_lock_file(lock_path)
	end
end

return M
