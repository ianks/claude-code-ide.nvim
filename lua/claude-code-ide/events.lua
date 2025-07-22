-- Event system for claude-code-ide.nvim
-- Production-ready event system with error boundaries, structured logging, and comprehensive observability

local M = {}

-- Configuration constants
local CONFIG = {
	EVENT_PREFIX = "ClaudeCode",
	MAX_LISTENERS = 1000,
	EVENT_TIMEOUT_MS = 5000,
	DEBUG_BUFFER_SIZE = 100,
	ASYNC_QUEUE_SIZE = 500,
}

-- Module state with proper lifecycle management
local State = {
	initialized = false,
	listeners = {},
	listener_count = 0,
	debug_mode = false,
	debug_buffer = {},
	async_queue = {},
	stats = {
		events_emitted = 0,
		events_handled = 0,
		errors = 0,
		async_events = 0,
	},
	timers = {},
	config = nil,
}

-- Load dependencies with graceful fallbacks
local deps = {}
local function load_dependency(name, required)
	local ok, module = pcall(require, name)
	if ok then
		deps[name] = module
		return module
	elseif required then
		error(string.format("Critical dependency missing: %s", name))
	else
		return nil
	end
end

-- Optional dependencies
local log = load_dependency("claude-code-ide.log", false)

-- Event validation utilities
local function validate_event_name(event)
	if type(event) ~= "string" or #event == 0 then
		return false, "Event name must be a non-empty string"
	end

	if #event > 100 then
		return false, "Event name too long (max 100 characters)"
	end

	if not event:match("^[%w_.-]+$") then
		return false, "Event name contains invalid characters (use alphanumeric, _, ., -)"
	end

	return true, nil
end

local function validate_callback(callback)
	if type(callback) ~= "function" then
		return false, "Callback must be a function"
	end
	return true, nil
end

-- Safe logging wrapper
local function safe_log(level, component, message, data)
	if log and log[level] then
		local ok, err = pcall(log[level], log, component, message, data)
		if not ok then
			vim.notify(string.format("Logging error: %s", err), vim.log.levels.WARN)
		end
	end
end

-- Debug event tracking
local function add_debug_entry(event_type, event, data, error_msg)
	if not State.debug_mode then
		return
	end

	local entry = {
		timestamp = vim.loop.now(),
		type = event_type,
		event = event,
		data_type = type(data),
		data_size = data and (type(data) == "table" and vim.tbl_count(data) or 1) or 0,
		error = error_msg,
	}

	table.insert(State.debug_buffer, entry)

	-- Keep buffer size limited
	if #State.debug_buffer > CONFIG.DEBUG_BUFFER_SIZE then
		table.remove(State.debug_buffer, 1)
	end
end

-- Generate full event pattern with prefix
local function get_event_pattern(event)
	return CONFIG.EVENT_PREFIX .. ":" .. event
end

-- Async event processing queue
local function process_async_queue()
	local queue = State.async_queue
	State.async_queue = {}

	for _, item in ipairs(queue) do
		local ok, err = pcall(function()
			vim.api.nvim_exec_autocmds("User", {
				pattern = item.pattern,
				data = item.data,
				modeline = false,
			})
		end)

		if ok then
			State.stats.events_handled = State.stats.events_handled + 1
			add_debug_entry("async_processed", item.event, item.data)
		else
			State.stats.errors = State.stats.errors + 1
			add_debug_entry("async_error", item.event, item.data, err)
			safe_log("error", "EVENTS", "Async event processing failed", {
				event = item.event,
				error = err,
			})
		end
	end
end

-- Setup async processing timer
local function setup_async_processing()
	local timer = vim.loop.new_timer()
	timer:start(100, 100, vim.schedule_wrap(process_async_queue))
	State.timers.async = timer

	return function()
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end
end

