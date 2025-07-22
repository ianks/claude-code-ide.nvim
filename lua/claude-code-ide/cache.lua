-- Cache system for claude-code-ide.nvim
-- Production-ready LRU cache with memory management, metrics, and automatic cleanup

local M = {}

-- Load dependencies with graceful fallbacks
local deps = {}
local function load_dependency(name, required)
	local ok, module = pcall(require, name)
	if ok then
		deps[name] = module
		return module
	elseif required then
		error(string.format("Critical dependency missing: %s", name))
	else
		return nil
	end
end

-- Optional dependencies
local log = load_dependency("claude-code-ide.log", false)
local events = load_dependency("claude-code-ide.events", false)

-- Configuration constants
local CONFIG = {
	DEFAULT_MAX_SIZE = 1000,
	DEFAULT_TTL_SECONDS = 300, -- 5 minutes
	DEFAULT_MEMORY_LIMIT = 50 * 1024 * 1024, -- 50MB
	CLEANUP_INTERVAL_MS = 60000, -- 1 minute
	STATS_EMIT_INTERVAL_MS = 300000, -- 5 minutes
	MAX_KEY_LENGTH = 512,
	MAX_VALUE_SIZE = 10 * 1024 * 1024, -- 10MB per entry
}

-- Cache entry structure with comprehensive metadata
---@class CacheEntry
---@field value any The cached value
---@field timestamp number When the entry was created (ms)
---@field access_count number Number of times accessed
---@field last_access number Last access timestamp (ms)
---@field ttl number? Time to live in seconds
---@field size number Estimated memory size in bytes
---@field key string The cache key
---@field metadata table? Additional metadata

-- Production-ready cache implementation with bounded resources
---@class Cache
---@field entries table<string, CacheEntry> Cache entries
---@field access_order table<number, string> LRU access order tracking
---@field max_size number Maximum number of entries
---@field default_ttl number Default TTL in seconds
---@field memory_limit number Maximum memory usage in bytes
---@field current_memory number Current estimated memory usage
---@field stats table Performance and usage statistics
---@field config table Cache configuration
---@field timers table Active timers for cleanup
local Cache = {}
Cache.__index = Cache

-- Safe logging wrapper
local function safe_log(level, component, message, data)
	if log and log[level] then
		local ok, err = pcall(log[level], log, component, message, data)
		if not ok then
			vim.notify(string.format("Cache logging error: %s", err), vim.log.levels.WARN)
		end
	end
end

-- Emit cache events safely
local function safe_emit(event, data)
	if events and events.emit then
		local ok, err = pcall(events.emit, event, data, { async = true })
		if not ok then
			safe_log("warn", "CACHE", "Event emission failed", { event = event, error = err })
		end
	end
end

-- Estimate memory size of a value
local function estimate_size(value)
	local value_type = type(value)

	if value_type == "nil" then
		return 0
	elseif value_type == "boolean" then
		return 1
	elseif value_type == "number" then
		return 8
	elseif value_type == "string" then
		return #value + 24 -- String overhead
	elseif value_type == "table" then
		local size = 40 -- Table overhead
		local count = 0
		for k, v in pairs(value) do
			size = size + estimate_size(k) + estimate_size(v) + 16 -- Entry overhead
			count = count + 1
			-- Limit deep scanning for performance
			if count > 1000 then
				size = size + 1000 * 32 -- Estimate remaining
				break
			end
		end
		return size
	else
		return 64 -- Estimated size for other types
	end
end

-- Validate cache key
local function validate_key(key)
	if type(key) ~= "string" then
		return false, "Key must be a string"
	end

	if #key == 0 then
		return false, "Key cannot be empty"
	end

	if #key > CONFIG.MAX_KEY_LENGTH then
		return false, string.format("Key too long (max %d characters)", CONFIG.MAX_KEY_LENGTH)
	end

	return true, nil
end

