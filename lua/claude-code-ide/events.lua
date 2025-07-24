-- Event system for claude-code-ide.nvim
-- Uses native Neovim User autocmds for a lightweight pub/sub mechanism

local M = {}
local notify = require("claude-code-ide.ui.notify")

-- Event name prefix for all claude-code-ide events
local EVENT_PREFIX = "ClaudeCode"

-- Sanitize data to remove userdata that can't be serialized
local function sanitize_data(data)
	if type(data) ~= "table" then
		return data
	end
	
	local result = {}
	for k, v in pairs(data) do
		if type(v) == "userdata" then
			-- Skip userdata values
		elseif type(v) == "table" then
			result[k] = sanitize_data(v)
		else
			result[k] = v
		end
	end
	return result
end

-- Emit an event with optional data
---@param event string Event name (will be prefixed with "ClaudeCode:")
---@param data table? Optional data to pass with the event
function M.emit(event, data)
	if not event then
		return
	end

	-- Defer autocmd execution to avoid fast event context issues
	vim.schedule(function()
		vim.api.nvim_exec_autocmds("User", {
			pattern = EVENT_PREFIX .. ":" .. event,
			data = data and sanitize_data(data) or nil,
			modeline = false,
		})
	end)
end

-- Subscribe to an event
---@param event string Event name or pattern (e.g., "ToolExecuted" or "*" for all)
---@param callback function Function to call when event fires, receives data as argument
---@param opts table? Optional options (group, once, desc)
---@return number autocmd_id The ID of the created autocmd
function M.on(event, callback, opts)
	opts = opts or {}

	local pattern = EVENT_PREFIX .. ":" .. event

	return vim.api.nvim_create_autocmd(
		"User",
		vim.tbl_extend("force", {
			pattern = pattern,
			callback = function(args)
				callback(args.data)
			end,
		}, opts)
	)
end

-- Subscribe to an event that fires only once
---@param event string Event name or pattern
---@param callback function Function to call when event fires
---@param opts table? Optional options (group, desc)
---@return number autocmd_id The ID of the created autocmd
function M.once(event, callback, opts)
	opts = opts or {}
	opts.once = true
	return M.on(event, callback, opts)
end

-- Unsubscribe from an event
---@param autocmd_id number The ID returned by on() or once()
function M.off(autocmd_id)
	pcall(vim.api.nvim_del_autocmd, autocmd_id)
end

-- Create an event group for better organization
---@param name string Group name
---@return number group_id The augroup ID
function M.group(name)
	return vim.api.nvim_create_augroup(EVENT_PREFIX .. "_" .. name, { clear = true })
end

-- Clear all event handlers in a group
---@param group_id number The group ID returned by group()
function M.clear_group(group_id)
	vim.api.nvim_clear_autocmds({ group = group_id })
end

-- Common event names as constants for consistency
M.events = {
	-- Connection events
	CONNECTED = "Connected",
	DISCONNECTED = "Disconnected",
	AUTHENTICATION_FAILED = "AuthenticationFailed",

	-- Tool events
	TOOL_EXECUTING = "ToolExecuting",
	TOOL_EXECUTED = "ToolExecuted",
	TOOL_FAILED = "ToolFailed",

	-- Message events
	MESSAGE_RECEIVED = "MessageReceived",
	MESSAGE_SENT = "MessageSent",
	REQUEST_STARTED = "RequestStarted",
	REQUEST_COMPLETED = "RequestCompleted",
	REQUEST_FAILED = "RequestFailed",

	-- File events
	FILE_OPENED = "FileOpened",
	FILE_FOCUSED = "FileFocused",
	DIFF_CREATED = "DiffCreated",

	-- Diagnostic events
	DIAGNOSTICS_REQUESTED = "DiagnosticsRequested",
	DIAGNOSTICS_PROVIDED = "DiagnosticsProvided",

	-- Server events
	SERVER_STARTED = "ServerStarted",
	SERVER_STOPPED = "ServerStopped",
	CLIENT_CONNECTED = "ClientConnected",
	CLIENT_DISCONNECTED = "ClientDisconnected",

	-- Initialization events
	INITIALIZING = "Initializing",
	INITIALIZED = "Initialized",

	-- Conversation events
	CONVERSATION_SAVED = "ConversationSaved",

	-- Progress events
	PROGRESS_STARTED = "ProgressStarted",
	PROGRESS_UPDATED = "ProgressUpdated",
	PROGRESS_COMPLETED = "ProgressCompleted",

	-- UI events
	UI_CONVERSATION_OPENED = "UIConversationOpened",
	UI_CONVERSATION_CLOSED = "UIConversationClosed",
	LAYOUT_CHANGED = "LayoutChanged",
	PANE_OPENED = "PaneOpened",
	PANE_CLOSED = "PaneClosed",

	-- Terminal events
	TERMINAL_STARTED = "TerminalStarted",
	TERMINAL_EXITED = "TerminalExited",

	-- Queue events
	REQUEST_QUEUED = "RequestQueued",
	REQUEST_PROCESSING = "RequestProcessing",
	REQUEST_PROGRESS = "RequestProgress",
	REQUEST_CANCELLED = "RequestCancelled",
	QUEUE_CLEARED = "QueueCleared",
	QUEUE_REQUEST_COMPLETED = "QueueRequestCompleted",
	QUEUE_REQUEST_FAILED = "QueueRequestFailed",

	-- Session events
	SESSION_CREATED = "SessionCreated",
	SESSION_TERMINATED = "SessionTerminated",
	SESSION_CONTEXT_ADDED = "SessionContextAdded",
	SESSION_CONTEXT_REMOVED = "SessionContextRemoved",
}

-- Debug helper to log all events
---@param enabled boolean Enable or disable debug logging
function M.debug(enabled)
	if enabled then
		-- Use native autocmd to capture event pattern correctly
		M._debug_id = vim.api.nvim_create_autocmd("User", {
			pattern = EVENT_PREFIX .. ":*",
			callback = function(args)
				local event_name = args.match:gsub("^" .. EVENT_PREFIX .. ":", "")
				local event_data = args.data

				-- Format the debug message
				local message = string.format("[ClaudeCode Event] %s", event_name)
				if event_data ~= nil then
					message = message .. ": " .. vim.inspect(event_data, { indent = "  " })
				end

				notify.debug(message)
			end,
			desc = "Debug all ClaudeCode events",
		})
	elseif M._debug_id then
		M.off(M._debug_id)
		M._debug_id = nil
	end
end

-- Setup function for initialization
---@param config table? Optional event configuration
function M.setup(config)
	-- Event system is ready to use immediately
	-- No additional setup required for this implementation
	return true
end

return M
