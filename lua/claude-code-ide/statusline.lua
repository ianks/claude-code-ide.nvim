-- Statusline integration for claude-code-ide.nvim
-- Provides functions for displaying Claude status in the statusline

local M = {}
local events = require("claude-code-ide.events")

-- Module state
M._state = {
	status = "idle",
	message = "",
	tool_count = 0,
	last_tool = nil,
	animation_frame = 1,
	animation_timer = nil,
	initialized = false,
}

-- Animation frames for different states
local animations = {
	thinking = { ".", "..", "...", "...." },
	processing = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	executing = { ">", ">>", ">>>", ">>>>" },
}

-- Initialize statusline integration
function M.setup()
	if M._state.initialized then
		return
	end

	M._state.initialized = true

	-- Listen to Claude events
	events.on(events.events.TOOL_EXECUTING, function(data)
		M._state.tool_count = M._state.tool_count + 1
		M._state.last_tool = data.tool or data.method
		M._state.status = "executing"
		M._state.message = string.format("Executing %s...", M._state.last_tool)
		M._start_animation("executing")
	end)

	events.on(events.events.TOOL_EXECUTED, function(data)
		M._state.status = "idle"
		M._state.message = string.format("Completed %s", data.tool or "tool")
		M._stop_animation()
		-- Clear message after a delay
		vim.defer_fn(function()
			if M._state.status == "idle" then
				M._state.message = ""
			end
		end, 3000)
	end)

	events.on(events.events.TOOL_FAILED, function(data)
		M._state.status = "error"
		M._state.message = string.format("Failed: %s", data.tool or "tool")
		M._stop_animation()
		-- Clear error after a delay
		vim.defer_fn(function()
			if M._state.status == "error" then
				M._state.message = ""
				M._state.status = "idle"
			end
		end, 5000)
	end)

	events.on("Connected", function()
		M._state.status = "connected"
		M._state.message = "Claude connected"
		vim.defer_fn(function()
			if M._state.status == "connected" then
				M._state.message = ""
			end
		end, 3000)
	end)

	events.on("Disconnected", function()
		M._state.status = "disconnected"
		M._state.message = "Claude disconnected"
		M._stop_animation()
	end)

	-- Listen for Claude thinking/processing
	events.on(events.events.PROGRESS_STARTED, function(data)
		M._state.status = "thinking"
		M._state.message = data.message or "Claude is thinking..."
		M._start_animation("thinking")
	end)

	events.on(events.events.PROGRESS_COMPLETED, function(data)
		if M._state.status == "thinking" then
			M._state.status = "idle"
			M._state.message = data.message or ""
			M._stop_animation()
		end
	end)
end

-- Start animation for the current status
function M._start_animation(type)
	M._stop_animation()

	local frames = animations[type] or animations.processing
	M._state.animation_frame = 1

	M._state.animation_timer = vim.loop.new_timer()
	M._state.animation_timer:start(
		0,
		200,
		vim.schedule_wrap(function()
			M._state.animation_frame = (M._state.animation_frame % #frames) + 1
			-- Force statusline redraw
			vim.cmd("redrawstatus")
		end)
	)
end

-- Stop any running animation
function M._stop_animation()
	if M._state.animation_timer then
		M._state.animation_timer:stop()
		M._state.animation_timer:close()
		M._state.animation_timer = nil
	end
end

-- Get the current status string for the statusline
function M.get_status()
	local server = require("claude-code-ide.server").get_server()
	local parts = {}

	-- Server status indicator
	if server and server.running then
		table.insert(parts, "●")
	else
		table.insert(parts, "○")
	end

	-- Add status message with animation
	if M._state.message ~= "" then
		local msg = M._state.message

		-- Add animation frame if animating
		if M._state.animation_timer and animations[M._state.status] then
			local frames = animations[M._state.status]
			local frame = frames[M._state.animation_frame] or frames[1]
			msg = frame .. " " .. msg
		end

		table.insert(parts, msg)
	end

	-- Add tool count if any tools have been executed
	if M._state.tool_count > 0 then
		table.insert(parts, string.format("[%d]", M._state.tool_count))
	end

	-- Join parts with space
	return table.concat(parts, " ")
end

-- Get a minimal status indicator (just the connection status)
function M.get_indicator()
	local server = require("claude-code-ide.server").get_server()
	return server and server.running and "●" or "○"
end

-- Get tool count
function M.get_tool_count()
	return M._state.tool_count
end

-- Reset tool count
function M.reset_tool_count()
	M._state.tool_count = 0
end

-- Cleanup
function M.stop()
	M._stop_animation()
end

-- Reset state for testing
function M._reset()
	M._state = {
		status = "idle",
		message = "",
		tool_count = 0,
		last_tool = nil,
		animation_frame = 1,
		animation_timer = nil,
		initialized = false,
	}
	M._stop_animation()
end

return M