-- Create a new cache instance with comprehensive configuration
---@param config table? Configuration options
---@return Cache
function Cache.new(config)
	config = config or {}

	local self = setmetatable({}, Cache)

	-- Configuration with secure defaults
	self.config = vim.tbl_extend("force", {
		max_size = CONFIG.DEFAULT_MAX_SIZE,
		default_ttl = CONFIG.DEFAULT_TTL_SECONDS,
		memory_limit = CONFIG.DEFAULT_MEMORY_LIMIT,
		cleanup_interval = CONFIG.CLEANUP_INTERVAL_MS,
		stats_interval = CONFIG.STATS_EMIT_INTERVAL_MS,
		enable_metrics = true,
		enable_events = true,
	}, config)

	-- Validate configuration
	if self.config.max_size <= 0 then
		error("max_size must be positive")
	end

	if self.config.memory_limit <= 0 then
		error("memory_limit must be positive")
	end

	-- Initialize state
	self.entries = {}
	self.access_order = {}
	self.max_size = self.config.max_size
	self.default_ttl = self.config.default_ttl
	self.memory_limit = self.config.memory_limit
	self.current_memory = 0
	self.timers = {}

	-- Initialize comprehensive statistics
	self.stats = {
		hits = 0,
		misses = 0,
		sets = 0,
		evictions = 0,
		expirations = 0,
		memory_evictions = 0,
		errors = 0,
		cleanup_runs = 0,
		created_at = vim.loop.now(),
		last_cleanup = 0,
		last_stats_emit = 0,
	}

	-- Setup automatic cleanup
	self:_setup_cleanup()

	safe_log("debug", "CACHE", "Cache created", {
		max_size = self.max_size,
		memory_limit = self.memory_limit,
		default_ttl = self.default_ttl,
	})

	return self
end

-- Setup periodic cleanup and stats emission
function Cache:_setup_cleanup()
	-- Cleanup timer
	local cleanup_timer = vim.loop.new_timer()
	cleanup_timer:start(
		self.config.cleanup_interval,
		self.config.cleanup_interval,
		vim.schedule_wrap(function()
			self:cleanup()
		end)
	)
	self.timers.cleanup = cleanup_timer

	-- Stats emission timer
	if self.config.enable_metrics then
		local stats_timer = vim.loop.new_timer()
		stats_timer:start(
			self.config.stats_interval,
			self.config.stats_interval,
			vim.schedule_wrap(function()
				self:_emit_stats()
			end)
		)
		self.timers.stats = stats_timer
	end
end

-- Generate secure cache key with validation
---@param method string RPC method name
---@param params table? Method parameters
---@return string cache_key
function Cache:_generate_key(method, params)
	local key_valid, key_err = validate_key(method)
	if not key_valid then
		error("Invalid method name: " .. key_err)
	end

	if not params then
		return method
	end

	-- Create a sorted, deterministic representation of params
	local function serialize_sorted(tbl, depth)
		depth = depth or 0
		if depth > 10 then -- Prevent infinite recursion
			return "..."
		end

		local keys = {}
		for k in pairs(tbl) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)

		local parts = {}
		for _, k in ipairs(keys) do
			local v = tbl[k]
			local value_str
			if type(v) == "table" then
				value_str = serialize_sorted(v, depth + 1)
			else
				value_str = tostring(v)
			end
			table.insert(parts, tostring(k) .. "=" .. value_str)
		end

		return "{" .. table.concat(parts, ",") .. "}"
	end

	local serialized = serialize_sorted(params)

	-- Use SHA-256 hash for consistent, bounded key length
	local key = method .. ":" .. vim.fn.sha256(serialized)

	return key
end

-- Check if entry is expired
---@param entry CacheEntry
---@return boolean expired
function Cache:_is_expired(entry)
	if not entry.ttl then
		return false
	end

	local age_seconds = (vim.loop.now() - entry.timestamp) / 1000
	return age_seconds > entry.ttl
end

-- Update access order for LRU
function Cache:_update_access_order(key)
	-- Remove key from current position
	for i, k in ipairs(self.access_order) do
		if k == key then
			table.remove(self.access_order, i)
			break
		end
	end

	-- Add to end (most recently used)
	table.insert(self.access_order, key)
end

-- Evict least recently used entries to maintain size limits
function Cache:_evict_lru()
	local evicted_count = 0

	while #self.access_order > self.max_size do
		local lru_key = table.remove(self.access_order, 1)
		local entry = self.entries[lru_key]

		if entry then
			self.current_memory = self.current_memory - entry.size
			self.entries[lru_key] = nil
			self.stats.evictions = self.stats.evictions + 1
			evicted_count = evicted_count + 1

			safe_log("trace", "CACHE", "LRU eviction", { key = lru_key, size = entry.size })
		end
	end

	return evicted_count
end

-- Evict entries to stay within memory limit
function Cache:_evict_memory()
	local evicted_count = 0

	while self.current_memory > self.memory_limit and #self.access_order > 0 do
		local lru_key = table.remove(self.access_order, 1)
		local entry = self.entries[lru_key]

		if entry then
			self.current_memory = self.current_memory - entry.size
			self.entries[lru_key] = nil
			self.stats.memory_evictions = self.stats.memory_evictions + 1
			evicted_count = evicted_count + 1

			safe_log("trace", "CACHE", "Memory eviction", { key = lru_key, size = entry.size })
		end
	end

	return evicted_count
end

