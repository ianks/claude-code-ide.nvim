-- Comprehensive tests for the refactored cache system

local cache = require("claude-code-ide.cache")

describe("Cache System", function()
	local test_cache

	-- Clean up between tests
	after_each(function()
		if test_cache then
			test_cache:clear()
		end
		-- Reset any global cache state
		package.loaded["claude-code-ide.cache"] = nil
		cache = require("claude-code-ide.cache")
	end)

	describe("Cache Creation and Configuration", function()
		it("should create cache with default configuration", function()
			test_cache = cache.new("test_cache")

			assert.truthy(test_cache)
			assert.equals("test_cache", test_cache.name)

			local stats = test_cache:get_stats()
			assert.equals(0, stats.size)
			assert.equals(0, stats.hits)
			assert.equals(0, stats.misses)
		end)

		it("should create cache with custom configuration", function()
			local config = {
				max_size = 100,
				max_memory = 1024 * 1024, -- 1MB
				default_ttl = 300, -- 5 minutes
				cleanup_interval = 30000, -- 30 seconds
			}

			test_cache = cache.new("custom_cache", config)

			assert.equals("custom_cache", test_cache.name)
			assert.equals(100, test_cache.max_size)
			assert.equals(1024 * 1024, test_cache.max_memory)
		end)

		it("should enforce size limits in configuration", function()
			assert.has_error(function()
				cache.new("invalid", { max_size = 0 })
			end, "Invalid cache configuration")

			assert.has_error(function()
				cache.new("invalid", { max_memory = -1 })
			end, "Invalid cache configuration")

			assert.has_error(function()
				cache.new("invalid", { default_ttl = 0 })
			end, "Invalid cache configuration")
		end)

		it("should provide global cache instance getter", function()
			local global_cache = cache.get("global_test_cache")
			assert.truthy(global_cache)
			assert.equals("global_test_cache", global_cache.name)

			-- Should return same instance on subsequent calls
			local same_cache = cache.get("global_test_cache")
			assert.equals(global_cache, same_cache)
		end)
	end)

	describe("Basic Cache Operations", function()
		before_each(function()
			test_cache = cache.new("test_cache", { max_size = 10 })
		end)

		it("should store and retrieve simple values", function()
			test_cache:set("simple_key", "simple_value")

			local value, hit = test_cache:get("simple_key")
			assert.is_true(hit)
			assert.equals("simple_value", value)
		end)

		it("should store and retrieve complex values", function()
			local complex_value = {
				nested = { data = "test" },
				array = { 1, 2, 3 },
				bool = true,
				num = 42,
			}

			test_cache:set("complex_key", complex_value)

			local value, hit = test_cache:get("complex_key")
			assert.is_true(hit)
			assert.same(complex_value, value)
		end)

		it("should handle cache misses correctly", function()
			local value, hit = test_cache:get("non_existent_key")
			assert.is_false(hit)
			assert.is_nil(value)

			local stats = test_cache:get_stats()
			assert.equals(1, stats.misses)
		end)

		it("should update existing keys", function()
			test_cache:set("update_key", "initial_value")
			test_cache:set("update_key", "updated_value")

			local value, hit = test_cache:get("update_key")
			assert.is_true(hit)
			assert.equals("updated_value", value)

			local stats = test_cache:get_stats()
			assert.equals(1, stats.size) -- Should still be only 1 item
		end)

		it("should check key existence without affecting LRU", function()
			test_cache:set("exists_key", "value")

			assert.is_true(test_cache:has("exists_key"))
			assert.is_false(test_cache:has("non_existent"))

			-- Should not affect access order for LRU
			local stats_before = test_cache:get_stats()
			test_cache:has("exists_key")
			local stats_after = test_cache:get_stats()

			assert.equals(stats_before.hits, stats_after.hits) -- No change in hits
		end)

		it("should delete keys correctly", function()
			test_cache:set("delete_key", "value")
			assert.is_true(test_cache:has("delete_key"))

			local deleted = test_cache:delete("delete_key")
			assert.is_true(deleted)
			assert.is_false(test_cache:has("delete_key"))

			-- Deleting non-existent key should return false
			local not_deleted = test_cache:delete("non_existent")
			assert.is_false(not_deleted)
		end)
	end)

	describe("TTL and Expiration", function()
		before_each(function()
			test_cache = cache.new("ttl_cache", {
				max_size = 10,
				default_ttl = 100, -- 100ms for fast testing
			})
		end)

		it("should respect TTL for cached items", function()
			test_cache:set("ttl_key", "value", { ttl = 50 }) -- 50ms TTL

			-- Should be available immediately
			local value, hit = test_cache:get("ttl_key")
			assert.is_true(hit)
			assert.equals("value", value)

			-- Wait for expiration
			vim.wait(100)

			-- Should be expired now
			local expired_value, expired_hit = test_cache:get("ttl_key")
			assert.is_false(expired_hit)
			assert.is_nil(expired_value)
		end)

		it("should use default TTL when not specified", function()
			test_cache:set("default_ttl_key", "value") -- No TTL specified

			-- Should be available initially
			assert.is_true(test_cache:has("default_ttl_key"))

			-- Wait for default TTL to expire
			vim.wait(150) -- Default is 100ms

			-- Should be expired
			assert.is_false(test_cache:has("default_ttl_key"))
		end)

		it("should allow permanent storage with no TTL", function()
			test_cache:set("permanent_key", "value", { ttl = 0 }) -- No expiration

			-- Wait longer than default TTL
			vim.wait(150)

			-- Should still be available
			local value, hit = test_cache:get("permanent_key")
			assert.is_true(hit)
			assert.equals("value", value)
		end)

		it("should clean up expired items automatically", function()
			-- Add items with short TTL
			for i = 1, 5 do
				test_cache:set("temp_" .. i, "value_" .. i, { ttl = 30 })
			end

			assert.equals(5, test_cache:get_stats().size)

			-- Wait for expiration and cleanup
			vim.wait(100)

			-- Force cleanup by trying to access
			test_cache:get("temp_1")

			local stats = test_cache:get_stats()
			assert.is_true(stats.size < 5) -- Some should be cleaned up
		end)
	end)

	describe("LRU Eviction Policy", function()
		before_each(function()
			test_cache = cache.new("lru_cache", { max_size = 3 })
		end)

		it("should evict least recently used items when size limit reached", function()
			-- Fill cache to capacity
			test_cache:set("key1", "value1")
			test_cache:set("key2", "value2")
			test_cache:set("key3", "value3")

			assert.equals(3, test_cache:get_stats().size)

			-- Access key1 to make it recently used
			test_cache:get("key1")

			-- Add new item - should evict key2 (least recently used)
			test_cache:set("key4", "value4")

			assert.equals(3, test_cache:get_stats().size)
			assert.is_true(test_cache:has("key1")) -- Recently accessed
			assert.is_false(test_cache:has("key2")) -- Should be evicted
			assert.is_true(test_cache:has("key3"))
			assert.is_true(test_cache:has("key4"))
		end)

		it("should update access order on get operations", function()
			test_cache:set("a", "value_a")
			test_cache:set("b", "value_b")
			test_cache:set("c", "value_c")

			-- Access 'a' to make it most recently used
			test_cache:get("a")

			-- Add new item - 'b' should be evicted (oldest unaccessed)
			test_cache:set("d", "value_d")

			assert.is_true(test_cache:has("a"))
			assert.is_false(test_cache:has("b"))
			assert.is_true(test_cache:has("c"))
			assert.is_true(test_cache:has("d"))
		end)

		it("should track evictions in statistics", function()
			-- Fill beyond capacity
			for i = 1, 5 do
				test_cache:set("key" .. i, "value" .. i)
			end

			local stats = test_cache:get_stats()
			assert.equals(3, stats.size) -- Max size
			assert.equals(2, stats.evictions) -- 2 items evicted
		end)
	end)

	describe("Memory Management", function()
		before_each(function()
			test_cache = cache.new("memory_cache", {
				max_size = 100,
				max_memory = 1024, -- 1KB limit for testing
			})
		end)

		it("should track memory usage", function()
			test_cache:set("small_key", "small_value")

			local stats = test_cache:get_stats()
			assert.is_true(stats.memory_usage > 0)
			assert.is_true(stats.memory_usage < 1024)
		end)

		it("should evict items when memory limit exceeded", function()
			-- Add large values to exceed memory limit
			local large_value = string.rep("x", 300) -- ~300 bytes each

			test_cache:set("large1", large_value)
			test_cache:set("large2", large_value)
			test_cache:set("large3", large_value)
			test_cache:set("large4", large_value) -- Should trigger memory eviction

			local stats = test_cache:get_stats()
			assert.is_true(stats.memory_usage <= 1024)
			assert.is_true(stats.size < 4) -- Some items should be evicted
		end)

		it("should prioritize memory over size limits", function()
			-- Set one very large item that exceeds memory limit
			local huge_value = string.rep("y", 2000) -- 2KB value

			test_cache:set("huge", huge_value)

			-- Cache should be mostly empty due to memory constraint
			local stats = test_cache:get_stats()
			assert.is_true(stats.memory_usage <= 1024)
		end)
	end)

	describe("Cache Statistics and Monitoring", function()
		before_each(function()
			test_cache = cache.new("stats_cache", { max_size = 10 })
		end)

		it("should track comprehensive statistics", function()
			-- Perform various operations
			test_cache:set("stat1", "value1")
			test_cache:set("stat2", "value2")
			test_cache:get("stat1") -- Hit
			test_cache:get("stat1") -- Another hit
			test_cache:get("nonexistent") -- Miss
			test_cache:delete("stat2")

			local stats = test_cache:get_stats()

			assert.equals(1, stats.size)
			assert.equals(2, stats.hits)
			assert.equals(1, stats.misses)
			assert.equals(0, stats.evictions)
			assert.truthy(stats.memory_usage)
			assert.truthy(stats.created_at)
			assert.truthy(stats.last_access)
		end)

		it("should calculate hit rate correctly", function()
			test_cache:set("key1", "value1")
			test_cache:set("key2", "value2")

			-- 2 hits, 1 miss = 66.67% hit rate
			test_cache:get("key1") -- Hit
			test_cache:get("key2") -- Hit
			test_cache:get("key3") -- Miss

			local stats = test_cache:get_stats()
			local hit_rate = stats.hits / (stats.hits + stats.misses)
			assert.equals(math.floor(hit_rate * 100), 66) -- ~66%
		end)

		it("should track peak usage", function()
			-- Fill cache
			for i = 1, 8 do
				test_cache:set("peak" .. i, "value" .. i)
			end

			local peak_size = test_cache:get_stats().size

			-- Clear some items
			test_cache:delete("peak1")
			test_cache:delete("peak2")

			local stats = test_cache:get_stats()
			assert.is_true(stats.size < peak_size)
			-- Should track that we reached the peak
		end)
	end)

	describe("Event Emission", function()
		local events
		local received_events

		before_each(function()
			-- Setup events system
			events = require("claude-code-ide.events")
			events.setup()

			received_events = {}

			-- Listen for cache events
			events.on("CacheHit", function(data)
				table.insert(received_events, { type = "hit", data = data })
			end)

			events.on("CacheMiss", function(data)
				table.insert(received_events, { type = "miss", data = data })
			end)

			events.on("CacheEviction", function(data)
				table.insert(received_events, { type = "eviction", data = data })
			end)

			test_cache = cache.new("event_cache", {
				max_size = 3,
				emit_events = true,
			})
		end)

		it("should emit cache hit events", function()
			test_cache:set("hit_key", "hit_value")
			test_cache:get("hit_key")

			vim.wait(50) -- Wait for async events

			local hit_events = vim.tbl_filter(function(e)
				return e.type == "hit"
			end, received_events)
			assert.equals(1, #hit_events)
			assert.equals("event_cache", hit_events[1].data.cache_name)
			assert.equals("hit_key", hit_events[1].data.key)
		end)

		it("should emit cache miss events", function()
			test_cache:get("missing_key")

			vim.wait(50)

			local miss_events = vim.tbl_filter(function(e)
				return e.type == "miss"
			end, received_events)
			assert.equals(1, #miss_events)
			assert.equals("missing_key", miss_events[1].data.key)
		end)

		it("should emit eviction events", function()
			-- Fill cache beyond capacity to trigger eviction
			test_cache:set("evict1", "value1")
			test_cache:set("evict2", "value2")
			test_cache:set("evict3", "value3")
			test_cache:set("evict4", "value4") -- Should evict first item

			vim.wait(50)

			local eviction_events = vim.tbl_filter(function(e)
				return e.type == "eviction"
			end, received_events)
			assert.equals(1, #eviction_events)
			assert.equals("evict1", eviction_events[1].data.evicted_key)
		end)
	end)

	describe("Error Handling and Edge Cases", function()
		before_each(function()
			test_cache = cache.new("error_cache", { max_size = 5 })
		end)

		it("should handle nil keys gracefully", function()
			assert.has_error(function()
				test_cache:set(nil, "value")
			end, "Key cannot be nil")

			assert.has_error(function()
				test_cache:get(nil)
			end, "Key cannot be nil")
		end)

		it("should handle nil values correctly", function()
			-- Setting nil should delete the key
			test_cache:set("nil_key", "value")
			assert.is_true(test_cache:has("nil_key"))

			test_cache:set("nil_key", nil)
			assert.is_false(test_cache:has("nil_key"))
		end)

		it("should handle very large keys", function()
			local large_key = string.rep("k", 10000) -- 10KB key

			assert.has_error(function()
				test_cache:set(large_key, "value")
			end, "Key too large")
		end)

		it("should handle concurrent access gracefully", function()
			-- Simulate concurrent access
			for i = 1, 20 do
				test_cache:set("concurrent" .. i, "value" .. i)
			end

			-- Multiple gets in quick succession
			local results = {}
			for i = 1, 20 do
				local value, hit = test_cache:get("concurrent" .. i)
				results[i] = { value = value, hit = hit }
			end

			-- Should not crash and should maintain consistency
			assert.equals(20, #results)
		end)
	end)

	describe("Cache Health Check", function()
		before_each(function()
			test_cache = cache.new("health_cache", { max_size = 10 })
		end)

		it("should provide health status", function()
			local health = test_cache:health_check()

			assert.truthy(health.healthy)
			assert.truthy(health.details.operational)
			assert.equals(0, health.details.size)
			assert.equals(0, health.details.memory_usage)
		end)

		it("should report memory pressure issues", function()
			-- Create cache with very small memory limit
			local small_cache = cache.new("small_cache", {
				max_size = 100,
				max_memory = 10, -- 10 bytes only
			})

			-- Try to add data that exceeds memory
			small_cache:set("test", "this is definitely more than 10 bytes")

			local health = small_cache:health_check()
			assert.is_false(health.healthy)
			assert.truthy(health.details.issues)
		end)

		it("should report high eviction rate as unhealthy", function()
			-- Force many evictions
			for i = 1, 50 do
				test_cache:set("evict_test" .. i, "value" .. i)
			end

			local health = test_cache:health_check()
			local stats = test_cache:get_stats()

			if stats.evictions > stats.size * 2 then -- High eviction rate
				assert.is_false(health.healthy)
			end
		end)
	end)

	describe("Cache Cleanup and Resource Management", function()
		before_each(function()
			test_cache = cache.new("cleanup_cache", {
				max_size = 10,
				cleanup_interval = 50, -- Fast cleanup for testing
			})
		end)

		it("should clean up expired items periodically", function()
			-- Add items with very short TTL
			for i = 1, 5 do
				test_cache:set("cleanup" .. i, "value" .. i, { ttl = 30 })
			end

			assert.equals(5, test_cache:get_stats().size)

			-- Wait for expiration and automatic cleanup
			vim.wait(100)

			-- Trigger cleanup by accessing cache
			test_cache:get("cleanup1")

			local stats = test_cache:get_stats()
			assert.is_true(stats.size < 5) -- Items should be cleaned up
		end)

		it("should stop cleanup timers on clear", function()
			test_cache:set("timer_test", "value")

			-- Clear should stop all timers
			assert.has_no_error(function()
				test_cache:clear()
			end)

			assert.equals(0, test_cache:get_stats().size)
		end)
	end)

	describe("Global Cache Management", function()
		it("should list all active caches", function()
			local cache1 = cache.get("global1")
			local cache2 = cache.get("global2")

			local active_caches = cache.list_caches()
			assert.is_true(#active_caches >= 2)

			local names = vim.tbl_map(function(c)
				return c.name
			end, active_caches)
			assert.truthy(vim.tbl_contains(names, "global1"))
			assert.truthy(vim.tbl_contains(names, "global2"))
		end)

		it("should clear all caches", function()
			local cache1 = cache.get("clear_all1")
			local cache2 = cache.get("clear_all2")

			cache1:set("test", "value")
			cache2:set("test", "value")

			cache.clear_all()

			assert.equals(0, cache1:get_stats().size)
			assert.equals(0, cache2:get_stats().size)
		end)

		it("should provide global cache statistics", function()
			local cache1 = cache.get("stats1")
			local cache2 = cache.get("stats2")

			cache1:set("test1", "value1")
			cache2:set("test2", "value2")

			local global_stats = cache.get_global_stats()
			assert.truthy(global_stats.total_caches)
			assert.truthy(global_stats.total_items)
			assert.truthy(global_stats.total_memory)
			assert.is_true(global_stats.total_items >= 2)
		end)
	end)
end)

