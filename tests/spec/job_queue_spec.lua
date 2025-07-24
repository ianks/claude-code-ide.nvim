describe("claude-code-ide.job_queue", function()
  local JobQueue = require("claude-code-ide.job_queue")
  local Job = require("claude-code-ide.job")

  local queue
  local mock_rpc = {
    send = function(self, message) end
  }

  before_each(function()
    -- Reset singleton
    package.loaded["claude-code-ide.job_queue"] = nil
    JobQueue = require("claude-code-ide.job_queue")
    queue = JobQueue.get_instance()
  end)

  it("should be a singleton", function()
    local queue1 = JobQueue.get_instance()
    local queue2 = JobQueue.get_instance()
    assert.are_equal(queue1, queue2)
  end)

  it("should add and retrieve jobs", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local tool_fn = function(params)
      return { result = "test" }
    end

    queue:add(job, tool_fn)

    -- Job should be in the queue
    local retrieved = queue:get(job.id)
    assert.are_equal(job, retrieved)
  end)

  it("should get all jobs", function()
    local job1 = Job.new({
      tool_name = "tool1",
      tool_params = {},
      request_id = 1,
      rpc_connection = mock_rpc
    })

    local job2 = Job.new({
      tool_name = "tool2",
      tool_params = {},
      request_id = 2,
      rpc_connection = mock_rpc
    })

    local tool_fn = function(params) return {} end

    queue:add(job1, tool_fn)
    queue:add(job2, tool_fn)

    local all_jobs = queue:get_all()
    assert.equals(2, #all_jobs)
  end)

  it("should remove jobs", function()
    local job = Job.new({
      tool_name = "test_tool",
      tool_params = {},
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local tool_fn = function(params) return {} end
    queue:add(job, tool_fn)

    -- Verify job is there
    assert.is_not_nil(queue:get(job.id))

    -- Remove it
    queue:remove(job.id)

    -- Should be gone
    assert.is_nil(queue:get(job.id))
  end)

  it("should get jobs by status", function()
    local pending_job = Job.new({
      tool_name = "pending",
      tool_params = {},
      request_id = 1,
      rpc_connection = mock_rpc
    })

    local running_job = Job.new({
      tool_name = "running",
      tool_params = {},
      request_id = 2,
      rpc_connection = mock_rpc
    })
    running_job:update_status("RUNNING")

    local completed_job = Job.new({
      tool_name = "completed",
      tool_params = {},
      request_id = 3,
      rpc_connection = mock_rpc
    })
    completed_job:update_status("COMPLETED")

    -- Add jobs without running them (to control status)
    queue.jobs[pending_job.id] = pending_job
    queue.jobs[running_job.id] = running_job
    queue.jobs[completed_job.id] = completed_job

    local pending = queue:get_by_status("PENDING")
    local running = queue:get_by_status("RUNNING")
    local completed = queue:get_by_status("COMPLETED")

    assert.equals(1, #pending)
    assert.equals(1, #running)
    assert.equals(1, #completed)
  end)

  it("should cleanup completed and failed jobs", function()
    local pending = Job.new({
      tool_name = "pending",
      tool_params = {},
      request_id = 1,
      rpc_connection = mock_rpc
    })

    local completed = Job.new({
      tool_name = "completed",
      tool_params = {},
      request_id = 2,
      rpc_connection = mock_rpc
    })
    completed:update_status("COMPLETED")

    local failed = Job.new({
      tool_name = "failed",
      tool_params = {},
      request_id = 3,
      rpc_connection = mock_rpc
    })
    failed:update_status("FAILED")

    -- Add jobs directly
    queue.jobs[pending.id] = pending
    queue.jobs[completed.id] = completed
    queue.jobs[failed.id] = failed

    -- Cleanup
    queue:cleanup()

    -- Only pending should remain
    assert.is_not_nil(queue:get(pending.id))
    assert.is_nil(queue:get(completed.id))
    assert.is_nil(queue:get(failed.id))
  end)

  it("should run jobs immediately when added", function()
    local job = Job.new({
      tool_name = "immediate",
      tool_params = { value = 42 },
      request_id = 123,
      rpc_connection = mock_rpc
    })

    local tool_executed = false
    local tool_fn = function(params)
      tool_executed = true
      return { received = params.value }
    end

    queue:add(job, tool_fn)

    -- Give it a moment to execute
    vim.wait(50, function()
      return tool_executed
    end)

    assert.is_true(tool_executed)
  end)
end)