-- Set a value in the cache with comprehensive validation
---@param method string RPC method name
---@param params table? Method parameters
---@param value any Value to cache
---@param ttl number? Custom TTL in seconds
---@return boolean success
function Cache:set(method, params, value, ttl)
	local ok, result = pcall(function()
		local key = self:_generate_key(method, params)

		-- Estimate value size
		local value_size = estimate_size(value)

		-- Check if single value exceeds limits
		if value_size > CONFIG.MAX_VALUE_SIZE then
			safe_log("warn", "CACHE", "Value too large for cache", {
				key = key,
				size = value_size,
				limit = CONFIG.MAX_VALUE_SIZE,
			})
			return false
		end

		if value_size > self.memory_limit then
			safe_log("warn", "CACHE", "Value exceeds cache memory limit", {
				key = key,
				size = value_size,
				limit = self.memory_limit,
			})
			return false
		end

		-- Remove existing entry if present
		local existing = self.entries[key]
		if existing then
			self.current_memory = self.current_memory - existing.size
		end

		-- Create new entry with comprehensive metadata
		local entry = {
			value = value,
			timestamp = vim.loop.now(),
			access_count = 0,
			last_access = vim.loop.now(),
			ttl = ttl or self.default_ttl,
			size = value_size,
			key = key,
			metadata = {
				method = method,
				params_hash = params and vim.fn.sha256(vim.inspect(params)) or nil,
			},
		}

		-- Update memory usage
		self.current_memory = self.current_memory + value_size

		-- Store entry
		self.entries[key] = entry
		self:_update_access_order(key)

		-- Maintain size and memory limits
		self:_evict_lru()
		self:_evict_memory()

		-- Update statistics
		self.stats.sets = self.stats.sets + 1

		safe_log("trace", "CACHE", "Cache set", {
			key = key,
			size = value_size,
			ttl = entry.ttl,
			total_memory = self.current_memory,
		})

		if self.config.enable_events then
			safe_emit("CacheSet", { key = key, size = value_size })
		end

		return true
	end)

	if not ok then
		self.stats.errors = self.stats.errors + 1
		safe_log("error", "CACHE", "Cache set failed", { error = result })
		return false
	end

	return result
end

-- Get a value from the cache with hit/miss tracking
---@param method string RPC method name
---@param params table? Method parameters
---@return any value, boolean hit
function Cache:get(method, params)
	local ok, value, hit = pcall(function()
		local key = self:_generate_key(method, params)
		local entry = self.entries[key]

		if not entry then
			self.stats.misses = self.stats.misses + 1
			safe_log("trace", "CACHE", "Cache miss", { key = key })
			return nil, false
		end

		-- Check expiration
		if self:_is_expired(entry) then
			self.current_memory = self.current_memory - entry.size
			self.entries[key] = nil
			self.stats.expirations = self.stats.expirations + 1

			-- Remove from access order
			for i, k in ipairs(self.access_order) do
				if k == key then
					table.remove(self.access_order, i)
					break
				end
			end

			safe_log("trace", "CACHE", "Cache expiration", { key = key })
			if self.config.enable_events then
				safe_emit("CacheExpiration", { key = key })
			end

			return nil, false
		end

		-- Update access metadata
		entry.access_count = entry.access_count + 1
		entry.last_access = vim.loop.now()
		self:_update_access_order(key)

		self.stats.hits = self.stats.hits + 1

		safe_log("trace", "CACHE", "Cache hit", {
			key = key,
			access_count = entry.access_count,
		})

		if self.config.enable_events then
			safe_emit("CacheHit", { key = key, access_count = entry.access_count })
		end

		return entry.value, true
	end)

	if not ok then
		self.stats.errors = self.stats.errors + 1
		self.stats.misses = self.stats.misses + 1
		safe_log("error", "CACHE", "Cache get failed", { error = value })
		return nil, false
	end

	return value, hit
end

-- Invalidate cache entries with pattern matching
---@param pattern string? Pattern to match keys (nil = invalidate all)
---@return number invalidated_count
function Cache:invalidate(pattern)
	local invalidated = 0
	local keys_to_remove = {}

	if not pattern then
		-- Invalidate all
		for key, entry in pairs(self.entries) do
			self.current_memory = self.current_memory - entry.size
			table.insert(keys_to_remove, key)
		end
		self.entries = {}
		self.access_order = {}
		invalidated = #keys_to_remove
	else
		-- Pattern-based invalidation
		for key, entry in pairs(self.entries) do
			if key:match(pattern) then
				self.current_memory = self.current_memory - entry.size
				table.insert(keys_to_remove, key)
			end
		end

		-- Remove entries and from access order
		for _, key in ipairs(keys_to_remove) do
			self.entries[key] = nil
			for i, k in ipairs(self.access_order) do
				if k == key then
					table.remove(self.access_order, i)
					break
				end
			end
		end
		invalidated = #keys_to_remove
	end

	safe_log("debug", "CACHE", "Cache invalidation", {
		pattern = pattern or "all",
		invalidated = invalidated,
		memory_freed = 0, -- We already updated current_memory
	})

	if self.config.enable_events then
		safe_emit("CacheInvalidation", { pattern = pattern, count = invalidated })
	end

	return invalidated
