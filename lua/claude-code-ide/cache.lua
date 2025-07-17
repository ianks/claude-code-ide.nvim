-- Cache system for claude-code-ide.nvim
-- Provides LRU caching for MCP responses to improve performance

local log = require("claude-code-ide.log")
local notify = require("claude-code-ide.ui.notify")

local M = {}

-- Cache entry structure
---@class CacheEntry
---@field value any The cached value
---@field timestamp number When the entry was created
---@field access_count number Number of times accessed
---@field last_access number Last access timestamp
---@field ttl number? Time to live in seconds

-- Cache implementation
---@class Cache
---@field entries table<string, CacheEntry> Cache entries
---@field max_size number Maximum number of entries
---@field default_ttl number Default TTL in seconds
---@field access_list table<number, string> Access order tracking
local Cache = {}
Cache.__index = Cache

-- Create a new cache instance
---@param config table? Configuration options
---@return Cache
function Cache.new(config)
	config = config or {}
	local self = setmetatable({}, Cache)

	self.entries = {}
	self.max_size = config.max_size or 100
	self.default_ttl = config.default_ttl or 300 -- 5 minutes default
	self.access_list = {}

	return self
end

-- Generate cache key
---@param method string RPC method name
---@param params table? Method parameters
---@return string
function Cache:_generate_key(method, params)
	if not params then
		return method
	end

	-- Sort params for consistent key generation
	-- Create a sorted representation of params
	local function serialize_sorted(tbl)
		local keys = {}
		for k in pairs(tbl) do
			table.insert(keys, k)
		end
		table.sort(keys)

		local parts = {}
		for _, k in ipairs(keys) do
			local v = tbl[k]
			if type(v) == "table" then
				table.insert(parts, k .. "=" .. serialize_sorted(v))
			else
				table.insert(parts, k .. "=" .. tostring(v))
			end
		end

		return "{" .. table.concat(parts, ",") .. "}"
	end

	local sorted = serialize_sorted(params)
	return method .. ":" .. vim.fn.sha256(sorted)
end

-- Check if entry is expired
---@param entry CacheEntry
---@return boolean
function Cache:_is_expired(entry)
	if not entry.ttl then
		return false
	end

	local age = os.time() - entry.timestamp
	return age > entry.ttl
end

