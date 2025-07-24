local async = require("plenary.async")
local Promise = require("plenary.async.util").Promise

---@class Job
---@field id string Unique identifier for the job
---@field tool_name string Name of the tool to execute
---@field tool_params table Parameters for the tool
---@field request_id integer Original RPC request ID
---@field rpc_connection table Reference to RPC connection
---@field status string Job status: PENDING, RUNNING, COMPLETED, FAILED
---@field result any? Result of the job when completed
---@field error any? Error if the job failed
---@field promise table? Plenary async promise
local Job = {}
Job.__index = Job

local job_counter = 0

---Create a new job
---@param opts table Job configuration
---@return Job
function Job.new(opts)
  job_counter = job_counter + 1
  local self = setmetatable({}, Job)
  
  self.id = string.format("job_%d_%d", vim.loop.now(), job_counter)
  self.tool_name = opts.tool_name
  self.tool_params = opts.tool_params or {}
  self.request_id = opts.request_id
  self.rpc_connection = opts.rpc_connection
  self.status = "PENDING"
  self.result = nil
  self.error = nil
  self.promise = nil
  
  return self
end

---Run the job asynchronously
---@param tool_fn function The tool function to execute
---@return table Promise
function Job:run(tool_fn)
  self:update_status("RUNNING")
  
  -- Create a simple promise implementation
  local promise_resolved = false
  local promise_rejected = false
  local promise_result = nil
  local promise_error = nil
  
  local resolve_handlers = {}
  local reject_handlers = {}
  
  local function resolve(result)
    if promise_resolved or promise_rejected then return end
    promise_resolved = true
    promise_result = result
    for _, handler in ipairs(resolve_handlers) do
      handler(result)
    end
  end
  
  local function reject(error)
    if promise_resolved or promise_rejected then return end
    promise_rejected = true
    promise_error = error
    for _, handler in ipairs(reject_handlers) do
      handler(error)
    end
  end
  
  self.promise = {
    next = function(_, on_resolve, on_reject)
      if promise_resolved then
        if on_resolve then on_resolve(promise_result) end
      elseif promise_rejected then
        if on_reject then on_reject(promise_error) end
      else
        if on_resolve then table.insert(resolve_handlers, on_resolve) end
        if on_reject then table.insert(reject_handlers, on_reject) end
      end
    end
  }
  
  -- Run the tool function in a protected call
  vim.schedule(function()
    local success, result = pcall(tool_fn, self.tool_params, resolve, reject)
    
    if not success then
      -- Tool function threw an error
      reject(result)
    elseif result and type(result) == "table" and result._async then
      -- Tool is handling its own async flow
      -- The promise will be settled by the tool calling resolve/reject
    else
      -- Synchronous tool - resolve immediately
      resolve(result)
    end
  end)
  
  -- Set up promise handlers
  self.promise:next(function(result)
    self:resolve(result)
  end, function(err)
    self:reject(err)
  end)
  
  return self.promise
end

---Update the job's status
---@param status string New status
function Job:update_status(status)
  self.status = status
end

---Resolve the job successfully
---@param result any The result value
function Job:resolve(result)
  self.result = result
  self:update_status("COMPLETED")
  
  -- Send success response back to client
  if self.rpc_connection and self.request_id then
    local response = {
      jsonrpc = "2.0",
      id = self.request_id,
      result = result
    }
    self.rpc_connection:_send(response)
  end
end

---Reject the job with an error
---@param err any The error
function Job:reject(err)
  self.error = err
  self:update_status("FAILED")
  
  -- Send error response back to client
  if self.rpc_connection and self.request_id then
    local error_message = type(err) == "string" and err or vim.inspect(err)
    local response = {
      jsonrpc = "2.0",
      id = self.request_id,
      error = {
        code = -32603,
        message = "Tool execution failed",
        data = error_message
      }
    }
    self.rpc_connection:_send(response)
  end
end

return Job