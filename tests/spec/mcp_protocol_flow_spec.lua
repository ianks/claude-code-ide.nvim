-- MCP Protocol Flow Tests
-- Tests the actual protocol message flow

local mock = require("tests.spec.helpers.mock_mcp_client")
local json = vim.json

describe("MCP Protocol Flow", function()
  local server
  local client
  
  before_each(function()
    -- Create mock server and client
    server = mock.create_server()
    client = mock.create_client()
  end)
  
  after_each(function()
    if server then server:close() end
    if client then client:close() end
  end)
  
  describe("connection flow", function()
    it("should complete WebSocket handshake", function()
      -- Connect client to server
      local connected = client:connect(server.port, server.auth_token)
      assert.is_true(connected)
      
      -- Verify WebSocket upgrade
      assert.equals("connected", client.state)
    end)
    
    it("should reject unauthorized connections", function()
      -- Try to connect with wrong token
      local connected = client:connect(server.port, "wrong-token")
      assert.is_false(connected)
      assert.equals(401, client.last_error_code)
    end)
  end)
  
  describe("initialization flow", function()
    it("should complete MCP initialization", function()
      client:connect(server.port, server.auth_token)
      
      -- Send initialize request
      local response = client:request("initialize", {
        protocolVersion = "2025-06-18",
        capabilities = {},
        clientInfo = {
          name = "Test Client",
          version = "1.0.0"
        }
      })
      
      -- Verify response
      assert.is_table(response.result)
      assert.equals("2025-06-18", response.result.protocolVersion)
      assert.is_table(response.result.capabilities)
      assert.equals("claude-code.nvim", response.result.serverInfo.name)
      
      -- Send initialized notification
      client:notify("notifications/initialized", {})
      
      -- Server should now be ready
      assert.is_true(server:is_initialized())
    end)
    
    it("should reject requests before initialization", function()
      client:connect(server.port, server.auth_token)
      
      -- Try to call tool before initialization
      local response = client:request("tools/call", {
        name = "openFile",
        arguments = { filePath = "test.lua" }
      })
      
      assert.is_table(response.error)
      assert.equals(-32002, response.error.code) -- Server not initialized
    end)
  end)
  
  describe("tool execution", function()
    before_each(function()
      -- Complete initialization
      client:connect(server.port, server.auth_token)
      client:request("initialize", {
        protocolVersion = "2025-06-18",
        capabilities = {},
        clientInfo = { name = "Test", version = "1.0.0" }
      })
      client:notify("notifications/initialized", {})
    end)
    
    it("should list available tools", function()
      local response = client:request("tools/list", {})
      
      assert.is_table(response.result)
      assert.is_table(response.result.tools)
      
      -- Find openFile tool
      local openFile = vim.tbl_filter(function(tool)
        return tool.name == "openFile"
      end, response.result.tools)[1]
      
      assert.is_table(openFile)
      assert.equals("openFile", openFile.name)
      assert.is_string(openFile.description)
      assert.is_table(openFile.inputSchema)
    end)
    
    it("should execute openFile tool", function()
      local response = client:request("tools/call", {
        name = "openFile",
        arguments = {
          filePath = "test.lua",
          preview = false,
          makeFrontmost = true
        }
      })
      
      assert.is_table(response.result)
      assert.is_table(response.result.content)
      assert.equals("text", response.result.content[1].type)
    end)
    
    it("should validate tool arguments", function()
      local response = client:request("tools/call", {
        name = "openFile",
        arguments = {
          -- Missing required filePath
          preview = false
        }
      })
      
      assert.is_table(response.error)
      assert.equals(-32602, response.error.code) -- Invalid params
    end)
  end)
  
  describe("message format validation", function()
    it("should use JSON-RPC 2.0 format", function()
      client:connect(server.port, server.auth_token)
      
      -- Capture raw message
      local raw_message = client:capture_next_message(function()
        client:request("initialize", { protocolVersion = "2025-06-18" })
      end)
      
      local message = json.decode(raw_message)
      assert.equals("2.0", message.jsonrpc)
      assert.is_number(message.id)
      assert.equals("initialize", message.method)
      assert.is_table(message.params)
    end)
    
    it("should handle batch requests", function()
      client:connect(server.port, server.auth_token)
      
      local batch = {
        {
          jsonrpc = "2.0",
          method = "tools/list",
          id = 1
        },
        {
          jsonrpc = "2.0",
          method = "resources/list",
          id = 2
        }
      }
      
      local responses = client:request_batch(batch)
      assert.equals(2, #responses)
      assert.equals(1, responses[1].id)
      assert.equals(2, responses[2].id)
    end)
  end)
end)