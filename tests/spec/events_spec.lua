-- Tests for the event system

describe("Event System", function()
	local events = require("claude-code-ide.events")

	-- Clean up any event handlers between tests
	after_each(function()
		-- Clear all autocmds for our event pattern
		vim.api.nvim_clear_autocmds({
			event = "User",
			pattern = "ClaudeCode:*",
		})
	end)

	describe("emit and on", function()
		it("should emit and receive events with data", function()
			local received_data = nil

			events.on("TestEvent", function(data)
				received_data = data
			end)

			events.emit("TestEvent", { message = "hello", value = 42 })

			-- Wait for scheduled event
			vim.wait(10, function()
				return received_data ~= nil
			end)

			assert.is_table(received_data)
			assert.equals("hello", received_data.message)
			assert.equals(42, received_data.value)
		end)

		it("should handle multiple listeners for same event", function()
			local count = 0

			events.on("CountEvent", function(data)
				count = count + 1
			end)

			events.on("CountEvent", function(data)
				count = count + 10
			end)

			events.emit("CountEvent", {})

			-- Wait for scheduled event
			vim.wait(10, function()
				return count == 11
			end)

			assert.equals(11, count)
		end)

		it("should support wildcard listeners", function()
			local events_received = {}

			events.on("*", function(data)
				table.insert(events_received, vim.fn.expand("<amatch>"))
			end)

			events.emit("Event1", {})
			events.emit("Event2", {})
			events.emit("Event3", {})

			-- Wait for all scheduled events
			vim.wait(10, function()
				return #events_received == 3
			end)

			assert.equals(3, #events_received)
			assert.is_truthy(vim.tbl_contains(events_received, "ClaudeCode:Event1"))
			assert.is_truthy(vim.tbl_contains(events_received, "ClaudeCode:Event2"))
			assert.is_truthy(vim.tbl_contains(events_received, "ClaudeCode:Event3"))
		end)
	end)

	describe("once", function()
		it("should only fire once", function()
			local count = 0

			events.once("OnceEvent", function(data)
				count = count + 1
			end)

			events.emit("OnceEvent", {})
			vim.wait(10) -- Wait for first event

			events.emit("OnceEvent", {})
			events.emit("OnceEvent", {})
			vim.wait(10) -- Wait for any additional events

			assert.equals(1, count)
		end)
	end)

	describe("off", function()
		it("should unsubscribe from events", function()
			local count = 0

			local id = events.on("OffEvent", function(data)
				count = count + 1
			end)

			events.emit("OffEvent", {})
			vim.wait(10, function()
				return count == 1
			end)
			assert.equals(1, count)

			events.off(id)

			events.emit("OffEvent", {})
			vim.wait(10) -- Wait to ensure no more events
			assert.equals(1, count) -- Should still be 1
		end)
	end)

	describe("group", function()
		it("should create event groups", function()
			local group_id = events.group("TestGroup")
			assert.is_number(group_id)

			-- Verify group was created with correct name
			local groups = vim.api.nvim_get_autocmds({ group = group_id })
			assert.is_table(groups)
		end)

		it("should clear all events in a group", function()
			local count = 0
			local group_id = events.group("ClearGroup")

			events.on("GroupEvent1", function()
				count = count + 1
			end, { group = group_id })
			events.on("GroupEvent2", function()
				count = count + 1
			end, { group = group_id })

			events.emit("GroupEvent1", {})
			events.emit("GroupEvent2", {})
			vim.wait(10, function()
				return count == 2
			end)
			assert.equals(2, count)

			events.clear_group(group_id)

			events.emit("GroupEvent1", {})
			events.emit("GroupEvent2", {})
			vim.wait(10) -- Wait to ensure no more events
			assert.equals(2, count) -- Should still be 2
		end)
	end)

	describe("predefined events", function()
		it("should have all expected event constants", function()
			assert.equals("Connected", events.events.CONNECTED)
			assert.equals("Disconnected", events.events.DISCONNECTED)
			assert.equals("ToolExecuted", events.events.TOOL_EXECUTED)
			assert.equals("FileOpened", events.events.FILE_OPENED)
			assert.equals("ServerStarted", events.events.SERVER_STARTED)
		end)
	end)

	describe("debug mode", function()
		it("should log events when debug is enabled", function()
			local original_notify = vim.notify
			local notifications = {}

			-- Mock vim.notify
			vim.notify = function(msg, level)
				table.insert(notifications, { msg = msg, level = level })
			end

			events.debug(true)
			events.emit("DebugTest", { value = "test" })

			-- Wait for the scheduled event and debug notification
			vim.wait(10, function()
				return #notifications > 0
			end)

			events.debug(false)

			-- Restore original notify
			vim.notify = original_notify

			-- Check that debug notification was sent
			assert.is_true(#notifications > 0)
			local found = false
			for _, notif in ipairs(notifications) do
				if notif.msg:match("DebugTest") and notif.level == vim.log.levels.DEBUG then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)
	end)
end)
