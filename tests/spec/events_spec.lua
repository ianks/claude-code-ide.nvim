-- Comprehensive tests for the refactored event system

local events = require("claude-code-ide.events")

describe("Event System", function()
	-- Clean up between tests
	after_each(function()
		-- Shutdown event system to clean up resources
		if events and events.shutdown then
			pcall(events.shutdown) -- Safe shutdown
		end

		-- Clear all autocmds for our event pattern
		pcall(vim.api.nvim_clear_autocmds, {
			event = "User",
			pattern = "ClaudeCode:*",
		})

		-- Reset module state quickly
		if _G.test_utils then
			_G.test_utils.reset_modules("claude%-code%-ide%.events")
		end
		events = require("claude-code-ide.events")
	end)

	describe("Initialization and Setup", function()
		it("should initialize with default configuration", function()
			events.setup()

			local stats = events.get_stats()
			assert.truthy(stats)
			assert.equals(0, stats.events_emitted)
			assert.equals(0, stats.events_handled)
			assert.equals(0, stats.errors)
		end)

		it("should initialize with custom configuration", function()
			local config = {
				async = false,
				debug = true,
				trace_callbacks = true,
				max_listeners = 500,
			}

			events.setup(config)

			local debug_info = events.get_debug_info()
			assert.is_true(debug_info.enabled)
			assert.truthy(debug_info.config)
			assert.equals(500, debug_info.config.max_listeners)
		end)

		it("should prevent multiple initialization", function()
			events.setup()

			-- Second setup should warn but not fail
			local original_notify = vim.notify
			local warnings = {}
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN then
					table.insert(warnings, msg)
				end
			end

			events.setup()

			vim.notify = original_notify
			assert.equals(1, #warnings)
			assert.truthy(warnings[1]:find("already initialized"))
		end)

		it("should emit initialization event", function()
			local init_events = {}

			events.setup()

			events.on("EventSystemInitialized", function(data)
				table.insert(init_events, data)
			end)

			-- Wait for initialization event
			vim.wait(50)

			assert.equals(1, #init_events)
			assert.truthy(init_events[1])
		end)
	end)

	describe("Event Validation", function()
		before_each(function()
			events.setup()
		end)

		it("should validate event names", function()
			-- Valid event names
			assert.has_no_error(function()
				events.emit("ValidEvent", {})
			end)

			assert.has_no_error(function()
				events.emit("Valid_Event-123", {})
			end)

			-- Invalid event names
			assert.has_error(function()
				events.emit("", {})
			end, "Event name must be a non-empty string")

			assert.has_error(function()
				events.emit(123, {})
			end, "Event name must be a non-empty string")

			assert.has_error(function()
				events.emit("Invalid Event With Spaces", {})
			end, "Event name contains invalid characters")

			-- Too long event name
			local long_name = string.rep("a", 101)
			assert.has_error(function()
				events.emit(long_name, {})
			end, "Event name too long")
		end)

		it("should validate callback functions", function()
			assert.has_error(function()
				events.on("TestEvent", "not a function")
			end, "Invalid callback")

			assert.has_error(function()
				events.on("TestEvent", nil)
			end, "Invalid callback")

			assert.has_no_error(function()
				events.on("TestEvent", function() end)
			end)
		end)
	end)

	describe("Event Emission and Handling", function()
		before_each(function()
			events.setup()
		end)

		it("should emit and receive events with data", function()
			local received_data = nil

			events.on("TestEvent", function(data)
				received_data = data
			end)

			events.emit("TestEvent", { message = "hello", value = 42 })

			-- Wait for event processing with timeout
			_G.test_utils.wait(50, function()
				return received_data ~= nil
			end)

			assert.is_table(received_data)
			assert.equals("hello", received_data.message)
			assert.equals(42, received_data.value)
		end)

		it("should handle multiple listeners for same event", function()
			local count = 0
			local messages = {}

			events.on("CountEvent", function(data)
				count = count + 1
				table.insert(messages, data.message)
			end)

			events.on("CountEvent", function(data)
				count = count + 10
				table.insert(messages, data.message .. "_modified")
			end)

			events.emit("CountEvent", { message = "test" })

			_G.test_utils.wait(50, function()
				return count == 11
			end)

			assert.equals(11, count)
			assert.equals(2, #messages)
			assert.truthy(vim.tbl_contains(messages, "test"))
			assert.truthy(vim.tbl_contains(messages, "test_modified"))
		end)

		it("should handle events without data", function()
			local called = false

			events.on("NoDataEvent", function(data)
				called = true
				assert.is_nil(data)
			end)

			events.emit("NoDataEvent")

			_G.test_utils.wait(50, function()
				return called
			end)
			assert.is_true(called)
		end)

		it("should handle once events correctly", function()
			local call_count = 0

			events.once("OnceEvent", function(data)
				call_count = call_count + 1
			end)

			-- Emit multiple times
			events.emit("OnceEvent", {})
			events.emit("OnceEvent", {})
			events.emit("OnceEvent", {})

			_G.test_utils.wait(50)

			-- Should only be called once
			assert.equals(1, call_count)
		end)
	end)

	describe("Async Event Processing", function()
		before_each(function()
			events.setup({ async = true })
		end)

		it("should process async events", function()
			local processed_events = {}

			events.on("AsyncEvent", function(data)
				table.insert(processed_events, data)
			end)

			-- Emit multiple async events
			events.emit("AsyncEvent", { id = 1 }, { async = true })
			events.emit("AsyncEvent", { id = 2 }, { async = true })
			events.emit("AsyncEvent", { id = 3 }, { async = true })

			-- Wait for async processing
			_G.test_utils.wait(100, function()
				return #processed_events >= 3
			end)

			assert.equals(3, #processed_events)

			local stats = events.get_stats()
			assert.equals(3, stats.async_events)
		end)

		it("should handle async queue overflow", function()
			-- Setup with small queue size
			events.shutdown()
			events.setup({ async = true })

			local processed = 0
			events.on("OverflowEvent", function(data)
				processed = processed + 1
			end)

			-- Emit many events rapidly to test overflow
			for i = 1, 600 do -- More than ASYNC_QUEUE_SIZE (500)
				events.emit("OverflowEvent", { id = i }, { async = true })
			end

			vim.wait(500) -- Wait for processing

			-- Some events should be dropped due to queue overflow
			assert.is_true(processed <= 500)
		end)
	end)

	describe("Error Handling and Resilience", function()
		before_each(function()
			events.setup()
		end)

		it("should handle callback errors gracefully", function()
			local good_callback_called = false
			local error_callback_called = false

			-- Register a callback that will error
			events.on("ErrorEvent", function(data)
				error_callback_called = true
				error("Intentional test error")
			end)

			-- Register a good callback
			events.on("ErrorEvent", function(data)
				good_callback_called = true
			end)

			events.emit("ErrorEvent", {})

			_G.test_utils.wait(50, function()
				return error_callback_called and good_callback_called
			end)

			-- Both callbacks should have been called despite error
			assert.is_true(error_callback_called)
			assert.is_true(good_callback_called)

			-- Error should be tracked in stats
			local stats = events.get_stats()
			assert.is_true(stats.errors > 0)
		end)

		it("should continue processing after callback errors", function()
			local successful_events = 0

			events.on("MixedEvent", function(data)
				if data.should_error then
					error("Test error")
				else
					successful_events = successful_events + 1
				end
			end)

			-- Emit mix of good and bad events
			events.emit("MixedEvent", { should_error = true })
			events.emit("MixedEvent", { should_error = false })
			events.emit("MixedEvent", { should_error = true })
			events.emit("MixedEvent", { should_error = false })

			_G.test_utils.wait(100, function()
				return successful_events >= 2
			end)

			assert.equals(2, successful_events)
		end)

		it("should enforce listener limits", function()
			-- Setup with low listener limit
			events.shutdown()
			events.setup({ max_listeners = 5 })

			-- Register maximum listeners
			for i = 1, 5 do
				assert.has_no_error(function()
					events.on("LimitEvent", function() end)
				end)
			end

			-- Next listener should error
			assert.has_error(function()
				events.on("LimitEvent", function() end)
			end, "Maximum number of event listeners exceeded")
		end)
	end)

	describe("Event Groups and Management", function()
		before_each(function()
			events.setup()
		end)

		it("should create and manage event groups", function()
			local group_id = events.group("test_group")
			assert.truthy(group_id)
			assert.equals("number", type(group_id))

			-- Clear group should not error
			assert.has_no_error(function()
				events.clear_group(group_id)
			end)
		end)

		it("should unregister listeners correctly", function()
			local call_count = 0

			local autocmd_id = events.on("UnregisterEvent", function()
				call_count = call_count + 1
			end)

			-- Emit event - should be received
			events.emit("UnregisterEvent")
			vim.wait(50)
			assert.equals(1, call_count)

			-- Unregister listener
			local success = events.off(autocmd_id)
			assert.is_true(success)

			-- Emit again - should not be received
			events.emit("UnregisterEvent")
			vim.wait(50)
			assert.equals(1, call_count) -- Still 1
		end)

		it("should handle invalid unregister gracefully", function()
			local success = events.off(99999) -- Invalid ID
			assert.is_false(success)

			success = events.off(nil)
			assert.is_false(success)
		end)
	end)

	describe("Debug and Monitoring", function()
		before_each(function()
			events.setup({ debug = true })
		end)

		it("should track debug information when enabled", function()
			events.debug(true)

			events.emit("DebugEvent", { test = "data" })
			vim.wait(50)

			local debug_info = events.get_debug_info()
			assert.is_true(debug_info.enabled)
			assert.is_true(#debug_info.buffer > 0)

			-- Check debug entry structure
			local entry = debug_info.buffer[1]
			assert.truthy(entry.timestamp)
			assert.truthy(entry.type)
			assert.truthy(entry.event)
		end)

		it("should clear debug buffer when disabled", function()
			events.debug(true)
			events.emit("TestEvent", {})
			vim.wait(50)

			local debug_info = events.get_debug_info()
			assert.is_true(#debug_info.buffer > 0)

			events.debug(false)
			debug_info = events.get_debug_info()
			assert.is_false(debug_info.enabled)
			assert.equals(0, #debug_info.buffer)
		end)

		it("should provide comprehensive statistics", function()
			events.emit("StatEvent1", {})
			events.emit("StatEvent2", {})

			local listener_id = events.on("StatEvent3", function() end)
			events.emit("StatEvent3", {})

			vim.wait(100)

			local stats = events.get_stats()
			assert.equals(3, stats.events_emitted)
			assert.is_true(stats.events_handled >= 1)
			assert.is_true(stats.active_listeners >= 1)
			assert.truthy(stats.uptime_ms)
		end)

		it("should emit callback completion events when tracing", function()
			events.shutdown()
			events.setup({ trace_callbacks = true })

			local completion_events = {}
			events.on("CallbackCompleted", function(data)
				table.insert(completion_events, data)
			end)

			events.on("TracedEvent", function() end)
			events.emit("TracedEvent", {})

			vim.wait(100)

			assert.is_true(#completion_events > 0)
			assert.truthy(completion_events[1].event)
			assert.truthy(completion_events[1].success)
			assert.truthy(completion_events[1].duration_ms)
		end)
	end)

	describe("Resource Management and Cleanup", function()
		it("should cleanup resources on shutdown", function()
			events.setup()

			-- Register some listeners
			events.on("CleanupEvent1", function() end)
			events.on("CleanupEvent2", function() end)

			local stats_before = events.get_stats()
			assert.is_true(stats_before.active_listeners > 0)

			-- Shutdown should clean up
			events.shutdown()

			-- Try to emit after shutdown - should not crash
			assert.has_no_error(function()
				events.emit("PostShutdownEvent", {})
			end)
		end)

		it("should handle shutdown when not initialized", function()
			-- Shutdown without initialization should not error
			assert.has_no_error(function()
				events.shutdown()
			end)
		end)

		it("should manage timer resources correctly", function()
			events.setup()

			-- Stats should show initialization
			local stats = events.get_stats()
			assert.truthy(stats.uptime_ms)

			-- Shutdown should stop timers
			events.shutdown()

			-- No way to directly test timer cleanup, but it should not error
		end)
	end)

	describe("Event Constants", function()
		it("should provide consistent event names", function()
			assert.truthy(events.events)
			assert.equals("string", type(events.events.CONNECTED))
			assert.equals("string", type(events.events.DISCONNECTED))
			assert.equals("string", type(events.events.TOOL_EXECUTED))
			assert.equals("string", type(events.events.SERVER_STARTED))
			assert.equals("string", type(events.events.HEALTH_CHECK))
		end)

		it("should have all expected event constants", function()
			local expected_events = {
				"INITIALIZED",
				"SHUTDOWN",
				"CONNECTED",
				"DISCONNECTED",
				"TOOL_EXECUTING",
				"TOOL_EXECUTED",
				"TOOL_FAILED",
				"SERVER_STARTED",
				"SERVER_STOPPED",
				"HEALTH_CHECK",
				"CONFIGURATION_CHANGED",
				"TERMINAL_CREATED",
			}

			for _, event_name in ipairs(expected_events) do
				assert.truthy(events.events[event_name], "Missing event constant: " .. event_name)
				assert.equals("string", type(events.events[event_name]))
			end
		end)
	end)

	describe("Health Check", function()
		it("should provide health status", function()
			events.setup()

			local health = events.health_check()
			assert.truthy(health.healthy)
			assert.truthy(health.details.initialized)
			assert.equals(0, health.details.listeners)
			assert.truthy(health.details.stats)
		end)

		it("should report unhealthy with too many errors", function()
			events.setup()

			-- Generate many errors
			events.on("ErrorEvent", function()
				error("Test error")
			end)

			for i = 1, 150 do -- More than error threshold
				events.emit("ErrorEvent", {})
			end

			vim.wait(200)

			local health = events.health_check()
			assert.is_false(health.healthy)
		end)

		it("should report details correctly", function()
			events.setup()

			-- Add some listeners
			events.on("HealthEvent1", function() end)
			events.on("HealthEvent2", function() end)

			local health = events.health_check()
			assert.equals(2, health.details.listeners)
			assert.equals(0, health.details.queue_size)
		end)
	end)

	describe("Performance and Load Testing", function()
		before_each(function()
			events.setup()
		end)

		it("should handle rapid event emission", function()
			local processed = 0
			events.on("RapidEvent", function()
				processed = processed + 1
			end)

			local start_time = vim.loop.hrtime()

			-- Emit many events rapidly
			for i = 1, 100 do
				events.emit("RapidEvent", { id = i })
			end

			vim.wait(200)

			local duration_ms = (vim.loop.hrtime() - start_time) / 1e6

			assert.equals(100, processed)
			assert.is_true(duration_ms < 1000) -- Should complete within 1 second
		end)

		it("should maintain performance with many listeners", function()
			-- Register many listeners for same event
			for i = 1, 50 do
				events.on("ManyListenersEvent", function() end)
			end

			local start_time = vim.loop.hrtime()
			events.emit("ManyListenersEvent", {})
			vim.wait(100)
			local duration_ms = (vim.loop.hrtime() - start_time) / 1e6

			assert.is_true(duration_ms < 500) -- Should complete within 500ms
		end)
	end)
end)
