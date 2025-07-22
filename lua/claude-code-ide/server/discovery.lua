-- Lock file management for server discovery

local M = {}

-- Set file permissions cross-platform
---@param path string File path
---@return boolean|nil success
---@return string|nil error
local function set_file_permissions_600(path)
	local stat = vim.uv.fs_stat(path)
	if not stat then
		return nil, "File does not exist"
	end

	-- Try to set permissions (owner read/write only)
	local ok, err = pcall(vim.uv.fs_chmod, path, 384) -- 0600 in decimal
	if not ok then
		-- Permissions may not be supported on this platform
		return true -- Don't fail on permission errors
	end

	return true
end

-- Check if process is running cross-platform
---@param pid number Process ID
---@return boolean running
local function is_process_running(pid)
	if type(pid) ~= "number" or pid <= 0 then
		return false
	end

	-- Use vim.uv to check if process exists
	local handle = vim.uv.kill(pid, 0) -- Signal 0 just checks existence
	return handle ~= nil
end

-- Create lock file for server discovery
---@param port number Server port
---@param auth_token string Authentication token
---@param lock_path string Path to lock file
---@return boolean|nil success
---@return string|nil error
function M.create_lock_file(port, auth_token, lock_path)
	if type(port) ~= "number" or type(auth_token) ~= "string" or type(lock_path) ~= "string" then
		return nil, "Invalid arguments"
	end

	-- Prepare lock file content
	local content_ok, content = pcall(vim.json.encode, {
		pid = vim.uv.os_getpid(),
		workspaceFolders = { vim.fn.getcwd() },
		ideName = "Neovim",
		transport = "ws",
		runningInWindows = vim.fn.has("win32") == 1,
		authToken = auth_token,
		port = port,
		version = "0.1.0",
	})

	if not content_ok then
		return nil, "Failed to encode lock file content"
	end

	-- Ensure directory exists
	local dir = vim.fn.fnamemodify(lock_path, ":h")
	local mkdir_ok, mkdir_err = vim.uv.fs_mkdir(dir, 493) -- 0755 in decimal
	if not mkdir_ok then
		-- Check if the error is because the directory already exists
		if tostring(mkdir_err):match("EEXIST") then
			-- Directory already exists, that's fine
		else
			return nil, "Failed to create directory: " .. tostring(mkdir_err)
		end
	end

	-- Write lock file atomically
	local fd, open_err = vim.uv.fs_open(lock_path, "w", 420) -- 0644 in decimal
	if not fd then
		return nil, "Failed to open lock file: " .. tostring(open_err)
	end

	local write_ok, write_err = vim.uv.fs_write(fd, content)
	vim.uv.fs_close(fd)

	if not write_ok then
		return nil, "Failed to write lock file: " .. tostring(write_err)
	end

	-- Set restrictive permissions
	set_file_permissions_600(lock_path)

	return true
end

-- Remove lock file
---@param lock_path string Path to lock file
---@return boolean|nil success
---@return string|nil error
function M.remove_lock_file(lock_path)
	if type(lock_path) ~= "string" then
		return nil, "Invalid path"
	end

	local stat = vim.uv.fs_stat(lock_path)
	if not stat then
		return true -- File doesn't exist, consider success
	end

	local ok, err = vim.uv.fs_unlink(lock_path)
	if not ok then
		return nil, "Failed to remove lock file: " .. tostring(err)
	end

	return true
end

-- Read existing lock file
---@param lock_path string Path to lock file
---@return table|nil data Lock file data or nil
---@return string|nil error
function M.read_lock_file(lock_path)
	if type(lock_path) ~= "string" then
		return nil, "Invalid path"
	end

	local fd, open_err = vim.uv.fs_open(lock_path, "r", 0)
	if not fd then
		return nil, "Cannot open lock file: " .. tostring(open_err)
	end

	local stat, stat_err = vim.uv.fs_fstat(fd)
	if not stat then
		vim.uv.fs_close(fd)
		return nil, "Cannot stat lock file: " .. tostring(stat_err)
	end

	local content, read_err = vim.uv.fs_read(fd, stat.size)
	vim.uv.fs_close(fd)

	if not content then
		return nil, "Cannot read lock file: " .. tostring(read_err)
	end

	local ok, data = pcall(vim.json.decode, content)
	if not ok then
		return nil, "Invalid JSON in lock file"
	end

	return data
end

-- Check if another server is running
---@param lock_path string Path to lock file
---@return boolean running
function M.is_server_running(lock_path)
	local data, err = M.read_lock_file(lock_path)
	if not data or err then
		return false
	end

	if not data.pid or type(data.pid) ~= "number" then
		return false
	end

	return is_process_running(data.pid)
end

-- Clean stale lock files
---@param lock_path string Path to lock file
---@return boolean|nil success
---@return string|nil error
function M.clean_stale_lock(lock_path)
	if not M.is_server_running(lock_path) then
		return M.remove_lock_file(lock_path)
	end
	return true
end

return M