-- Emit an event with comprehensive error handling
---@param event string Event name
---@param data table? Optional data to pass with the event
---@param opts table? Options (async, timeout, priority)
function M.emit(event, data, opts)
	opts = opts or {}

	-- Validate inputs
	local valid, err = validate_event_name(event)
	if not valid then
		error("Invalid event name: " .. err)
	end

	-- Increment stats
	State.stats.events_emitted = State.stats.events_emitted + 1

	-- Add debug tracking
	add_debug_entry("emit", event, data)

	-- Prepare event pattern
	local pattern = get_event_pattern(event)

	-- Handle async events
	if opts.async or State.config.async then
		State.stats.async_events = State.stats.async_events + 1

		-- Add to async queue with bounds checking
		if #State.async_queue >= CONFIG.ASYNC_QUEUE_SIZE then
			safe_log("warn", "EVENTS", "Async queue full, dropping event", { event = event })
			return false
		end

		table.insert(State.async_queue, {
			event = event,
			pattern = pattern,
			data = data,
			timestamp = vim.loop.now(),
		})

		return true
	end

	-- Synchronous event emission with error boundaries
	local ok, result = pcall(function()
		vim.api.nvim_exec_autocmds("User", {
			pattern = pattern,
			data = data,
			modeline = false,
		})
	end)

	if ok then
		State.stats.events_handled = State.stats.events_handled + 1
		safe_log("debug", "EVENTS", "Event emitted", { event = event, listeners = State.listener_count })
	else
		State.stats.errors = State.stats.errors + 1
		add_debug_entry("error", event, data, result)
		safe_log("error", "EVENTS", "Event emission failed", {
			event = event,
			error = result,
		})

		-- Don't propagate errors to caller in production
		if State.config and State.config.debug then
			error(string.format("Event emission failed (%s): %s", event, result))
		end
	end

	return ok
end

-- Subscribe to an event with comprehensive options
---@param event string Event name or pattern
---@param callback function Function to call when event fires
---@param opts table? Options (group, once, desc, priority, timeout)
---@return number autocmd_id The ID of the created autocmd
function M.on(event, callback, opts)
	opts = opts or {}

	-- Validate inputs
	local valid, err = validate_event_name(event)
	if not valid then
		error("Invalid event name: " .. err)
	end

	local cb_valid, cb_err = validate_callback(callback)
	if not cb_valid then
		error("Invalid callback: " .. cb_err)
	end

	-- Check listener limits
	if State.listener_count >= CONFIG.MAX_LISTENERS then
		error("Maximum number of event listeners exceeded")
	end

	-- Create safe callback wrapper with error boundaries
	local safe_callback = function(args)
		local start_time = vim.loop.hrtime()
		local success = false
		local error_msg = nil

		local ok, result = pcall(function()
			callback(args.data)
			success = true
		end)

		local duration_ns = vim.loop.hrtime() - start_time

		if not ok then
			error_msg = result
			State.stats.errors = State.stats.errors + 1
			add_debug_entry("callback_error", event, args.data, result)
			safe_log("error", "EVENTS", "Event callback failed", {
				event = event,
				error = result,
				duration_ms = duration_ns / 1e6,
			})
		else
			add_debug_entry("callback_success", event, args.data)
			safe_log("trace", "EVENTS", "Event callback completed", {
				event = event,
				duration_ms = duration_ns / 1e6,
			})
		end

		-- Emit callback completion event for monitoring
		if State.config and State.config.trace_callbacks then
			vim.schedule(function()
				M.emit("CallbackCompleted", {
					event = event,
					success = success,
					duration_ms = duration_ns / 1e6,
					error = error_msg,
				}, { async = true })
			end)
		end
	end

	-- Create autocmd with comprehensive options
	local autocmd_opts = vim.tbl_extend("force", {
		pattern = get_event_pattern(event),
		callback = safe_callback,
		desc = opts.desc or ("Claude Code: " .. event),
	}, opts)

	-- Remove our custom options that aren't valid for nvim_create_autocmd
	autocmd_opts.priority = nil
	autocmd_opts.timeout = nil

	local autocmd_id = vim.api.nvim_create_autocmd("User", autocmd_opts)

	-- Track listener
	State.listener_count = State.listener_count + 1
	State.listeners[autocmd_id] = {
		event = event,
		created_at = vim.loop.now(),
		opts = opts,
	}

	safe_log("debug", "EVENTS", "Event listener registered", {
		event = event,
		autocmd_id = autocmd_id,
		total_listeners = State.listener_count,
	})

	return autocmd_id
end

-- Subscribe to an event that fires only once
---@param event string Event name
---@param callback function Callback function
---@param opts table? Additional options
---@return number autocmd_id
function M.once(event, callback, opts)
	opts = opts or {}
	opts.once = true
	return M.on(event, callback, opts)
end

-- Unsubscribe from an event
---@param autocmd_id number Autocmd ID returned by on()
---@return boolean success
function M.off(autocmd_id)
	if not autocmd_id or not State.listeners[autocmd_id] then
		return false
	end

	local ok, err = pcall(vim.api.nvim_del_autocmd, autocmd_id)
	if ok then
		State.listener_count = State.listener_count - 1
		State.listeners[autocmd_id] = nil
		safe_log("debug", "EVENTS", "Event listener unregistered", { autocmd_id = autocmd_id })
		return true
	else
		safe_log("warn", "EVENTS", "Failed to unregister listener", {
			autocmd_id = autocmd_id,
			error = err,
		})
		return false
	end
end

