-- MCP Resources handlers with enhanced error handling and caching
-- Provides access to files, templates, snippets, and other resources via MCP

local resources = require("claude-code-ide.resources")
local log = require("claude-code-ide.log")
local cache = require("claude-code-ide.cache")

local M = {}

-- Configuration constants
local CONFIG = {
	MAX_RESOURCES_PER_PAGE = 100,
	DEFAULT_CACHE_TTL = 300, -- 5 minutes
	FILE_CACHE_TTL = 60, -- 1 minute for files
	TEMPLATE_CACHE_TTL = 1800, -- 30 minutes for templates/snippets
	MAX_URI_LENGTH = 1024,
}

-- Generate secure cache key
---@param operation string Operation name
---@param params table Parameters
---@return string cache_key
local function generate_cache_key(operation, params)
	local key_parts = { "resources", operation }

	-- Sort parameters for consistent keys
	local sorted_params = {}
	for k, v in pairs(params or {}) do
		table.insert(sorted_params, k .. "=" .. tostring(v))
	end
	table.sort(sorted_params)

	for _, part in ipairs(sorted_params) do
		table.insert(key_parts, part)
	end

	return table.concat(key_parts, ":")
end

-- Validate URI format
---@param uri string URI to validate
---@return boolean valid, string? error_message
local function validate_uri(uri)
	if type(uri) ~= "string" then
		return false, "URI must be a string"
	end

	if #uri == 0 then
		return false, "URI cannot be empty"
	end

	if #uri > CONFIG.MAX_URI_LENGTH then
		return false, "URI too long (max " .. CONFIG.MAX_URI_LENGTH .. " characters)"
	end

	-- Basic URI format validation
	if not uri:match("^%w+://") then
		return false, "URI must have a valid scheme"
	end

	return true, nil
end

-- Get appropriate cache TTL for resource type
---@param uri string Resource URI
---@return number ttl
local function get_cache_ttl(uri)
	if uri:match("^template://") or uri:match("^snippet://") then
		return CONFIG.TEMPLATE_CACHE_TTL
	elseif uri:match("^file://") then
		return CONFIG.FILE_CACHE_TTL
	else
		return CONFIG.DEFAULT_CACHE_TTL
	end
end

-- Get the resources cache with error handling
---@return table? cache_instance
local function get_cache()
	local ok, cache_instance = pcall(cache.caches.resources)
	if not ok then
		log.warn("Resources", "Failed to get cache instance", { error = cache_instance })
		return nil
	end
	return cache_instance
end

-- Validate pagination parameters
---@param params table Parameters to validate
---@return boolean valid, string? error_message
local function validate_pagination_params(params)
	if not params then
		return true, nil
	end

	if params.cursor then
		if type(params.cursor) ~= "string" then
			return false, "Cursor must be a string"
		end

		local cursor_num = tonumber(params.cursor)
		if not cursor_num or cursor_num < 1 then
			return false, "Cursor must be a positive number"
		end
	end

	return true, nil
end

