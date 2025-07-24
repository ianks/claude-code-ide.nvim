local async = require("plenary.async")
local ui = require("claude-code-ide.ui")
local log = require("claude-code-ide.log")

local M = {}

-- Run the openDiff job
---@param job_params table The job parameters containing tool_params
---@param resolve function Callback to resolve the job
---@param reject function Callback to reject the job
---@return table Async marker
function M.run(job_params, resolve, reject)
  local params = job_params
  
  -- Validate parameters
  if not params.filePath then
    reject("filePath is required")
    return
  end
  
  if not params.diff then
    reject("diff is required")
    return
  end
  
  log.debug("OpenDiffJob", "Running openDiff job", {
    filePath = params.filePath,
    diff_length = #params.diff
  })
  
  -- Open the diff UI with callbacks
  ui.diff.open_diff({
    filePath = params.filePath,
    diff = params.diff,
    on_accept = function()
      log.info("OpenDiffJob", "Diff accepted", { filePath = params.filePath })
      resolve({
        content = {
          {
            type = "text",
            text = "FILE_SAVED"
          }
        }
      })
    end,
    on_reject = function()
      log.info("OpenDiffJob", "Diff rejected", { filePath = params.filePath })
      resolve({
        content = {
          {
            type = "text",
            text = "DIFF_REJECTED"
          }
        }
      })
    end
  })
  
  -- Return async marker to indicate this job handles its own async flow
  return { _async = true }
end

return M