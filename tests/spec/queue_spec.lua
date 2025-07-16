-- Tests for request queue and rate limiting

local queue = require("claude-code.queue")
local events = require("claude-code.events")

describe("Request Queue", function()
	local test_queue
	local captured_events
	local event_handlers

	before_each(function()
		-- Create new queue instance
		test_queue = queue.Queue.new({
			max_concurrent = 2,
			max_queue_size = 10,
			rate_limit = {
				enabled = true,
				max_requests = 5,
				window_ms = 1000,
				retry_after_ms = 100,
			},
			timeout_ms = 500,
		})

		-- Reset captured events
		captured_events = {}
		event_handlers = {}

		-- Capture queue events
		local queue_events = {
			"RequestQueued",
			"RequestProcessing",
			"RequestProgress",
			"QueueRequestCompleted",
			"QueueRequestFailed",
			"RequestCancelled",
			"QueueCleared",
		}

		for _, event in ipairs(queue_events) do
			table.insert(
				event_handlers,
				events.on(event, function(data)
					table.insert(captured_events, { type = event, data = data })
				end)
			)
		end

		-- Mock vim.loop.now for consistent timing
		local time = 0
		vim.loop.now = function()
			return time
		end

		-- Helper to advance time
		_G.advance_time = function(ms)
			time = time + ms
		end
	end)

	after_each(function()
		-- Clean up event handlers
		for _, handler in ipairs(event_handlers) do
			events.off(handler)
		end
	end)

	describe("Basic Queueing", function()
		it("should enqueue requests", function()
			local request = {
				method = "test",
				priority = "normal",
				handler = function(params)
					return { success = true }
				end,
			}

			local id = test_queue:enqueue(request)

			assert.truthy(id)
			assert.truthy(id:match("test_%d+_%d+"))
			assert.equals(1, #test_queue.queue)
		end)

		it("should respect queue size limit", function()
			local request = {
				method = "test",
				handler = function()
					return {}
				end,
			}

			-- Fill the queue
			for i = 1, 10 do
				test_queue:enqueue(request)
			end

			-- Try to add one more
			local id = test_queue:enqueue(request)
			assert.is_nil(id)
			assert.equals(10, #test_queue.queue)
		end)

		it("should order by priority", function()
			-- Add low priority
			test_queue:enqueue({
				method = "low",
				priority = "low",
				handler = function()
					return {}
				end,
			})

			-- Add high priority
			test_queue:enqueue({
				method = "high",
				priority = "high",
				handler = function()
					return {}
				end,
			})

			-- Add normal priority
			test_queue:enqueue({
				method = "normal",
				priority = "normal",
				handler = function()
					return {}
				end,
			})

			-- Check order: high, normal, low
			assert.equals("high", test_queue.queue[1].request.method)
			assert.equals("normal", test_queue.queue[2].request.method)
			assert.equals("low", test_queue.queue[3].request.method)
		end)
	end)

	describe("Request Processing", function()
		it("should process requests", function()
			local processed = false
			local request = {
				method = "test",
				handler = function(params)
					processed = true
					return { result = "ok" }
				end,
			}

			test_queue:enqueue(request)

			-- Wait for processing
			vim.wait(100, function()
				return processed
			end)

			assert.is_true(processed)
			assert.equals(0, #test_queue.queue)
			assert.equals(0, vim.tbl_count(test_queue.processing))
		end)

		it("should handle concurrent requests", function()
			local max_concurrent_seen = 0
			local processing_count = 0
			local completed_count = 0

			local make_request = function(name)
				return {
					method = name,
					handler = function(params)
						processing_count = processing_count + 1
						max_concurrent_seen = math.max(max_concurrent_seen, processing_count)

						-- Simulate work
						vim.wait(30)

						processing_count = processing_count - 1
						completed_count = completed_count + 1
						return { name = name }
					end,
				}
			end

			-- Queue 4 requests
			for i = 1, 4 do
				test_queue:enqueue(make_request("req" .. i))
			end

			-- Wait for all to complete
			vim.wait(500, function()
				return completed_count == 4
			end)

			-- Verify all completed
			assert.equals(4, completed_count)

			-- Verify we respected max concurrent limit (2)
			assert.is_true(
				max_concurrent_seen <= 2,
				"Max concurrent was " .. max_concurrent_seen .. " but should be <= 2"
			)
		end)

		it("should handle request callbacks", function()
			local callback_result = nil
			local callback_error = nil

			local request = {
				method = "test",
				handler = function(params)
					return { status = "done" }
				end,
				callback = function(err, result)
					callback_error = err
					callback_result = result
				end,
			}

			test_queue:enqueue(request)

			vim.wait(100, function()
				return callback_result ~= nil
			end)

			assert.is_nil(callback_error)
			assert.equals("done", callback_result.status)
		end)
	end)

	describe("Error Handling", function()
		it("should handle handler errors", function()
			local callback_error = nil

			local request = {
				method = "failing",
				handler = function(params)
					error("Handler failed")
				end,
				callback = function(err, result)
					callback_error = err
				end,
			}

			test_queue:enqueue(request)

			vim.wait(100, function()
				return callback_error ~= nil
			end)

			assert.truthy(callback_error)
			assert.truthy(callback_error:match("Handler failed"))
			assert.equals(1, test_queue.stats.failed)
		end)

		it("should retry failed requests", function()
			local attempt_count = 0
			local callback_result = nil

			local request = {
				method = "retry_test",
				max_retries = 2,
				handler = function(params)
					attempt_count = attempt_count + 1
					if attempt_count < 3 then
						error("Try again")
					end
					return { attempts = attempt_count }
				end,
				callback = function(err, result)
					callback_result = result or { error = err }
				end,
			}

			test_queue:enqueue(request)

			vim.wait(5000, function()
				return callback_result ~= nil
			end)

			assert.equals(3, attempt_count)
			assert.equals(3, callback_result.attempts)
		end)

		it("should handle timeouts", function()
			-- Use shorter timeout for testing
			test_queue.config.timeout_ms = 50

			local callback_error = nil

			local request = {
				method = "timeout_test",
				handler = function(params)
					-- Simulate long running task
					vim.wait(200)
					return { done = true }
				end,
				callback = function(err, result)
					callback_error = err
				end,
			}

			test_queue:enqueue(request)

			vim.wait(100, function()
				return callback_error ~= nil
			end)

			assert.truthy(callback_error)
			assert.truthy(callback_error:match("timed out"))
		end)
	end)

	describe("Rate Limiting", function()
		it("should enforce rate limits", function()
			local completed_count = 0

			local make_request = function(n)
				return {
					method = "rate_test_" .. n,
					handler = function()
						completed_count = completed_count + 1
						return { n = n }
					end,
				}
			end

			-- Queue 7 requests (limit is 5 per window)
			for i = 1, 7 do
				test_queue:enqueue(make_request(i))
			end

			-- Wait for some processing
			vim.wait(100, function()
				return completed_count >= 5
			end)

			-- Should have processed up to limit
			assert.equals(5, completed_count)
			assert.is_true(test_queue:is_rate_limited())
			-- Rate limited count may be higher due to multiple attempts
			assert.is_true(test_queue.stats.rate_limited >= 1)

			-- Wait for rate limit window to pass
			advance_time(1000)
			vim.wait(200, function()
				return completed_count == 7
			end)

			-- Should process remaining
			assert.equals(7, completed_count)
		end)

		it("should clean up old requests from rate limit window", function()
			-- Add some requests
			for i = 1, 3 do
				table.insert(test_queue.rate_limiter.requests, i * 100)
			end

			-- Advance time past window
			advance_time(2000)

			-- Check rate limit (should clean up old requests)
			assert.is_false(test_queue:is_rate_limited())
			assert.equals(0, #test_queue.rate_limiter.requests)
		end)
	end)

	describe("Progress Updates", function()
		it("should handle progress updates", function()
			local progress_updates = {}

			local request = {
				method = "progress_test",
				handler = function(params, context)
					context.on_progress({ percent = 25, message = "Starting" })
					context.on_progress({ percent = 50, message = "Half way" })
					context.on_progress({ percent = 100, message = "Done" })
					return { complete = true }
				end,
			}

			-- Capture progress events
			local handler = events.on("RequestProgress", function(data)
				table.insert(progress_updates, data.progress)
			end)

			test_queue:enqueue(request)

			vim.wait(100)

			assert.equals(3, #progress_updates)
			assert.equals(25, progress_updates[1].percent)
			assert.equals(50, progress_updates[2].percent)
			assert.equals(100, progress_updates[3].percent)

			events.off(handler)
		end)
	end)

	describe("Queue Management", function()
		it("should cancel queued requests", function()
			local request = {
				method = "cancel_test",
				handler = function()
					vim.wait(100)
					return {}
				end,
			}

			local id = test_queue:enqueue(request)

			-- Cancel before processing
			local cancelled = test_queue:cancel(id)
			assert.is_true(cancelled)
			assert.equals(0, #test_queue.queue)
		end)

		it("should clear the queue", function()
			-- Add multiple requests
			for i = 1, 5 do
				test_queue:enqueue({
					method = "clear_test_" .. i,
					handler = function()
						return {}
					end,
				})
			end

			assert.equals(5, #test_queue.queue)

			test_queue:clear()

			assert.equals(0, #test_queue.queue)

			-- Wait a bit for event to be emitted
			vim.wait(50)

			-- Check event was emitted
			local found = false
			for _, event in ipairs(captured_events) do
				if event.type == "QueueCleared" then
					found = true
					break
				end
			end
			assert.is_true(found, "QueueCleared event not found in captured events")
		end)

		it("should provide queue status", function()
			-- Add some requests
			for i = 1, 3 do
				test_queue:enqueue({
					method = "status_test_" .. i,
					handler = function()
						return {}
					end,
				})
			end

			local status = test_queue:get_status()

			assert.equals(3, status.queue_size)
			assert.equals(0, status.processing)
			assert.equals(2, status.max_concurrent)
			assert.is_false(status.rate_limited)
			assert.truthy(status.stats)
		end)
	end)

	describe("Module Interface", function()
		it("should provide module-level functions", function()
			-- Initialize
			queue.init({ max_concurrent = 1 })

			-- Enqueue
			local id = queue.enqueue({
				method = "module_test",
				handler = function()
					return { ok = true }
				end,
			})

			assert.truthy(id)

			-- Get status
			local status = queue.get_status()
			assert.equals(1, status.queue_size)

			-- Clear
			queue.clear()
			status = queue.get_status()
			assert.equals(0, status.queue_size)
		end)
	end)
end)
