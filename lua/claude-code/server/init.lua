-- WebSocket server initialization for claude-code.nvim

local M = {}
M.__index = M

-- Create a new server instance
---@param config table Configuration
---@return table server Server instance
function M.new(config)
  local self = setmetatable({}, M)
  self.config = config
  self.tcp_server = nil
  self.port = nil
  self.auth_token = nil
  self.clients = {}
  self.running = false
  return self
end

-- Start the WebSocket server
---@param config table Configuration
---@return table server Server instance
function M.start(config)
  local server = M.new(config)

  -- Initialize components
  local websocket = require("claude-code.server.websocket")
  local auth = require("claude-code.server.auth")
  local discovery = require("claude-code.server.discovery")

  -- Generate auth token
  server.auth_token = auth.generate_token()

  -- Find available port
  server.port = server:_find_available_port()

  -- Create TCP server
  server.tcp_server = vim.uv.new_tcp()
  server.tcp_server:bind(server.config.server.host, server.port)

  -- Start listening
  server.tcp_server:listen(128, function(err)
    if err then
      vim.notify("Failed to start server: " .. err, vim.log.levels.ERROR)
      return
    end

    local client = vim.uv.new_tcp()
    server.tcp_server:accept(client)

    -- Handle new connection
    websocket.handle_connection(client, server)
  end)

  -- Create lock file
  discovery.create_lock_file(server.port, server.auth_token, config.lock_file.path)

  server.running = true
  vim.notify("Claude Code server started on port " .. server.port, vim.log.levels.INFO)

  return server
end

-- Stop the server
function M:stop()
  if self.tcp_server then
    self.tcp_server:close()
  end

  -- Close all client connections
  for _, client in pairs(self.clients) do
    if client.socket then
      client.socket:close()
    end
  end

  -- Remove lock file
  local discovery = require("claude-code.server.discovery")
  discovery.remove_lock_file(self.config.lock_file.path)

  self.running = false
  vim.notify("Claude Code server stopped", vim.log.levels.INFO)
end

-- Check if server is running
function M:is_running()
  return self.running
end

-- Find an available port in the configured range
---@return number port Available port number
function M:_find_available_port()
  if self.config.server.port ~= 0 then
    return self.config.server.port
  end

  local min_port, max_port = unpack(self.config.server.port_range)
  
  for port = min_port, max_port do
    local sock = vim.uv.new_tcp()
    local success = pcall(function()
      sock:bind("127.0.0.1", port)
    end)
    sock:close()
    
    if success then
      return port
    end
  end

  error("No available ports in range " .. min_port .. "-" .. max_port)
end

-- Add a client connection
---@param client_id string Client identifier
---@param client table Client connection
function M:add_client(client_id, client)
  self.clients[client_id] = client
end

-- Remove a client connection
---@param client_id string Client identifier
function M:remove_client(client_id)
  self.clients[client_id] = nil
end

return M