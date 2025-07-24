describe("async diff integration", function()
  local server = require("claude-code-ide.server")
  local rpc = require("claude-code-ide.rpc")
  local async = require("plenary.async")
  
  local test_server
  local test_connection
  local test_rpc
  
  -- Helper to send RPC request and get response
  local function send_request(method, params)
    local response_data = nil
    local response_received = false
    
    -- Mock send callback to capture responses
    local send_callback = function(conn, data)
      response_data = vim.json.decode(data)
      response_received = true
    end
    
    test_rpc = rpc.new(test_connection, send_callback)
    test_connection.rpc = test_rpc
    
    -- Send the request
    local request = {
      jsonrpc = "2.0",
      id = 1,
      method = method,
      params = params
    }
    
    test_rpc:process_message(vim.json.encode(request))
    
    -- Wait for response
    vim.wait(1000, function()
      return response_received
    end)
    
    return response_data
  end
  
  before_each(function()
    -- Start test server
    test_server = server.start({
      host = "127.0.0.1",
      port = 0, -- Random port
      debug = false
    })
    
    -- Create mock connection
    test_connection = {
      id = "test_connection",
      send = function(self, data) end
    }
  end)
  
  after_each(function()
    if test_server then
      test_server:stop()
    end
  end)
  
  it("should handle openDiff tool asynchronously without timeout", function()
    -- Create a test file
    local test_file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({"-- Original content", "print('hello')"}, test_file)
    
    local diff_opened = false
    local decision_made = false
    
    -- Override the openDiff tool to use callback version
    local tools = require("claude-code-ide.tools")
    local original_tool = tools.get_tool("openDiff")
    
    -- Replace the tool temporarily
    local diff_module = require("claude-code-ide.ui.diff")
    diff_module.open_diff_callback = function(opts)
      diff_opened = true
      
      -- Simulate user accepting after a delay
      vim.defer_fn(function()
        opts.on_accept()
        decision_made = true
      end, 100)
      
      return { success = true }
    end
    
    -- Send openDiff request
    local response = send_request("tools/call", {
      name = "openDiff",
      arguments = {
        old_file_path = test_file,
        new_file_path = test_file,
        new_file_contents = "-- Modified content\nprint('world')",
        tab_name = "Test Diff"
      }
    })
    
    -- Wait for decision to be made
    vim.wait(500, function()
      return decision_made
    end)
    
    -- Check response
    assert.is_not_nil(response, "Response should not be nil")
    if response.error then
      print("Error response:", vim.inspect(response.error))
    end
    assert.is_nil(response.error, "Should not have an error")
    assert.is_not_nil(response.result)
    
    -- Check the result content
    local content = response.result.content
    assert.is_table(content)
    assert.equals("text", content[1].type)
    assert.equals("FILE_SAVED", content[1].text)
    
    -- Wait for everything to complete
    vim.wait(500, function()
      return diff_opened and decision_made
    end)
    
    assert.is_true(diff_opened, "Diff should have been opened")
    assert.is_true(decision_made, "Decision should have been made")
    
    -- No need to restore since we're just overriding temporarily
    
    -- Cleanup
    vim.fn.delete(test_file)
  end)
  
  it("should handle diff rejection correctly", function()
    -- Create a test file
    local test_file = vim.fn.tempname() .. ".lua"
    vim.fn.writefile({"-- Original content"}, test_file)
    
    local diff_opened = false
    local decision_made = false
    
    -- Override the diff UI to simulate user rejection
    local diff_module = require("claude-code-ide.ui.diff")
    diff_module.open_diff_callback = function(opts)
      diff_opened = true
      
      -- Simulate user rejecting after a delay
      vim.defer_fn(function()
        opts.on_reject()
        decision_made = true
      end, 50)
      
      return { success = true }
    end
    
    -- Send openDiff request
    async.run(function()
      local response = send_request("tools/call", {
        name = "openDiff",
        arguments = {
          old_file_path = test_file,
          new_file_path = test_file,
          new_file_contents = "-- Modified content",
          tab_name = "Test Diff"
        }
      })
      
      -- Should get a proper response (not an error)
      assert.is_not_nil(response)
      assert.is_nil(response.error, "Should not have an error")
      assert.is_not_nil(response.result)
      
      -- Check the result content
      local content = response.result.content
      assert.is_table(content)
      assert.equals("text", content[1].type)
      assert.equals("DIFF_REJECTED", content[1].text)
    end)
    
    -- Wait for everything to complete
    vim.wait(300, function()
      return diff_opened and decision_made
    end)
    
    assert.is_true(diff_opened, "Diff should have been opened")
    assert.is_true(decision_made, "Decision should have been made")
    
    -- Verify file was not modified
    local file_content = vim.fn.readfile(test_file)
    assert.equals("-- Original content", file_content[1])
    
    -- No need to restore since we're just overriding temporarily
    
    -- Cleanup
    vim.fn.delete(test_file)
  end)
end)