-- MCP Tools handlers with enhanced error handling and caching
-- Implements the MCP tools/list and tools/call protocol methods

local tools = require("claude-code-ide.tools")
local events = require("claude-code-ide.events")
local cache = require("claude-code-ide.cache")
local log = require("claude-code-ide.log")

local M = {}

-- Configuration constants
local CONFIG = {
	MAX_TOOL_NAME_LENGTH = 128,
	MAX_ARGUMENT_SIZE = 1024 * 1024, -- 1MB limit for arguments
	DEFAULT_CACHE_TTL = 60, -- 1 minute default
	WORKSPACE_CACHE_TTL = 600, -- 10 minutes for workspace info
}

-- Cacheable tools configuration
local CACHEABLE_TOOLS = {
	getWorkspaceFolders = { ttl = CONFIG.WORKSPACE_CACHE_TTL, enabled = true },
	getCurrentSelection = { ttl = 0, enabled = false }, -- Dynamic content
	getOpenEditors = { ttl = 0, enabled = false }, -- Changes frequently
	getDiagnostics = { ttl = 0, enabled = false }, -- Changes frequently
	openFile = { ttl = 0, enabled = false }, -- Has side effects
	openDiff = { ttl = 0, enabled = false }, -- Has side effects
	executeCode = { ttl = 0, enabled = false }, -- Has side effects
}

-- Generate secure cache key for tool calls
---@param tool_name string Tool name
---@param arguments table Tool arguments
---@return string cache_key
local function generate_cache_key(tool_name, arguments)
	local key_parts = { "tools", "call", tool_name }

	-- Sort arguments for consistent keys
	local sorted_args = {}
	for k, v in pairs(arguments or {}) do
		table.insert(sorted_args, k .. "=" .. tostring(v))
	end
	table.sort(sorted_args)

	for _, arg in ipairs(sorted_args) do
		table.insert(key_parts, arg)
	end

	return table.concat(key_parts, ":")
end

-- Get the tools cache with error handling
---@return table? cache_instance
local function get_cache()
	local ok, cache_instance = pcall(cache.caches.tools)
	if not ok then
		log.warn("Tools", "Failed to get cache instance", { error = cache_instance })
		return nil
	end
	return cache_instance
end

-- Validate tool name
---@param tool_name string Tool name to validate
---@return boolean valid, string? error_message
local function validate_tool_name(tool_name)
	if type(tool_name) ~= "string" then
		return false, "Tool name must be a string"
	end

	if #tool_name == 0 then
		return false, "Tool name cannot be empty"
	end

	if #tool_name > CONFIG.MAX_TOOL_NAME_LENGTH then
		return false, "Tool name too long (max " .. CONFIG.MAX_TOOL_NAME_LENGTH .. " characters)"
	end

	-- Allow alphanumeric, underscore, and camelCase
	if not tool_name:match("^[%w_]+$") then
		return false, "Tool name contains invalid characters"
	end

	return true, nil
end

-- Validate tool arguments
---@param arguments table Tool arguments to validate
---@return boolean valid, string? error_message
local function validate_arguments(arguments)
	if arguments == nil then
		return true, nil
	end

	if type(arguments) ~= "table" then
		return false, "Arguments must be a table"
	end

	-- Check argument size
	local ok, serialized = pcall(vim.json.encode, arguments)
	if not ok then
		return false, "Arguments must be JSON serializable"
	end

	if #serialized > CONFIG.MAX_ARGUMENT_SIZE then
		return false, "Arguments too large (max " .. CONFIG.MAX_ARGUMENT_SIZE .. " bytes)"
	end

	return true, nil
end

-- Determine if a tool result is cacheable and get TTL
---@param tool_name string Tool name
---@return boolean cacheable, number ttl
local function get_cache_config(tool_name)
	local config = CACHEABLE_TOOLS[tool_name]
	if not config or not config.enabled then
		return false, 0
	end
	return true, config.ttl
end

-- Validate and sanitize tool list result
---@param tools_list table List of tools
---@return table sanitized_list
local function sanitize_tools_list(tools_list)
	if not tools_list or type(tools_list) ~= "table" then
		log.warn("Tools", "Invalid tools list returned")
		return {}
	end

	local sanitized = {}
	for _, tool in ipairs(tools_list) do
		if tool and type(tool) == "table" and tool.name then
			-- Fix empty properties encoding issue
			if tool.inputSchema and tool.inputSchema.properties then
				if vim.tbl_isempty(tool.inputSchema.properties) then
					tool.inputSchema.properties = vim.empty_dict()
				end
			end

			table.insert(sanitized, {
				name = tostring(tool.name),
				description = tostring(tool.description or ""),
				inputSchema = tool.inputSchema or {
					type = "object",
					properties = vim.empty_dict(),
				},
			})
		end
	end

	return sanitized