-- Evict least recently used entries
function Cache:_evict_lru()
	-- Check if we need to evict (we're at or over capacity)
	while vim.tbl_count(self.entries) >= self.max_size do
		-- Find LRU entry
		local lru_key = nil
		local lru_time = nil

		for key, entry in pairs(self.entries) do
			if not lru_time or entry.last_access < lru_time then
				lru_time = entry.last_access
				lru_key = key
			end
		end

		if lru_key then
			self.entries[lru_key] = nil
			log.trace("CACHE", "Evicted LRU entry", { key = lru_key })
		else
			-- Safety: prevent infinite loop
			break
		end
	end
end

-- Get value from cache
---@param method string RPC method name
---@param params table? Method parameters
---@return any? value, boolean hit
function Cache:get(method, params)
	local key = self:_generate_key(method, params)
	local entry = self.entries[key]

	if not entry then
		log.trace("CACHE", "Cache miss", { method = method })
		return nil, false
	end

	-- Check if expired
	if self:_is_expired(entry) then
		self.entries[key] = nil
		log.trace("CACHE", "Cache entry expired", { method = method })
		return nil, false
	end

	-- Update access info
	entry.access_count = entry.access_count + 1
	entry.last_access = os.time()

	log.trace("CACHE", "Cache hit", {
		method = method,
		access_count = entry.access_count,
	})

	return entry.value, true
end

-- Set value in cache
---@param method string RPC method name
---@param params table? Method parameters
---@param value any Value to cache
---@param ttl number? Time to live in seconds
function Cache:set(method, params, value, ttl)
	local key = self:_generate_key(method, params)

	-- Evict if needed
	self:_evict_lru()

	-- Create entry
	self.entries[key] = {
		value = value,
		timestamp = os.time(),
		access_count = 0,
		last_access = os.time(),
		ttl = ttl or self.default_ttl,
	}

	log.trace("CACHE", "Cached value", {
		method = method,
		ttl = ttl or self.default_ttl,
	})
end

-- Invalidate cache entries
---@param pattern string? Pattern to match methods (nil = all)
function Cache:invalidate(pattern)
	if not pattern then
		self.entries = {}
		log.debug("CACHE", "Invalidated all entries")
		return
	end

	local count = 0
	for key, _ in pairs(self.entries) do
		local method = key:match("^([^:]+)")
		if method and method:match(pattern) then
			self.entries[key] = nil
			count = count + 1
		end
	end

	log.debug("CACHE", "Invalidated entries", {
		pattern = pattern,
		count = count,
	})
end

-- Get cache statistics
---@return table
function Cache:stats()
	local total = vim.tbl_count(self.entries)
	local expired = 0
	local total_size = 0
	local total_hits = 0

	for _, entry in pairs(self.entries) do
		if self:_is_expired(entry) then
			expired = expired + 1
		end
		total_hits = total_hits + entry.access_count

		-- Estimate size (very rough)
		local ok, encoded = pcall(vim.json.encode, entry.value)
		if ok then
			total_size = total_size + #encoded
		end
	end

	return {
		total_entries = total,
		expired_entries = expired,
		total_hits = total_hits,
		estimated_size = total_size,
		max_size = self.max_size,
	}
end

-- Clear expired entries
function Cache:cleanup()
	local count = 0
	for key, entry in pairs(self.entries) do
		if self:_is_expired(entry) then
			self.entries[key] = nil
			count = count + 1
		end
	end

	if count > 0 then
		log.debug("CACHE", "Cleaned up expired entries", { count = count })
	end
end

-- Module-level cache instances
local caches = {}

-- Get or create a cache instance
---@param name string Cache name
---@param config table? Configuration
---@return Cache
function M.get_cache(name, config)
	if not caches[name] then
		caches[name] = Cache.new(config)
	end
	return caches[name]
end

-- Default caches with specific configurations
M.caches = {
	-- Tool responses cache (short TTL)
	tools = function()
		return M.get_cache("tools", {
			max_size = 50,
			default_ttl = 60, -- 1 minute
		})
	end,

	-- Resources cache (longer TTL)
	resources = function()
		return M.get_cache("resources", {
			max_size = 200,
			default_ttl = 600, -- 10 minutes
		})
	end,

	-- File content cache
	files = function()
		return M.get_cache("files", {
			max_size = 100,
			default_ttl = 300, -- 5 minutes
		})
	end,

	-- General RPC responses
	rpc = function()
		return M.get_cache("rpc", {
			max_size = 100,
			default_ttl = 120, -- 2 minutes
		})
	end,
}

-- Setup periodic cleanup
local cleanup_timer = nil

function M.setup()
	-- Stop existing timer if any
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer:close()
	end

	-- Create periodic cleanup timer (every 5 minutes)
	cleanup_timer = vim.loop.new_timer()
	cleanup_timer:start(300000, 300000, function()
		vim.schedule(function()
			for name, cache in pairs(caches) do
				cache:cleanup()
			end
		end)
	end)

	log.debug("CACHE", "Cache system initialized")
end

-- Shutdown cleanup
function M.shutdown()
	if cleanup_timer then
		cleanup_timer:stop()
		cleanup_timer:close()
		cleanup_timer = nil
	end

	-- Clear all caches
	caches = {}
end

-- Invalidate all caches
function M.invalidate_all()
	for _, cache in pairs(caches) do
		cache:invalidate()
	end
end

-- Get statistics for all caches
function M.get_all_stats()
	local stats = {}
	for name, cache in pairs(caches) do
		stats[name] = cache:stats()
	end
	return stats
end

return M
