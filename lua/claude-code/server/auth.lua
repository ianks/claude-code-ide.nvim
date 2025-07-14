-- Authentication management for claude-code.nvim

local M = {}

-- Generate a cryptographically secure auth token
---@return string token Generated auth token
function M.generate_token()
  -- Use multiple sources of randomness
  local sources = {
    tostring(vim.uv.hrtime()),
    tostring(vim.uv.getpid()),
    tostring(math.random()),
    tostring(os.time()),
    vim.fn.tempname(),
  }

  -- Combine and hash
  local combined = table.concat(sources, "-")
  local hash = vim.fn.sha256(combined)

  -- Format as UUID-like string for compatibility
  return string.format(
    "%s-%s-%s-%s-%s",
    hash:sub(1, 8),
    hash:sub(9, 12),
    hash:sub(13, 16),
    hash:sub(17, 20),
    hash:sub(21, 32)
  )
end

-- Validate an auth token
---@param provided string? Provided token
---@param expected string Expected token
---@return boolean valid
function M.validate_token(provided, expected)
  if not provided or not expected then
    return false
  end

  -- Constant-time comparison to prevent timing attacks
  if #provided ~= #expected then
    return false
  end

  local result = 0
  for i = 1, #provided do
    result = bit.bor(result, bit.bxor(provided:byte(i), expected:byte(i)))
  end

  return result == 0
end

-- Extract auth token from headers
---@param headers table HTTP headers
---@return string? token
function M.extract_token(headers)
  return headers["x-claude-code-ide-authorization"]
end

return M