end

-- Comprehensive cleanup of expired entries
---@return number cleaned_count
function Cache:cleanup()
	local cleaned = 0
	local memory_freed = 0
	local keys_to_remove = {}

	-- Find expired entries
	for key, entry in pairs(self.entries) do
		if self:_is_expired(entry) then
			memory_freed = memory_freed + entry.size
			table.insert(keys_to_remove, key)
		end
	end

	-- Remove expired entries
	for _, key in ipairs(keys_to_remove) do
		self.entries[key] = nil
		for i, k in ipairs(self.access_order) do
			if k == key then
				table.remove(self.access_order, i)
				break
			end
		end
		cleaned = cleaned + 1
	end

	self.current_memory = self.current_memory - memory_freed
	self.stats.expirations = self.stats.expirations + cleaned
	self.stats.cleanup_runs = self.stats.cleanup_runs + 1
	self.stats.last_cleanup = vim.loop.now()

	safe_log("debug", "CACHE", "Cache cleanup completed", {
		cleaned = cleaned,
		memory_freed = memory_freed,
		total_entries = vim.tbl_count(self.entries),
		memory_usage = self.current_memory,
	})

	if self.config.enable_events then
		safe_emit("CacheCleanup", { cleaned = cleaned, memory_freed = memory_freed })
	end

	return cleaned
end

-- Get comprehensive cache statistics
---@return table stats
function Cache:stats()
	local total_requests = self.stats.hits + self.stats.misses
	local hit_rate = total_requests > 0 and (self.stats.hits / total_requests) or 0

	return vim.tbl_extend("force", vim.deepcopy(self.stats), {
		total_entries = vim.tbl_count(self.entries),
		memory_usage = self.current_memory,
		memory_limit = self.memory_limit,
		memory_utilization = self.memory_limit > 0 and (self.current_memory / self.memory_limit) or 0,
		hit_rate = hit_rate,
		size_utilization = self.max_size > 0 and (vim.tbl_count(self.entries) / self.max_size) or 0,
		uptime_ms = vim.loop.now() - self.stats.created_at,
	})
end

-- Emit statistics for monitoring
function Cache:_emit_stats()
	if not self.config.enable_events then
		return
	end

	local stats = self:stats()
	safe_emit("CacheStats", stats)
	self.stats.last_stats_emit = vim.loop.now()
end

-- Shutdown cache and cleanup resources
function Cache:shutdown()
	-- Stop all timers
	for name, timer in pairs(self.timers) do
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end

	-- Clear all entries
	self:invalidate()

	safe_log("info", "CACHE", "Cache shutdown", {
		final_stats = self:stats(),
	})
end

-- Health check for cache
function Cache:health_check()
	local stats = self:stats()
	local healthy = true
	local issues = {}

	-- Check error rate
	if stats.total_entries > 0 and (stats.errors / stats.total_entries) > 0.1 then
		healthy = false
		table.insert(issues, "High error rate")
	end

	-- Check memory usage
	if stats.memory_utilization > 0.9 then
		table.insert(issues, "High memory usage")
	end

	-- Check hit rate
	if stats.hit_rate < 0.1 and stats.total_entries > 100 then
		table.insert(issues, "Low hit rate")
	end

	return {
		healthy = healthy,
		issues = issues,
		stats = stats,
	}
end

-- Named cache instances for different use cases
local cache_instances = {}

-- Get or create a named cache instance
---@param name string Cache name
---@param config table? Configuration for the cache
---@return Cache
function M.get_cache(name, config)
	if not cache_instances[name] then
		cache_instances[name] = Cache.new(config)
		safe_log("debug", "CACHE", "Named cache created", { name = name })
	end
	return cache_instances[name]
end

-- Shutdown all cache instances
function M.shutdown_all()
	for name, cache in pairs(cache_instances) do
		cache:shutdown()
	end
	cache_instances = {}
end

-- Health check for all caches
function M.health_check()
	local all_healthy = true
	local cache_health = {}

	for name, cache in pairs(cache_instances) do
		local health = cache:health_check()
		cache_health[name] = health
		if not health.healthy then
			all_healthy = false
		end
	end

	return {
		healthy = all_healthy,
		caches = cache_health,
		total_caches = vim.tbl_count(cache_instances),
	}
end

-- Export the Cache class for direct usage
M.Cache = Cache

return M
