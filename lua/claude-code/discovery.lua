-- Lock file discovery mechanism for claude-code.nvim
-- Manages server discovery via ~/.claude/ide/<port>.lock files

local M = {}

local uv = vim.loop
local json = vim.json

-- Default lock directory
local LOCK_DIR = vim.fn.expand("~/.claude/ide")

-- Override lock directory for testing
function M._set_lock_dir(dir)
  LOCK_DIR = dir
end

-- Ensure lock directory exists with correct permissions
local function ensure_lock_dir()
  if vim.fn.isdirectory(LOCK_DIR) == 0 then
    vim.fn.mkdir(LOCK_DIR, "p")
  end
end

-- Create or update lock file
---@param port number Server port
---@param auth_token string Authentication token
---@param workspace string Current workspace path
---@return string path Path to created lock file
function M.create_lock_file(port, auth_token, workspace)
  ensure_lock_dir()
  
  local lock_path = LOCK_DIR .. "/" .. port .. ".lock"
  local existing_data = nil
  
  -- Try to read existing lock file to preserve auth token
  if vim.fn.filereadable(lock_path) == 1 then
    local ok, content = pcall(vim.fn.readfile, lock_path)
    if ok and content then
      local decode_ok, data = pcall(json.decode, table.concat(content))
      if decode_ok then
        existing_data = data
      end
    end
  end
  
  -- Create lock file data
  local lock_data = {
    pid = vim.fn.getpid(),
    workspaceFolders = { workspace },
    ideName = "Neovim",
    transport = "ws",
    runningInWindows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1,
    authToken = existing_data and existing_data.authToken or auth_token
  }
  
  -- Write lock file
  local content = json.encode(lock_data)
  vim.fn.writefile({content}, lock_path)
  
  -- Set permissions to 600 (owner read/write only)
  uv.fs_chmod(lock_path, tonumber("600", 8))
  
  return lock_path
end

-- Delete lock file
---@param port number Server port
function M.delete_lock_file(port)
  local lock_path = LOCK_DIR .. "/" .. port .. ".lock"
  if vim.fn.filereadable(lock_path) == 1 then
    vim.fn.delete(lock_path)
  end
end

-- List all available servers
---@return table[] servers Array of server info
function M.list_servers()
  ensure_lock_dir()
  
  local servers = {}
  local files = vim.fn.readdir(LOCK_DIR)
  
  for _, file in ipairs(files) do
    if file:match("^%d+%.lock$") then
      local port = tonumber(file:match("^(%d+)%.lock$"))
      local path = LOCK_DIR .. "/" .. file
      
      local ok, content = pcall(vim.fn.readfile, path)
      if ok and content then
        local decode_ok, data = pcall(json.decode, table.concat(content))
        if decode_ok and data then
          data.port = port
          table.insert(servers, data)
        end
      end
    end
  end
  
  return servers
end

-- Find server for current workspace
---@param workspace string Current workspace path
---@return table? server Server info if found
function M.find_server_for_workspace(workspace)
  local servers = M.list_servers()
  
  for _, server in ipairs(servers) do
    if server.workspaceFolders then
      for _, folder in ipairs(server.workspaceFolders) do
        if folder == workspace then
          return server
        end
      end
    end
  end
  
  return nil
end

return M