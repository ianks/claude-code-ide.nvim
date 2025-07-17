-- Logging module for claude-code-ide.nvim
-- Provides structured logging to ~/.local/state/nvim/claude-code-ide.log

local M = {}

-- Log levels
M.levels = {
	TRACE = 0,
	DEBUG = 1,
	INFO = 2,
	WARN = 3,
	ERROR = 4,
	OFF = 5,
}

-- Current log level
M.level = M.levels.INFO

-- Log file path
M.log_file = vim.fn.expand("~/.local/state/nvim/claude-code-ide.log")

-- Ensure log directory exists
local log_dir = vim.fn.fnamemodify(M.log_file, ":h")
if vim.fn.isdirectory(log_dir) == 0 then
	vim.fn.mkdir(log_dir, "p")
end

-- Format log message
local function format_message(level, component, message, data)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local level_name = nil

	for name, value in pairs(M.levels) do
		if value == level then
			level_name = name
			break
		end
	end

	local parts = {
		timestamp,
		string.format("[%s]", level_name or "UNKNOWN"),
	}

	if component then
		table.insert(parts, string.format("[%s]", component))
	end

	table.insert(parts, message)

	if data then
		local ok, encoded = pcall(vim.inspect, data, { indent = "  " })
		if ok and encoded ~= "nil" then
			table.insert(parts, "\n" .. encoded)
		end
	end

	return table.concat(parts, " ")
end

-- Write to log file
local function write_log(formatted_message)
	-- Use vim.schedule to avoid blocking
	vim.schedule(function()
		local file = io.open(M.log_file, "a")
		if file then
			file:write(formatted_message .. "\n")
			file:close()
		end
	end)
end

-- Main logging function
local function log(level, component, message, data)
	if level < M.level then
		return
	end

	local formatted = format_message(level, component, message, data)
	write_log(formatted)

	-- Also output to Neovim messages for warnings and errors
	if level >= M.levels.WARN then
		local msg = component and string.format("[%s] %s", component, message) or message
		vim.schedule(function()
			if level == M.levels.WARN then
				vim.notify(msg, vim.log.levels.WARN)
			elseif level >= M.levels.ERROR then
				vim.notify(msg, vim.log.levels.ERROR)
			end
		end)
	end
end

-- Public API functions
function M.trace(component, message, data)
	log(M.levels.TRACE, component, message, data)
end

function M.debug(component, message, data)
	log(M.levels.DEBUG, component, message, data)
end

function M.info(component, message, data)
	log(M.levels.INFO, component, message, data)
end

function M.warn(component, message, data)
	log(M.levels.WARN, component, message, data)
end

function M.error(component, message, data)
	log(M.levels.ERROR, component, message, data)
end

-- Set log level
function M.set_level(level)
	if type(level) == "string" then
		level = M.levels[level:upper()]
	end

	if level and level >= 0 and level <= M.levels.OFF then
		M.level = level
		M.info("LOG", "Log level set to " .. level)
	end
end

-- Get current log level name
function M.get_level()
	for name, value in pairs(M.levels) do
		if value == M.level then
			return name
		end
	end
	return "UNKNOWN"
end

-- Clear log file
function M.clear()
	local file = io.open(M.log_file, "w")
	if file then
		file:close()
		M.info("LOG", "Log file cleared")
	end
end

-- Get log file path
function M.get_file()
	return M.log_file
end

-- Tail the log file (useful for debugging)
function M.tail(lines)
	lines = lines or 50
	local content = vim.fn.system(string.format("tail -n %d %s", lines, M.log_file))
	return vim.split(content, "\n")
end

-- Open log file in new buffer
function M.open()
	vim.cmd("edit " .. M.log_file)
	vim.cmd("normal! G")
	vim.bo.autoread = true

	-- Set up auto-refresh
	vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
		buffer = 0,
		callback = function()
			vim.cmd("checktime")
		end,
	})
end

return M
