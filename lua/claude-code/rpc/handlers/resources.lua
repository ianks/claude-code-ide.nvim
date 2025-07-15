-- MCP Resources handlers
-- Currently returns empty resources list as we don't expose any resources yet

local M = {}

-- List available resources
---@param rpc table RPC instance
---@param params table Parameters (unused)
---@return table result
function M.list_resources(rpc, params)
	-- TODO: In the future, we could expose resources like:
	-- - Current buffer content
	-- - Project structure
	-- - Configuration files
	-- - etc.

	return {
		resources = {},
	}
end

-- Read a specific resource
---@param rpc table RPC instance
---@param params table Parameters with uri
---@return table result
function M.read_resource(rpc, params)
	-- Not implemented yet
	error("Resource reading not implemented")
end

return M
