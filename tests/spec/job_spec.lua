describe("claude-code-ide.job", function()
  local Job = require("claude-code-ide.job")
  local async = require("plenary.async")

  -- Mock RPC connection
  local mock_rpc = {
    _send = function(self, message)
      self.last_message = message
    end
  }

  before_each(function()
    mock_rpc.last_message = nil
  end)

  it("should create a job with unique ID", function()
    local job1 = Job.new({
      tool_name = "test_tool",
      tool_params = { param1 = "value1" },
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local job2 = Job.new({
      tool_name = "test_tool",
      tool_params = { param1 = "value1" },
      request_id = 124,
      rpc_connection = mock_rpc
    })

    assert.is_string(job1.id)
    assert.is_string(job2.id)
    assert.are_not_equal(job1.id, job2.id)
  end)

  it("should initialize with PENDING status", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    assert.equals("PENDING", job.status)
  end)

  it("should update status correctly", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    job:update_status("RUNNING")
    assert.equals("RUNNING", job.status)

    job:update_status("COMPLETED")
    assert.equals("COMPLETED", job.status)
  end)

  it("should resolve successfully and send response", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local result = { data = "test result" }
    job:resolve(result)

    assert.equals("COMPLETED", job.status)
    assert.same(result, job.result)
    assert.is_nil(job.error)

    -- Check RPC response was sent
    assert.is_table(mock_rpc.last_message)
    assert.equals(123, mock_rpc.last_message.id)
    assert.equals("2.0", mock_rpc.last_message.jsonrpc)
    assert.is_table(mock_rpc.last_message.result)
  end)

  it("should reject with error and send error response", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local error_msg = "Test error"
    job:reject(error_msg)

    assert.equals("FAILED", job.status)
    assert.equals(error_msg, job.error)
    assert.is_nil(job.result)

    -- Check error response was sent
    assert.is_table(mock_rpc.last_message)
    assert.equals(123, mock_rpc.last_message.id)
    assert.equals("2.0", mock_rpc.last_message.jsonrpc)
    assert.is_table(mock_rpc.last_message.error)
    assert.equals(-32603, mock_rpc.last_message.error.code)
  end)

  it("should run synchronous tool successfully", function()
    local job = Job.new({
      tool_name = "sync_tool",
      tool_params = { input = "test" },
      request_id = 123,
      rpc_connection = mock_rpc
    })

    -- Synchronous tool function (ignores resolve/reject)
    local tool_fn = function(params, resolve, reject)
      return { output = params.input .. "_processed" }
    end

    -- Run the job
    job:run(tool_fn)

    -- Wait for completion
    vim.wait(500, function()
      return job.status ~= "PENDING" and job.status ~= "RUNNING"
    end, 10)

    assert.equals("COMPLETED", job.status)
    assert.is_table(job.result)
    assert.equals("test_processed", job.result.output)
  end)

  it("should handle tool function errors", function()
    local job = Job.new({
      tool_name = "error_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    -- Tool that throws an error
    local tool_fn = function(params, resolve, reject)
      error("Tool execution failed")
    end

    -- Run the job
    job:run(tool_fn)

    -- Wait for failure
    vim.wait(500, function()
      return job.status ~= "PENDING" and job.status ~= "RUNNING"
    end, 10)

    assert.equals("FAILED", job.status)
    assert.is_string(job.error)
    assert.match("Tool execution failed", job.error)
  end)

  it("should handle async tools", function()
    local job = Job.new({
      tool_name = "async_tool",
      tool_params = { delay = 20 },
      request_id = 123,
      rpc_connection = mock_rpc
    })

    -- Async tool that uses callbacks
    local tool_fn = function(params, resolve, reject)
      vim.defer_fn(function()
        resolve({ async_result = "completed" })
      end, params.delay)
      return { _async = true }
    end

    -- Run the job
    job:run(tool_fn)

    -- Should eventually complete
    vim.wait(500, function()
      return job.status ~= "PENDING" and job.status ~= "RUNNING"
    end, 10)

    assert.equals("COMPLETED", job.status)
    assert.is_table(job.result)
    assert.equals("completed", job.result.async_result)
  end)
end)