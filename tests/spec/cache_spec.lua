-- Tests for cache system

local cache = require("claude-code.cache")

describe("Cache System", function()
	local test_cache

	before_each(function()
		-- Create a fresh cache instance for each test
		test_cache = cache.get_cache("test", {
			max_size = 5,
			default_ttl = 60,
		})

		-- Clear the cache
		test_cache:invalidate()
	end)

	describe("Basic Operations", function()
		it("should store and retrieve values", function()
			test_cache:set("test_method", { param = "value" }, { result = "data" })

			local value, hit = test_cache:get("test_method", { param = "value" })
			assert.is_true(hit)
			assert.same({ result = "data" }, value)
		end)

		it("should return cache miss for non-existent keys", function()
			local value, hit = test_cache:get("non_existent", {})
			assert.is_false(hit)
			assert.is_nil(value)
		end)

		it("should generate consistent keys for same params", function()
			local key1 = test_cache:_generate_key("method", { b = 2, a = 1 })
			local key2 = test_cache:_generate_key("method", { a = 1, b = 2 })

			-- Keys should be the same regardless of param order due to JSON sorting
			assert.equals(key1, key2)
		end)

		it("should generate different keys for different params", function()
			local key1 = test_cache:_generate_key("method", { a = 1 })
			local key2 = test_cache:_generate_key("method", { a = 2 })

			assert.not_equals(key1, key2)
		end)
	end)

	describe("TTL and Expiration", function()
		it("should respect TTL", function()
			-- Mock time functions
			local current_time = os.time()
			local original_time = os.time
			os.time = function()
				return current_time
			end

			-- Set with 10 second TTL
			test_cache:set("expire_test", {}, "value", 10)

			-- Should be valid immediately
			local value, hit = test_cache:get("expire_test", {})
			assert.is_true(hit)
			assert.equals("value", value)

			-- Advance time by 11 seconds
			current_time = current_time + 11

			-- Should be expired
			value, hit = test_cache:get("expire_test", {})
			assert.is_false(hit)
			assert.is_nil(value)

			-- Restore
			os.time = original_time
		end)

		it("should use default TTL when not specified", function()
			test_cache:set("default_ttl", {}, "value")

			local entry = test_cache.entries[test_cache:_generate_key("default_ttl", {})]
			assert.equals(60, entry.ttl) -- Default TTL from our test config
		end)

		it("should handle entries without TTL", function()
			-- Directly set entry without TTL
			local key = test_cache:_generate_key("no_ttl", {})
			test_cache.entries[key] = {
				value = "eternal",
				timestamp = os.time(),
				access_count = 0,
				last_access = os.time(),
				ttl = nil,
			}

			-- Should never expire
			local value, hit = test_cache:get("no_ttl", {})
			assert.is_true(hit)
			assert.equals("eternal", value)
		end)
	end)

	describe("LRU Eviction", function()
		it("should evict least recently used entries", function()
			-- Mock time to ensure different access times
			local current_time = os.time()
			local original_time = os.time
			os.time = function()
				return current_time
			end

			-- Fill cache to capacity with different timestamps
			for i = 1, 5 do
				test_cache:set("method", { id = i }, "value" .. i)
				current_time = current_time + 1
			end

			-- Access some entries to update their last access time
			current_time = current_time + 10
			test_cache:get("method", { id = 2 })
			current_time = current_time + 1
			test_cache:get("method", { id = 4 })

			-- Add one more entry to trigger eviction
			current_time = current_time + 1
			test_cache:set("method", { id = 6 }, "value6")

			-- Entry 1, 3, or 5 should have been evicted (not 2 or 4)
			local stats = test_cache:stats()
			assert.equals(5, stats.total_entries)

			-- Entries 2 and 4 should still be there
			local _, hit2 = test_cache:get("method", { id = 2 })
			local _, hit4 = test_cache:get("method", { id = 4 })
			assert.is_true(hit2)
			assert.is_true(hit4)

			-- Entry 6 should be there
			local _, hit6 = test_cache:get("method", { id = 6 })
			assert.is_true(hit6)

			-- Restore
			os.time = original_time
		end)
	end)

	describe("Invalidation", function()
		it("should invalidate all entries", function()
			test_cache:set("method1", {}, "value1")
			test_cache:set("method2", {}, "value2")

			test_cache:invalidate()

			local stats = test_cache:stats()
			assert.equals(0, stats.total_entries)
		end)

		it("should invalidate by pattern", function()
			test_cache:set("tools/call:openFile", {}, "value1")
			test_cache:set("tools/call:openDiff", {}, "value2")
			test_cache:set("resources/read", {}, "value3")

			test_cache:invalidate("^tools/")

			-- Tools should be gone
			local _, hit1 = test_cache:get("tools/call:openFile", {})
			local _, hit2 = test_cache:get("tools/call:openDiff", {})
			assert.is_false(hit1)
			assert.is_false(hit2)

			-- Resources should remain
			local _, hit3 = test_cache:get("resources/read", {})
			assert.is_true(hit3)
		end)
	end)

	describe("Statistics", function()
		it("should track cache statistics", function()
			test_cache:set("method1", {}, "value1")
			test_cache:set("method2", {}, "value2")

			-- Access method1 multiple times
			test_cache:get("method1", {})
			test_cache:get("method1", {})
			test_cache:get("method1", {})

			local stats = test_cache:stats()
			assert.equals(2, stats.total_entries)
			assert.equals(3, stats.total_hits) -- 3 hits on method1
			assert.equals(5, stats.max_size)
			assert.is_true(stats.estimated_size > 0)
		end)
	end)

	describe("Cleanup", function()
		it("should remove expired entries", function()
			-- Mock time
			local current_time = os.time()
			local original_time = os.time
			os.time = function()
				return current_time
			end

			-- Add entries with different TTLs
			test_cache:set("short", {}, "value1", 5)
			test_cache:set("long", {}, "value2", 100)

			-- Advance time by 10 seconds
			current_time = current_time + 10

			-- Run cleanup
			test_cache:cleanup()

			-- Short-lived entry should be gone
			local stats = test_cache:stats()
			assert.equals(1, stats.total_entries)

			-- Long-lived entry should remain
			local _, hit = test_cache:get("long", {})
			assert.is_true(hit)

			-- Restore
			os.time = original_time
		end)
	end)

	describe("Named Caches", function()
		it("should provide pre-configured cache instances", function()
			local tools_cache = cache.caches.tools()
			local resources_cache = cache.caches.resources()
			local files_cache = cache.caches.files()
			local rpc_cache = cache.caches.rpc()

			assert.not_nil(tools_cache)
			assert.not_nil(resources_cache)
			assert.not_nil(files_cache)
			assert.not_nil(rpc_cache)

			-- Check configurations
			assert.equals(50, tools_cache.max_size)
			assert.equals(200, resources_cache.max_size)
			assert.equals(100, files_cache.max_size)
			assert.equals(100, rpc_cache.max_size)
		end)

		it("should return same instance for same cache name", function()
			local cache1 = cache.get_cache("test_singleton")
			local cache2 = cache.get_cache("test_singleton")

			assert.equals(cache1, cache2)
		end)
	end)

	describe("Module Functions", function()
		it("should get statistics for all caches", function()
			-- Create some caches with data
			local c1 = cache.get_cache("stats1")
			local c2 = cache.get_cache("stats2")

			c1:set("method", {}, "value")
			c2:set("method", {}, "value")

			local all_stats = cache.get_all_stats()

			assert.not_nil(all_stats.stats1)
			assert.not_nil(all_stats.stats2)
			assert.equals(1, all_stats.stats1.total_entries)
			assert.equals(1, all_stats.stats2.total_entries)
		end)

		it("should invalidate all caches", function()
			local c1 = cache.get_cache("inv1")
			local c2 = cache.get_cache("inv2")

			c1:set("method", {}, "value")
			c2:set("method", {}, "value")

			cache.invalidate_all()

			local stats1 = c1:stats()
			local stats2 = c2:stats()

			assert.equals(0, stats1.total_entries)
			assert.equals(0, stats2.total_entries)
		end)
	end)
end)