-- Create event group for batch management
---@param name string Group name
---@return number group_id
function M.group(name)
	local group_id = vim.api.nvim_create_augroup(CONFIG.EVENT_PREFIX .. "_" .. name, { clear = true })
	safe_log("debug", "EVENTS", "Event group created", { name = name, group_id = group_id })
	return group_id
end

-- Clear all event handlers in a group
---@param group_id number The group ID returned by group()
function M.clear_group(group_id)
	local ok, err = pcall(vim.api.nvim_clear_autocmds, { group = group_id })
	if ok then
		safe_log("debug", "EVENTS", "Event group cleared", { group_id = group_id })
	else
		safe_log("warn", "EVENTS", "Failed to clear event group", {
			group_id = group_id,
			error = err,
		})
	end
end

-- Enable/disable debug mode
---@param enabled boolean Enable debug mode
function M.debug(enabled)
	State.debug_mode = enabled
	if enabled then
		safe_log("info", "EVENTS", "Debug mode enabled")
	else
		State.debug_buffer = {}
		safe_log("info", "EVENTS", "Debug mode disabled")
	end
end

-- Get debug information
---@return table debug_info
function M.get_debug_info()
	return {
		enabled = State.debug_mode,
		buffer = vim.deepcopy(State.debug_buffer),
		stats = vim.deepcopy(State.stats),
		listeners = vim.tbl_count(State.listeners),
		config = State.config,
	}
end

-- Get event system statistics
---@return table stats
function M.get_stats()
	return vim.tbl_extend("force", vim.deepcopy(State.stats), {
		active_listeners = State.listener_count,
		async_queue_size = #State.async_queue,
		debug_buffer_size = #State.debug_buffer,
		uptime_ms = vim.loop.now() - (State.start_time or 0),
	})
end

-- Setup event system with configuration
---@param config table? Configuration options
function M.setup(config)
	if State.initialized then
		vim.notify("Event system already initialized", vim.log.levels.WARN)
		return
	end

	State.config = vim.tbl_extend("force", {
		async = true,
		debug = false,
		trace_callbacks = false,
		max_listeners = CONFIG.MAX_LISTENERS,
		timeout_ms = CONFIG.EVENT_TIMEOUT_MS,
	}, config or {})

	State.start_time = vim.loop.now()

	-- Setup async processing
	local cleanup_async = setup_async_processing()

	-- Register cleanup on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			M.shutdown()
		end,
		desc = "Claude Code Events cleanup",
	})

	State.initialized = true
	safe_log("info", "EVENTS", "Event system initialized", {
		config = State.config,
		listeners = State.listener_count,
	})

	-- Emit initialization event
	vim.defer_fn(function()
		M.emit("EventSystemInitialized", State.config, { async = true })
	end, 10)
end

-- Shutdown event system and cleanup resources
function M.shutdown()
	if not State.initialized then
		return
	end

	safe_log("info", "EVENTS", "Shutting down event system", {
		stats = State.stats,
		listeners = State.listener_count,
	})

	-- Stop all timers
	for name, timer in pairs(State.timers) do
		if timer and not timer:is_closing() then
			timer:stop()
			timer:close()
		end
	end

	-- Process remaining async events
	if #State.async_queue > 0 then
		process_async_queue()
	end

	-- Clear all listeners
	for autocmd_id, _ in pairs(State.listeners) do
		M.off(autocmd_id)
	end

	State.initialized = false
	State.listeners = {}
	State.listener_count = 0
	State.async_queue = {}
	State.timers = {}
end

-- Health check for event system
function M.health_check()
	return {
		healthy = State.initialized and State.stats.errors < 100,
		details = {
			initialized = State.initialized,
			listeners = State.listener_count,
			stats = State.stats,
			queue_size = #State.async_queue,
		},
	}
end

-- Common event names as constants for consistency
M.events = {
	-- Lifecycle events
	INITIALIZED = "Initialized",
	SHUTDOWN = "Shutdown",

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

	-- Configuration events
	CONFIGURATION_CHANGED = "ConfigurationChanged",
	CONFIGURATION_SETUP = "ConfigurationSetup",

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
	TERMINAL_CREATED = "TerminalCreated",
	TERMINAL_SHOWN = "TerminalShown",
	TERMINAL_HIDDEN = "TerminalHidden",

	-- Queue events
	REQUEST_QUEUED = "RequestQueued",
	REQUEST_PROCESSING = "RequestProcessing",
	REQUEST_PROGRESS = "RequestProgress",
	REQUEST_CANCELLED = "RequestCancelled",

	-- Health events
	HEALTH_CHECK = "HealthCheck",

	-- Event system events
	EVENT_SYSTEM_INITIALIZED = "EventSystemInitialized",
	CALLBACK_COMPLETED = "CallbackCompleted",
}

return M
