---@class JobQueue
---@field jobs table<string, Job> Map of job ID to Job instance
local JobQueue = {}
JobQueue.__index = JobQueue

-- Singleton instance
local instance = nil

---Get or create the singleton JobQueue instance
---@return JobQueue
function JobQueue.get_instance()
  if not instance then
    instance = setmetatable({
      jobs = {}
    }, JobQueue)
  end
  return instance
end

---Add a job to the queue and run it
---@param job Job The job to add
---@param tool_fn function The tool function to execute
---@return Job
function JobQueue:add(job, tool_fn)
  self.jobs[job.id] = job
  
  -- Run the job immediately
  job:run(tool_fn):next(function()
    -- Job completed, could clean up here if needed
  end, function()
    -- Job failed, could clean up here if needed
  end)
  
  return job
end

---Get a job by ID
---@param job_id string The job ID
---@return Job?
function JobQueue:get(job_id)
  return self.jobs[job_id]
end

---Get all current jobs
---@return Job[]
function JobQueue:get_all()
  local jobs = {}
  for _, job in pairs(self.jobs) do
    table.insert(jobs, job)
  end
  return jobs
end

---Remove a completed or failed job
---@param job_id string The job ID to remove
function JobQueue:remove(job_id)
  self.jobs[job_id] = nil
end

---Get jobs by status
---@param status string Status to filter by
---@return Job[]
function JobQueue:get_by_status(status)
  local jobs = {}
  for _, job in pairs(self.jobs) do
    if job.status == status then
      table.insert(jobs, job)
    end
  end
  return jobs
end

---Clear all completed and failed jobs
function JobQueue:cleanup()
  for id, job in pairs(self.jobs) do
    if job.status == "COMPLETED" or job.status == "FAILED" then
      self.jobs[id] = nil
    end
  end
end

return JobQueue