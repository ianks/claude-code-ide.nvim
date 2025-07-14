-- Lock File Management Tests
-- Tests the discovery mechanism via lock files

describe("Lock File Management", function()
  local discovery = require("claude-code.discovery")
  local temp_dir
  
  before_each(function()
    -- Create temporary directory for testing
    temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    
    -- Mock the lock file directory
    discovery._set_lock_dir(temp_dir)
  end)
  
  after_each(function()
    -- Clean up temp directory
    vim.fn.delete(temp_dir, "rf")
  end)
  
  describe("lock file creation", function()
    it("should create lock file with correct format", function()
      local port = 12345
      local auth_token = "test-token-123"
      local workspace = "/test/workspace"
      
      local lock_path = discovery.create_lock_file(port, auth_token, workspace)
      
      -- Verify file was created
      assert.is_string(lock_path)
      assert.equals(temp_dir .. "/" .. port .. ".lock", lock_path)
      assert.is_true(vim.fn.filereadable(lock_path) == 1)
      
      -- Verify content
      local content = vim.fn.readfile(lock_path)
      local data = vim.json.decode(table.concat(content))
      
      assert.is_number(data.pid)
      assert.is_table(data.workspaceFolders)
      assert.equals(workspace, data.workspaceFolders[1])
      assert.equals("Neovim", data.ideName)
      assert.equals("ws", data.transport)
      assert.is_boolean(data.runningInWindows)
      assert.equals(auth_token, data.authToken)
    end)
    
    it("should set correct file permissions (600)", function()
      local port = 12346
      local lock_path = discovery.create_lock_file(port, "token", "/workspace")
      
      -- Get file permissions
      local stat = vim.loop.fs_stat(lock_path)
      local mode = stat.mode
      
      -- Extract permission bits (last 3 digits in octal)
      local perms = bit.band(mode, 511) -- 0777 in decimal
      local octal_perms = string.format("%o", perms)
      
      assert.equals("600", octal_perms)
    end)
    
    it("should update existing lock file with new workspace folders", function()
      local port = 12347
      local auth_token = "test-token"
      
      -- Create initial lock file
      discovery.create_lock_file(port, auth_token, "/workspace1")
      
      -- Update with new workspace
      discovery.create_lock_file(port, auth_token, "/workspace2")
      
      -- Verify updated content
      local lock_path = temp_dir .. "/" .. port .. ".lock"
      local content = vim.fn.readfile(lock_path)
      local data = vim.json.decode(table.concat(content))
      
      assert.equals("/workspace2", data.workspaceFolders[1])
      assert.equals(auth_token, data.authToken) -- Token should remain the same
    end)
  end)
  
  describe("lock file deletion", function()
    it("should delete lock file", function()
      local port = 12348
      local lock_path = discovery.create_lock_file(port, "token", "/workspace")
      
      -- Verify file exists
      assert.is_true(vim.fn.filereadable(lock_path) == 1)
      
      -- Delete lock file
      discovery.delete_lock_file(port)
      
      -- Verify file is gone
      assert.is_true(vim.fn.filereadable(lock_path) == 0)
    end)
    
    it("should handle missing lock file gracefully", function()
      -- Try to delete non-existent lock file
      assert.has_no.errors(function()
        discovery.delete_lock_file(99999)
      end)
    end)
  end)
  
  describe("lock file discovery", function()
    it("should find all lock files", function()
      -- Create multiple lock files
      discovery.create_lock_file(10001, "token1", "/workspace1")
      discovery.create_lock_file(10002, "token2", "/workspace2")
      discovery.create_lock_file(10003, "token3", "/workspace3")
      
      -- Find all lock files
      local servers = discovery.list_servers()
      
      assert.equals(3, #servers)
      
      -- Verify each server info
      local ports = {}
      for _, server in ipairs(servers) do
        assert.is_number(server.port)
        assert.is_string(server.authToken)
        assert.is_table(server.workspaceFolders)
        table.insert(ports, server.port)
      end
      
      table.sort(ports)
      assert.same({10001, 10002, 10003}, ports)
    end)
    
    it("should ignore invalid lock files", function()
      -- Create valid lock file
      discovery.create_lock_file(10004, "token", "/workspace")
      
      -- Create invalid lock file
      local invalid_path = temp_dir .. "/invalid.lock"
      vim.fn.writefile({"invalid json"}, invalid_path)
      
      -- Should only find valid server
      local servers = discovery.list_servers()
      assert.equals(1, #servers)
      assert.equals(10004, servers[1].port)
    end)
  end)
  
  describe("platform compatibility", function()
    it("should set correct runningInWindows flag", function()
      local port = 12349
      local lock_path = discovery.create_lock_file(port, "token", "/workspace")
      
      local content = vim.fn.readfile(lock_path)
      local data = vim.json.decode(table.concat(content))
      
      local expected = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
      assert.equals(expected, data.runningInWindows)
    end)
  end)
end)