end

-- Handle tools/list request with enhanced error handling
---@param rpc table RPC instance
---@param params table Request parameters (supports cursor for pagination)
---@return table Response with tools list
function M.list_tools(rpc, params)
	log.debug("Tools", "list_tools called", params)

	-- Get all tools from the registry with error handling
	local ok, all_tools = pcall(tools.list)
	if not ok then
		log.error("Tools", "Failed to list tools", { error = all_tools })
		error("Failed to retrieve tools: " .. tostring(all_tools))
	end

	-- Validate and sanitize tools list
	local sanitized_tools = sanitize_tools_list(all_tools)

	-- Emit tool listing event
	local event_ok, event_err = pcall(events.emit, events.events.TOOL_EXECUTING, {
		method = "tools/list",
		count = #sanitized_tools,
	})

	if not event_ok then
		log.warn("Tools", "Failed to emit tool listing event", { error = event_err })
	end

	log.debug("Tools", "Returning tools list", { count = #sanitized_tools })

	return {
		tools = sanitized_tools,
		-- Future: Add pagination support if needed
		-- nextCursor = nil
	}
end

-- Handle tools/call request with comprehensive error handling
---@param rpc table RPC instance
---@param params table Request parameters with name and arguments
---@param request_id integer The RPC request ID
function M.call_tool(rpc, params, request_id)
	log.debug("Tools", "call_tool called", params)

	-- Load job system dependencies
	local Job = require("claude-code-ide.job")
	local JobQueue = require("claude-code-ide.job_queue")
	
	-- Validate parameters
	if not params or type(params) ~= "table" then
		error("Parameters must be a table")
	end

	local tool_name = params.name
	local arguments = params.arguments or {}

	-- Validate tool name
	local valid, error_msg = validate_tool_name(tool_name)
	if not valid then
		error("Invalid tool name: " .. error_msg)
	end

	-- Validate arguments
	valid, error_msg = validate_arguments(arguments)
	if not valid then
		error("Invalid arguments: " .. error_msg)
	end

	-- Check cache for cacheable tools
	local cacheable, cache_ttl = get_cache_config(tool_name)
	if cacheable then
		local cache_instance = get_cache()
		if cache_instance then
			local cache_key = generate_cache_key(tool_name, arguments)
			local cached, hit = cache_instance:get(cache_key)
			if hit then
				log.debug("Tools", "Tool result served from cache", { tool = tool_name })

				-- Emit cached result event
				pcall(events.emit, events.events.TOOL_EXECUTED, {
					tool = tool_name,
					result = cached,
					from_cache = true,
				})

				-- Send cached result immediately
				local response = {
					jsonrpc = "2.0",
					id = request_id,
					result = cached
				}
				rpc:_send(response)
				return
			end
		end
	end

	-- Get the tool function
	local tool_fn = tools.get_tool(tool_name)
	if not tool_fn then
		error("Tool not found: " .. tool_name)
	end

	-- Create a job for this tool execution
	local job = Job.new({
		tool_name = tool_name,
		tool_params = arguments,
		request_id = request_id,
		rpc_connection = rpc
	})

	-- Emit tool executing event
	pcall(events.emit, events.events.TOOL_EXECUTING, {
		tool = tool_name,
		arguments = arguments,
		job_id = job.id
	})

	-- Create a wrapped tool function that includes session
	local wrapped_tool_fn = function(params, resolve, reject)
		-- Execute the tool with the session
		local session = rpc.connection
		local exec_ok, result = pcall(tool_fn, params, session)
		
		if not exec_ok then
			-- Tool execution failed
			local error_msg = tostring(result)
			log.error("Tools", "Tool execution failed", {
				tool = tool_name,
				error = error_msg,
				arguments = arguments,
			})

			-- Emit failure event
			pcall(events.emit, events.events.TOOL_FAILED, {
				tool = tool_name,
				error = error_msg,
			})

			-- Reject the job
			reject("Tool execution failed: " .. error_msg)
			return
		end

		-- Check if tool is handling its own async flow
		if type(result) == "table" and result._async then
			-- Tool will call resolve/reject itself
			return result
		end

		-- For synchronous tools or successful results
		if cacheable and cache_ttl > 0 then
			-- Cache the result
			local cache_instance = get_cache()
			if cache_instance then
				local cache_key = generate_cache_key(tool_name, arguments)
				cache_instance:set(cache_key, result, cache_ttl)
			end
		end

		-- Emit success event
		pcall(events.emit, events.events.TOOL_EXECUTED, {
			tool = tool_name,
			result = result,
			from_cache = false,
		})

		-- Resolve the job
		resolve(result)
	end

	-- Add the job to the queue and run it
	local queue = JobQueue.get_instance()
	queue:add(job, wrapped_tool_fn)
end

-- Get a tool's definition
---@param name string Tool name
