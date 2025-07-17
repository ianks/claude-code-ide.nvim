-- Progress indicators and animations for claude-code-ide.nvim
-- Provides buttery smooth progress animations using snacks.nvim

local M = {}
local notify = require("claude-code-ide.ui.notify")
local events = require("claude-code-ide.events")

-- Animation presets
M.animations = {
	-- Classic spinner animations
	dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	dots2 = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" },
	dots3 = { "⠋", "⠙", "⠚", "⠞", "⠖", "⠦", "⠴", "⠲", "⠳", "⠓" },
	line = { "⎯", "⎯", "⎻", "⎼", "⎽", "⎼", "⎻" },
	line2 = { "⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈" },
	pipe = { "┤", "┘", "┴", "└", "├", "┌", "┬", "┐" },
	star = { "✶", "✸", "✹", "✺", "✹", "✸" },
	flip = { "◐", "◓", "◑", "◒" },
	hamburger = { "☱", "☲", "☴", "☲" },
	grow = { "▁", "▃", "▄", "▅", "▆", "▇", "▆", "▅", "▄", "▃" },
	balloon = { " ", ".", "o", "O", "@", "*", " " },
	noise = { "▓", "▒", "░", "▒" },
	bounce = { "⠁", "⠂", "⠄", "⠂" },
	bouncingBar = {
		"[    ]",
		"[=   ]",
		"[==  ]",
		"[=== ]",
		"[ ===]",
		"[  ==]",
		"[   =]",
		"[    ]",
		"[   =]",
		"[  ==]",
		"[ ===]",
		"[====]",
		"[=== ]",
		"[==  ]",
		"[=   ]",
	},
	clock = { "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛" },
	earth = { "🌍", "🌎", "🌏" },
	moon = { "🌑", "🌒", "🌓", "🌔", "🌕", "🌖", "🌗", "🌘" },

	-- Modern animations
	ai_thinking = { "🤔", "🧠", "💭", "✨", "💡" },
	ai_processing = { "◐", "◓", "◑", "◒" },
	ai_writing = { "✍️ ", "✍️.", "✍️..", "✍️..." },

	-- Code-specific animations
	code_analysis = { "󰁔", "󰁕", "󰁖", "󰁗", "󰁘", "󰁙", "󰁚", "󰁛", "󰁜", "󰁝" },
	compile = { "⚙️ ", "⚙️.", "⚙️..", "⚙️..." },
	search = { "🔍", "🔎", "🔍", "🔎" },
}

-- Active progress indicators
local active_progress = {}

-- Progress indicator class
local Progress = {}
Progress.__index = Progress

-- Create a new progress indicator
---@param opts table Options for the progress indicator
---@return table Progress instance
function Progress:new(opts)
	local instance = setmetatable({}, self)

	instance.id = opts.id or vim.fn.tempname()
	instance.message = opts.message or "Processing..."
	instance.animation = opts.animation or "dots"
	instance.frame_rate = opts.frame_rate or 80 -- milliseconds per frame
	instance.timeout = opts.timeout
	instance.style = opts.style or {}
	instance.on_complete = opts.on_complete
	instance.start_time = vim.loop.now()
	instance.frame_index = 1
	instance.notification = nil
	instance.timer = nil
	instance.completed = false

	-- Additional options
	instance.show_elapsed = opts.show_elapsed or false
	instance.show_percentage = opts.show_percentage or false
	instance.percentage = 0

	return instance
end

