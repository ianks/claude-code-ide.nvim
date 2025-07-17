-- Tests for progress indicators and animations

local progress = require("claude-code-ide.ui.progress")
local events = require("claude-code-ide.events")

describe("Progress Indicators", function()
	local captured_events = {}
	local event_handlers = {}

	before_each(function()
		-- Clear any active progress
		progress.stop_all()
		captured_events = {}

		-- Always start with fresh handlers
		event_handlers = {}

		-- Mock Snacks notify
		package.loaded["snacks"] = {
			notify = function(message, level, opts)
				return {
					update = function(self, msg)
						self.message = msg
					end,
					icon = opts and opts.icon or "",
					message = message,
					level = level,
				}
			end,
			notifier = {
				hide = function() end,
			},
		}
	end)

	after_each(function()
		-- Clean up event handlers
		for _, handler in ipairs(event_handlers) do
			events.off(handler)
		end
		progress.stop_all()
	end)

	describe("Basic Progress", function()
		it("should show and hide progress", function()
			local p = progress.show("Test progress")
			assert.truthy(p)
			assert.equals("Test progress", p.message)
			assert.equals("dots", p.animation)

			p:stop()
			assert.is_nil(progress.get(p.id))
		end)

		it("should emit events", function()
			-- Create a unique group for this test
			local test_group = events.group("progress_test_" .. vim.fn.tempname())

			-- Ensure we start clean
			local test_events = {}

			-- Set up event handlers in test group
			events.on(events.events.PROGRESS_STARTED, function(data)
				table.insert(test_events, { type = "started", data = data })
			end, { group = test_group })

			events.on(events.events.PROGRESS_COMPLETED, function(data)
				table.insert(test_events, { type = "completed", data = data })
			end, { group = test_group })

			local p = progress.show("Test progress")

			-- Wait for async event
			vim.wait(100, function()
				return #test_events > 0
			end)

			-- At least one started event
			assert.is_true(#test_events >= 1)

			-- Find our specific event
			local found_start = false
			for _, event in ipairs(test_events) do
				if event.type == "started" and event.data.message == "Test progress" then
					found_start = true
					break
				end
			end
			assert.is_true(found_start, "Did not find expected start event")

			local events_before_complete = #test_events
			p:complete("Done!", true)

			-- Wait for completion event
			vim.wait(100, function()
				return #test_events > events_before_complete
			end)

			-- Find our completion event
			local found_complete = false
			for i = events_before_complete + 1, #test_events do
				local event = test_events[i]
				if event.type == "completed" and event.data.message == "Done!" and event.data.success == true then
					found_complete = true
					break
				end
			end
			assert.is_true(found_complete, "Did not find expected completion event")

			-- Clean up entire group
			events.clear_group(test_group)
		end)

		it("should update message and percentage", function()
			local p = progress.show_with_percentage("Processing...")

			p:update_message("Still processing...")
			assert.equals("Still processing...", p.message)

			p:update_percentage(50)
			assert.equals(50, p.percentage)

			p:update_percentage(150) -- Should clamp to 100
			assert.equals(100, p.percentage)

			p:stop()
		end)
	end)

	describe("Animation Presets", function()
		it("should have all animation types", function()
			local expected_animations = {
				"dots",
				"dots2",
				"dots3",
				"line",
				"line2",
				"pipe",
				"star",
				"flip",
				"hamburger",
				"grow",
				"balloon",
				"noise",
				"bounce",
				"bouncingBar",
				"clock",
				"earth",
				"moon",
				"ai_thinking",
				"ai_processing",
				"ai_writing",
				"code_analysis",
				"compile",
				"search",
			}

			for _, anim in ipairs(expected_animations) do
				assert.truthy(progress.animations[anim], "Missing animation: " .. anim)
			end
		end)

		it("should use specified animation", function()
			local p = progress.show("Test", { animation = "ai_thinking" })
			assert.equals("ai_thinking", p.animation)
			p:stop()
		end)
	end)

	describe("Progress Types", function()
		it("should show spinner", function()
			local p = progress.spinner("Loading...")
			assert.equals("dots", p.animation)
			assert.equals("Loading...", p.message)
			p:stop()
		end)

		it("should show AI thinking", function()
			local p = progress.ai_thinking()
			assert.equals("ai_thinking", p.animation)
			assert.equals("Claude is thinking...", p.message)
			p:stop()
		end)

		it("should show code analysis", function()
			local p = progress.code_analysis()
			assert.equals("code_analysis", p.animation)
			assert.equals("Analyzing code...", p.message)
			p:stop()
		end)

		it("should show with timer", function()
			local p = progress.show_with_timer("Processing...")
			assert.is_true(p.show_elapsed)
			p:stop()
		end)
	end)

	describe("Multi-step Progress", function()
		it("should handle multiple steps", function()
			local steps = { "Step 1", "Step 2", "Step 3" }
			local multi = progress.multi_step(steps)

			assert.equals(0, multi.current_step)

			-- First step
			assert.is_true(multi:next())
			assert.equals(1, multi.current_step)
			assert.truthy(multi.progress)
			assert.truthy(multi.progress.message:match("Step 1"))

			-- Second step
			assert.is_true(multi:next())
			assert.equals(2, multi.current_step)
			assert.truthy(multi.progress.message:match("Step 2"))

			-- Third step
			assert.is_true(multi:next())
			assert.equals(3, multi.current_step)

			-- Beyond last step
			assert.is_false(multi:next())

			-- Wait for completion
			vim.wait(100, function()
				return multi.progress.completed
			end)
		end)

		it("should show step progress percentage", function()
			local steps = { "A", "B", "C", "D" }
			local multi = progress.multi_step(steps)

			multi:next()
			assert.equals(0, multi.progress.percentage) -- 0/4

			multi:next()
			assert.equals(25, multi.progress.percentage) -- 1/4

			multi:next()
			assert.equals(50, multi.progress.percentage) -- 2/4

			multi:complete(true)
		end)
	end)

	describe("Progress Management", function()
		it("should track active progress", function()
			local p1 = progress.show("Progress 1")
			local p2 = progress.show("Progress 2")

			assert.truthy(progress.get(p1.id))
			assert.truthy(progress.get(p2.id))

			p1:stop()
			assert.is_nil(progress.get(p1.id))
			assert.truthy(progress.get(p2.id))

			progress.stop_all()
			assert.is_nil(progress.get(p2.id))
		end)

		it("should handle completion callback", function()
			local callback_called = false
			local callback_success = nil

			local p = progress.show("Test", {
				on_complete = function(success)
					callback_called = true
					callback_success = success
				end,
			})

			p:complete("Done", true)

			assert.is_true(callback_called)
			assert.is_true(callback_success)
		end)

		it("should handle timeout", function()
			local p = progress.show("Test", { timeout = 50 })

			-- Wait for timeout
			vim.wait(100, function()
				return p.completed
			end)

			assert.is_true(p.completed)
		end)
	end)

	describe("Message Formatting", function()
		it("should format elapsed time", function()
			local p = progress.show_with_timer("Test")

			-- Mock time
			p.start_time = vim.loop.now() - 65000 -- 65 seconds ago

			local msg = p:format_message()
			assert.truthy(msg:match("1m 5s"))

			p.start_time = vim.loop.now() - 45000 -- 45 seconds ago
			msg = p:format_message()
			assert.truthy(msg:match("45s"))

			p:stop()
		end)

		it("should format percentage", function()
			local p = progress.show_with_percentage("Test")

			p:update_percentage(75)
			local msg = p:format_message()
			assert.truthy(msg:match("75%%"))

			p:stop()
		end)
	end)
end)
