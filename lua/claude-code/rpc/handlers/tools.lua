-- MCP Tools handlers
-- Implements the MCP tools/list and tools/call protocol methods

local tools = require("claude-code.tools")
local events = require("claude-code.events")

local M = {}

-- Handle tools/list request
-- Returns a list of available tools with their metadata
---@param rpc table RPC instance
---@param params table Request parameters (supports cursor for pagination)
---@return table Response with tools list
function M.list_tools(rpc, params)
	-- Get all tools from the registry
	local all_tools = tools.list()

	-- Fix empty properties encoding issue
	-- vim.json.encode converts empty tables {} to [] which violates JSON Schema
	-- We need to ensure properties are always encoded as objects
	for _, tool in ipairs(all_tools) do
		if tool.inputSchema and tool.inputSchema.properties then
			-- Check if properties is empty
			if vim.tbl_isempty(tool.inputSchema.properties) then
				-- Use a metatable to force object encoding
				setmetatable(tool.inputSchema.properties, {
					__jsontype = "object",
				})
			end
		end
	end

	-- TODO: Implement pagination if needed
	-- For now, return all tools

	-- Emit tool listing event
	events.emit(events.events.TOOL_EXECUTING, {
		method = "tools/list",
		count = #all_tools,
	})

	return {
		tools = all_tools,
		-- nextCursor = nil -- No pagination for now
	}
end

-- Handle tools/call request
-- Executes a specific tool with provided arguments
---@param rpc table RPC instance
---@param params table Request parameters with name and arguments
---@return table Tool execution result
function M.call_tool(rpc, params)
	local tool_name = params.name
	local arguments = params.arguments or {}

	-- Emit tool executing event
	events.emit(events.events.TOOL_EXECUTING, {
		tool = tool_name,
		arguments = arguments,
	})

	-- Execute the tool
	local ok, result = pcall(tools.execute, tool_name, arguments)

	if not ok then
		-- Tool execution failed
		local error_msg = tostring(result)

		events.emit(events.events.TOOL_FAILED, {
			tool = tool_name,
			error = error_msg,
		})

		-- Return error result following MCP protocol
		return {
			content = {
				{
					type = "text",
					text = "Tool execution failed: " .. error_msg,
				},
			},
			isError = true,
		}
	end

	-- Tool executed successfully
	events.emit(events.events.TOOL_EXECUTED, {
		tool = tool_name,
		result = result,
	})

	-- Ensure result has the correct structure
	if not result.content then
		-- Wrap plain text responses
		result = {
			content = {
				{
					type = "text",
					text = vim.json.encode(result),
				},
			},
		}
	end

	-- Add isError flag if not present
	if result.isError == nil then
		result.isError = false
	end

	return result
end

return M