-- Start the progress animation
function Progress:start()
	local Snacks = require("snacks")
	local frames = M.animations[self.animation] or M.animations.dots

	-- Initial notification
	local opts = vim.tbl_deep_extend("force", {
		title = self.style.title or "Claude Processing",
		timeout = false,
		icon = frames[1],
	}, self.style)

	self.notification = Snacks.notify(self:format_message(), "info", opts)

	-- Start animation timer
	self.timer = vim.loop.new_timer()
	self.timer:start(
		0,
		self.frame_rate,
		vim.schedule_wrap(function()
			if self.completed then
				self:stop()
				return
			end

			-- Update frame
			self.frame_index = (self.frame_index % #frames) + 1
			local frame = frames[self.frame_index]

			-- Update notification
			if self.notification then
				self.notification.icon = frame
				self.notification:update(self:format_message(), "info")
			end

			-- Check timeout
			if self.timeout then
				local elapsed = vim.loop.now() - self.start_time
				if elapsed > self.timeout then
					self:complete("Timed out")
				end
			end
		end)
	)

	-- Emit event
	events.emit(events.events.PROGRESS_STARTED, {
		id = self.id,
		message = self.message,
	})

	return self
end

-- Format the message with elapsed time and percentage
function Progress:format_message()
	local msg = self.message

	if self.show_elapsed then
		local elapsed = math.floor((vim.loop.now() - self.start_time) / 1000)
		local minutes = math.floor(elapsed / 60)
		local seconds = elapsed % 60
		if minutes > 0 then
			msg = msg .. string.format(" (%dm %ds)", minutes, seconds)
		else
			msg = msg .. string.format(" (%ds)", seconds)
		end
	end

	if self.show_percentage and self.percentage > 0 then
		msg = msg .. string.format(" [%d%%]", self.percentage)
	end

	return msg
end

-- Update progress percentage
---@param percentage number Progress percentage (0-100)
function Progress:update_percentage(percentage)
	self.percentage = math.min(100, math.max(0, percentage))
	if self.notification then
		self.notification:update(self:format_message(), "info")
	end
end

-- Update progress message
---@param message string New message
function Progress:update_message(message)
	self.message = message
	if self.notification then
		self.notification:update(self:format_message(), "info")
	end
end

-- Complete the progress
---@param message? string Completion message
---@param success? boolean Whether the operation was successful
function Progress:complete(message, success)
	if self.completed then
		return
	end

	self.completed = true

	-- Stop timer
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end

	-- Update notification
	if self.notification then
		local Snacks = require("snacks")
		local final_message = message or "Complete!"
		local level = success == false and "error" or "success"
		local icon = success == false and "❌" or "✅"

		-- Hide current notification
		Snacks.notifier.hide(self.notification)

		-- Show completion notification
		Snacks.notify(final_message, level, {
			title = self.style.title or "Claude",
			icon = icon,
			timeout = 3000,
		})
	end

	-- Emit event
	events.emit(events.events.PROGRESS_COMPLETED, {
		id = self.id,
		message = message,
		success = success,
		duration = vim.loop.now() - self.start_time,
	})

	-- Callback
	if self.on_complete then
		self.on_complete(success)
	end

	-- Remove from active
	active_progress[self.id] = nil
end

-- Stop the progress without completion message
function Progress:stop()
	if self.timer then
		self.timer:stop()
		self.timer:close()
		self.timer = nil
	end

	if self.notification then
		local Snacks = require("snacks")
		Snacks.notifier.hide(self.notification)
		self.notification = nil
	end

	active_progress[self.id] = nil
end

-- Public API

-- Show a progress indicator
---@param message string Progress message
---@param opts? table Options
---@return table Progress instance
function M.show(message, opts)
	opts = opts or {}
	opts.message = message

	local progress = Progress:new(opts)
	progress:start()

	active_progress[progress.id] = progress

	return progress
end

-- Show progress with percentage
---@param message string Progress message
---@param opts? table Options
---@return table Progress instance
function M.show_with_percentage(message, opts)
	opts = opts or {}
	opts.message = message
	opts.show_percentage = true

	return M.show(message, opts)
end

-- Show progress with elapsed time
---@param message string Progress message
---@param opts? table Options
---@return table Progress instance
function M.show_with_timer(message, opts)
	opts = opts or {}
	opts.message = message
	opts.show_elapsed = true

	return M.show(message, opts)
end

-- Show a simple spinner
---@param message string Progress message
---@return table Progress instance
function M.spinner(message)
	return M.show(message, { animation = "dots" })
end

-- Show AI thinking animation
---@param message? string Progress message
---@return table Progress instance
function M.ai_thinking(message)
	return M.show(message or "Claude is thinking...", {
		animation = "ai_thinking",
		frame_rate = 500,
		style = { title = "Claude AI" },
	})
end

-- Show code analysis animation
---@param message? string Progress message
---@return table Progress instance
function M.code_analysis(message)
	return M.show(message or "Analyzing code...", {
		animation = "code_analysis",
		style = { title = "Code Analysis" },
	})
end

-- Stop all active progress indicators
function M.stop_all()
	for _, progress in pairs(active_progress) do
		progress:stop()
	end
	active_progress = {}
end

-- Get active progress by ID
---@param id string Progress ID
---@return table? Progress instance
function M.get(id)
	return active_progress[id]
end

-- Multi-step progress indicator
---@param steps table Array of step descriptions
---@param opts? table Options
---@return table MultiStepProgress instance
function M.multi_step(steps, opts)
	opts = opts or {}

	local multi = {
		steps = steps,
		current_step = 0,
		progress = nil,
		opts = opts,
	}

	function multi:next()
		self.current_step = self.current_step + 1

		if self.current_step > #self.steps then
			if self.progress then
				self.progress:complete("All steps completed!", true)
			end
			return false
		end

		local step = self.steps[self.current_step]
		local message = string.format("[%d/%d] %s", self.current_step, #self.steps, step)

		if self.progress then
			self.progress:update_message(message)
			self.progress:update_percentage((self.current_step - 1) / #self.steps * 100)
		else
			self.progress = M.show_with_percentage(message, self.opts)
		end

		return true
	end

	function multi:complete(success)
		if self.progress then
			self.progress:complete(success and "All steps completed!" or "Process failed", success)
		end
	end

	return multi
end

return M
