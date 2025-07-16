-- MCP Resources handlers
-- Provides access to files, templates, snippets, and other resources via MCP

local resources = require("claude-code.resources")
local log = require("claude-code.log")
local notify = require("claude-code.ui.notify")
local cache = require("claude-code.cache")

local M = {}

-- Get the resources cache
local function get_cache()
	return cache.caches.resources()
end

-- List available resources
---@param rpc table RPC instance
---@param params table Parameters (can include cursor for pagination)
---@return table result
function M.list_resources(rpc, params)
	log.debug("RPC", "resources/list called", params)

	-- Get all resources
	local all_resources = resources.list()

	-- Format for MCP protocol
	local formatted_resources = {}
	for _, resource in ipairs(all_resources) do
		table.insert(formatted_resources, {
			uri = resource.uri,
			name = resource.name,
			description = resource.description,
			mimeType = resource.mimeType,
			metadata = resource.metadata,
		})
	end

	-- Handle pagination if cursor is provided
	local result = {
		resources = formatted_resources,
	}

	-- If we have more than 100 resources, implement pagination
	if #formatted_resources > 100 and params and params.cursor then
		-- Simple pagination: cursor is the index to start from
		local start_idx = tonumber(params.cursor) or 1
		local page_size = 100

		result.resources = {}
		for i = start_idx, math.min(start_idx + page_size - 1, #formatted_resources) do
			table.insert(result.resources, formatted_resources[i])
		end

		-- Add next cursor if there are more resources
		if start_idx + page_size <= #formatted_resources then
			result.nextCursor = tostring(start_idx + page_size)
		end
	end

	log.debug("RPC", "Returning resources", { count = #result.resources })

	return result
end

-- Read a specific resource
---@param rpc table RPC instance
---@param params table Parameters with uri
---@return table result
function M.read_resource(rpc, params)
	log.debug("RPC", "resources/read called", params)

	if not params or not params.uri then
		error("Missing required parameter: uri")
	end

	-- Check cache first
	local cache_instance = get_cache()
	local cached, hit = cache_instance:get("resources/read", params)
	if hit then
		log.debug("RPC", "Resource served from cache", { uri = params.uri })
		return cached
	end

	-- Read the resource
	local result = resources.read(params.uri)

	if not result then
		error("Resource not found: " .. params.uri)
	end

	-- Cache the result
	-- Use longer TTL for static resources like templates and snippets
	local ttl = 300 -- 5 minutes default
	if params.uri:match("^template://") or params.uri:match("^snippet://") then
		ttl = 1800 -- 30 minutes for templates/snippets
	elseif params.uri:match("^file://") then
		ttl = 60 -- 1 minute for files (they might change)
	end

	cache_instance:set("resources/read", params, result, ttl)

	log.debug("RPC", "Resource read successfully", { uri = params.uri })

	return result
end

-- Subscribe to resource updates
---@param rpc table RPC instance
---@param params table Parameters (unused)
---@return table result
function M.subscribe_resources(rpc, params)
	log.debug("RPC", "resources/subscribe called", params)

	-- Mark that this client is subscribed to resource updates
	if rpc.connection then
		rpc.connection.subscribed_to_resources = true
	end

	return {}
end

-- Unsubscribe from resource updates
---@param rpc table RPC instance
---@param params table Parameters (unused)
---@return table result
function M.unsubscribe_resources(rpc, params)
	log.debug("RPC", "resources/unsubscribe called", params)

	-- Mark that this client is unsubscribed
	if rpc.connection then
		rpc.connection.subscribed_to_resources = false
	end

	return {}
end

return M
