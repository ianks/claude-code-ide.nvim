-- Notification utility for claude-code.nvim
-- Centralizes all notifications using snacks.nvim

local M = {}

-- Cache for notification IDs
local notification_ids = {}

-- Default icons matching plugin style
local icons = {
	error = " ",
	warn = " ",
	info = " ",
	debug = " ",
	trace = " ",
	success = " ",
}

-- Map vim.log.levels to string names
local level_names = {
	[vim.log.levels.ERROR] = "error",
	[vim.log.levels.WARN] = "warn",
	[vim.log.levels.INFO] = "info",
	[vim.log.levels.DEBUG] = "debug",
	[vim.log.levels.TRACE] = "trace",
}

---Send a notification
---@param msg string The message to display
---@param level? number|string vim.log.levels or level name
---@param opts? table Additional options
function M.notify(msg, level, opts)
	opts = opts or {}

	-- Convert numeric levels to string
	if type(level) == "number" then
		level = level_names[level] or "info"
	end

	-- Default to info level
	level = level or "info"

	-- Add default title if not provided
	opts.title = opts.title or "Claude Code"

	-- Use custom icon if provided, otherwise use defaults
	if not opts.icon and icons[level] then
		opts.icon = icons[level]
	end

	-- Check if Snacks is available
	local ok, Snacks = pcall(require, "snacks")
	if ok and Snacks.notify then
		-- Try to call Snacks.notify, but handle different API versions
		local success, result = pcall(function()
			-- Snacks.notify expects (msg, opts) where opts includes level
			local snacks_opts = vim.tbl_extend("force", opts, { level = level })
			return Snacks.notify(msg, snacks_opts)
		end)

		if success then
			return result
		else
			-- If Snacks.notify failed, try alternative API or fall back
			-- Some versions might have different method names
			if Snacks.notifier and Snacks.notifier.notify then
				return Snacks.notifier.notify(msg, level, opts)
			end
			-- Fall through to vim.notify
		end
	end

	-- Fallback to vim.notify
	local vim_level = vim.log.levels.INFO
	for k, v in pairs(level_names) do
		if v == level then
			vim_level = k
			break
		end
	end
	return vim.notify(msg, vim_level, opts)
end

---Show a progress notification
---@param msg string The message to display
---@param opts? table Additional options
---@return any notification_id
function M.progress(msg, opts)
	opts = opts or {}
	opts.timeout = false -- Progress notifications don't timeout
	opts.icon = opts.icon or "⠋"

	-- Add spinner animation
	local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	opts.opts = function(notif)
		notif.icon = frames[math.floor(vim.uv.hrtime() / (1e6 * 80)) % #frames + 1]
	end

	return M.notify(msg, "info", opts)
end

---Hide a notification
---@param id any The notification ID to hide
function M.hide(id)
	local ok, Snacks = pcall(require, "snacks")
	if ok and Snacks.notifier and Snacks.notifier.hide then
		Snacks.notifier.hide(id)
	end
end

---Show notification history
function M.history()
	local ok, Snacks = pcall(require, "snacks")
	if ok and Snacks.notifier and Snacks.notifier.show_history then
		Snacks.notifier.show_history()
	else
		M.notify("Notification history not available", "warn")
	end
end

-- Convenience methods
function M.error(msg, opts)
	return M.notify(msg, "error", opts)
end

function M.warn(msg, opts)
	return M.notify(msg, "warn", opts)
end

function M.info(msg, opts)
	return M.notify(msg, "info", opts)
end

function M.debug(msg, opts)
	return M.notify(msg, "debug", opts)
end

function M.success(msg, opts)
	opts = opts or {}
	opts.icon = opts.icon or icons.success
	return M.notify(msg, "info", opts)
end

return M
