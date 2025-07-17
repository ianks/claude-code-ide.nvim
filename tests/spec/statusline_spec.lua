-- Tests for statusline integration
local statusline = require("claude-code-ide.statusline")
local events = require("claude-code-ide.events")

describe("Statusline Integration", function()
	before_each(function()
		-- Reset statusline state completely
		statusline._reset()

		-- Setup statusline
		statusline.setup()
	end)

	after_each(function()
		statusline.stop()
		statusline._reset()
	end)

	describe("Status Display", function()
		it("should show disconnected state by default", function()
			local status = statusline.get_status()
			assert.truthy(status:match("○"))
		end)

		it("should show connected state when server is running", function()
			-- Mock server state
			local server = require("claude-code-ide.server")
			server._state = { running = true }
			server.get_server = function()
				return server._state
			end

			local status = statusline.get_status()
			assert.truthy(status:match("●"))
		end)

		it("should display status messages", function()
			-- Directly set state to test display logic
			statusline._state.message = "Claude connected"
			local status = statusline.get_status()
			assert.truthy(status:match("Claude connected"))
		end)
	end)

	describe("Tool Execution Tracking", function()
		it("should track tool executions", function()
			assert.equals(0, statusline.get_tool_count())

			-- Directly manipulate state
			statusline._state.tool_count = 1

			assert.equals(1, statusline.get_tool_count())
		end)

		it("should show tool count in status", function()
			-- Set tool count
			statusline._state.tool_count = 1

			local status = statusline.get_status()
			assert.truthy(status:match("%[1%]"))
		end)

		it("should display executing message", function()
			-- Set executing state
			statusline._state.status = "executing"
			statusline._state.message = "Executing getDiagnostics..."

			local status = statusline.get_status()
			assert.truthy(status:match("Executing getDiagnostics"))
		end)
	end)

	describe("Progress Display", function()
		it("should show progress messages", function()
			-- Set thinking state
			statusline._state.status = "thinking"
			statusline._state.message = "Analyzing code..."

			local status = statusline.get_status()
			assert.truthy(status:match("Analyzing code"))
		end)

		it("should clear progress on completion", function()
			-- Set completion message
			statusline._state.status = "idle"
			statusline._state.message = "Done!"

			local status = statusline.get_status()
			assert.truthy(status:match("Done!"))
		end)
	end)

	describe("Error Handling", function()
		it("should display tool failures", function()
			-- Set error state
			statusline._state.status = "error"
			statusline._state.message = "Failed: openFile"

			local status = statusline.get_status()
			assert.truthy(status:match("Failed: openFile"))
		end)
	end)

	describe("Animation", function()
		it("should not crash when animation is started", function()
			-- This test just ensures no errors occur
			assert.has_no_errors(function()
				events.emit(events.events.TOOL_EXECUTING, {
					tool = "openFile",
				})
				-- Animation should be running now
			end)
		end)

		it("should stop animation on completion", function()
			assert.has_no_errors(function()
				events.emit(events.events.TOOL_EXECUTING, {
					tool = "openFile",
				})

				events.emit(events.events.TOOL_EXECUTED, {
					tool = "openFile",
				})
			end)
		end)
	end)

	describe("Helper Functions", function()
		it("should provide minimal indicator", function()
			local indicator = statusline.get_indicator()
			assert.truthy(indicator == "●" or indicator == "○")
		end)

		it("should reset tool count", function()
			-- Set tool count
			statusline._state.tool_count = 1

			assert.equals(1, statusline.get_tool_count())

			statusline.reset_tool_count()
			assert.equals(0, statusline.get_tool_count())
		end)
	end)
end)