-- List available resources with enhanced error handling
---@param rpc table RPC instance
---@param params table Parameters (can include cursor for pagination)
---@return table result
function M.list_resources(rpc, params)
	log.info("RESOURCES", "list_resources called", {
		params = params,
		has_resources_module = resources ~= nil,
	})

	-- Validate pagination parameters
	local valid, error_msg = validate_pagination_params(params)
	if not valid then
		error("Invalid pagination parameters: " .. error_msg)
	end

	-- Get all resources with error handling
	local ok, all_resources = pcall(resources.list)
	if not ok then
		log.error("Resources", "Failed to list resources", { error = all_resources })
		error("Failed to retrieve resources: " .. tostring(all_resources))
	end

	if not all_resources or type(all_resources) ~= "table" then
		log.warn("Resources", "Invalid resources list returned")
		all_resources = {}
	end

	-- Format for MCP protocol with validation
	local formatted_resources = {}
	for _, resource in ipairs(all_resources) do
		if resource and type(resource) == "table" and resource.uri then
			table.insert(formatted_resources, {
				uri = tostring(resource.uri),
				name = tostring(resource.name or ""),
				description = tostring(resource.description or ""),
				mimeType = tostring(resource.mimeType or ""),
				metadata = resource.metadata or {},
			})
		end
	end

	-- Handle pagination
	local result = {
		resources = formatted_resources,
	}

	-- Implement pagination if cursor is provided or if too many resources
	if #formatted_resources > CONFIG.MAX_RESOURCES_PER_PAGE or (params and params.cursor) then
		local start_idx = 1
		if params and params.cursor then
			start_idx = tonumber(params.cursor) or 1
		end

		result.resources = {}
		local end_idx = math.min(start_idx + CONFIG.MAX_RESOURCES_PER_PAGE - 1, #formatted_resources)

		for i = start_idx, end_idx do
			table.insert(result.resources, formatted_resources[i])
		end

		-- Add next cursor if there are more resources
		if end_idx < #formatted_resources then
			result.nextCursor = tostring(end_idx + 1)
		end
	end

	log.debug("Resources", "Returning resources", {
		total = #formatted_resources,
		returned = #result.resources,
		has_next = result.nextCursor ~= nil,
	})

	return result
end

-- Read a specific resource with enhanced caching and validation
---@param rpc table RPC instance
---@param params table Parameters with uri
---@return table result
function M.read_resource(rpc, params)
	log.debug("Resources", "read_resource called", params)

	-- Validate parameters
	if not params or type(params) ~= "table" then
		error("Parameters must be a table")
	end

	if not params.uri then
		error("Missing required parameter: uri")
	end

	-- Validate URI
	local valid, error_msg = validate_uri(params.uri)
	if not valid then
		error("Invalid URI: " .. error_msg)
	end

	-- Check cache first with secure key generation
	local cache_instance = get_cache()
	if cache_instance then
		local cache_key = generate_cache_key("read", { uri = params.uri })
		local cached, hit = cache_instance:get(cache_key)
		if hit then
			log.debug("Resources", "Resource served from cache", { uri = params.uri })
			return cached
		end
	end

	-- Read the resource with error handling
	local ok, result = pcall(resources.read, params.uri)
	if not ok then
		log.error("Resources", "Failed to read resource", {
			uri = params.uri,
			error = result,
		})
		error("Failed to read resource: " .. tostring(result))
	end

	if not result then
		error("Resource not found: " .. params.uri)
	end

	-- Validate result structure
	if type(result) ~= "table" then
		log.warn("Resources", "Invalid result structure from resource read", {
			uri = params.uri,
			type = type(result),
		})
		result = { contents = { type = "text", text = tostring(result) } }
	end

	-- Cache the result with appropriate TTL
	if cache_instance then
		local cache_key = generate_cache_key("read", { uri = params.uri })
		local ttl = get_cache_ttl(params.uri)

		local cache_ok, cache_err = pcall(cache_instance.set, cache_instance, cache_key, result, ttl)
		if not cache_ok then
			log.warn("Resources", "Failed to cache resource result", {
				uri = params.uri,
				error = cache_err,
			})
		end
	end

	log.debug("Resources", "Resource read successfully", { uri = params.uri })

	return result
end

-- Subscribe to resource updates (placeholder for future implementation)
---@param rpc table RPC instance
---@param params table Parameters (unused)
---@return table result
function M.subscribe_resources(rpc, params)
	log.debug("Resources", "subscribe_resources called", params)

	-- Validate RPC connection
	if not rpc or not rpc.connection then
		error("Invalid RPC connection")
	end

	-- Mark that this client is subscribed to resource updates
	rpc.connection.subscribed_to_resources = true

	log.debug("Resources", "Client subscribed to resource updates", {
		connection_id = rpc.connection.id,
	})

	return vim.empty_dict()
end

-- Unsubscribe from resource updates
---@param rpc table RPC instance
---@param params table Parameters (unused)
---@return table result
function M.unsubscribe_resources(rpc, params)
	log.debug("Resources", "unsubscribe_resources called", params)

	-- Validate RPC connection
	if not rpc or not rpc.connection then
		error("Invalid RPC connection")
	end

	-- Mark that this client is unsubscribed
	rpc.connection.subscribed_to_resources = false

	log.debug("Resources", "Client unsubscribed from resource updates", {
		connection_id = rpc.connection.id,
	})

	return vim.empty_dict()
end

return M
