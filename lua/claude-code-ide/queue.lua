-- Request queue and rate limiting for claude-code-ide.nvim
-- Ensures requests are processed in order and respects rate limits

local notify = require("claude-code-ide.ui.notify")
local log = require("claude-code-ide.log")
local events = require("claude-code-ide.events")

local M = {}

-- Default configuration
local default_config = {
	max_concurrent = 3, -- Maximum concurrent requests
	max_queue_size = 100, -- Maximum queue size
	rate_limit = {
		enabled = true,
		max_requests = 30, -- Max requests per window
		window_ms = 60000, -- Time window in milliseconds (1 minute)
		retry_after_ms = 5000, -- Retry after this delay when rate limited
	},
	timeout_ms = 30000, -- Request timeout in milliseconds
	priorities = {
		high = 3,
		normal = 2,
		low = 1,
	},
}

-- Queue class
local Queue = {}
Queue.__index = Queue

function Queue.new(config)
	local self = setmetatable({}, Queue)

	self.config = vim.tbl_deep_extend("force", default_config, config or {})
	self.queue = {} -- Priority queue
	self.processing = {} -- Currently processing requests
	self.rate_limiter = {
		requests = {}, -- Timestamp of each request
		blocked_until = nil, -- When rate limiting will be lifted
	}
	self.stats = {
		queued = 0,
		processed = 0,
		failed = 0,
		rate_limited = 0,
	}

	return self
end

-- Add request to queue
---@param request table Request object with handler, priority, etc.
---@return string|nil Request ID or nil if queue is full
function Queue:enqueue(request)
	if #self.queue >= self.config.max_queue_size then
		local config = require("claude-code-ide.config")
		if config.get("debug") then
			notify.error("Request queue is full", {
				title = "Claude Code Queue",
				timeout = 3000,
			})
		end
		return nil
	end

	-- Generate request ID
	local id = string.format("%s_%d_%d", request.method or "unknown", vim.loop.now(), math.random(1000, 9999))

	-- Create queue entry
	local entry = {
		id = id,
		request = request,
		priority = self.config.priorities[request.priority] or self.config.priorities.normal,
		queued_at = vim.loop.now(),
		retries = 0,
		status = "queued",
	}

	-- Insert into priority queue
	local inserted = false
	for i, item in ipairs(self.queue) do
		if entry.priority > item.priority then
			table.insert(self.queue, i, entry)
			inserted = true
			break
		end
	end

	if not inserted then
		table.insert(self.queue, entry)
	end

	self.stats.queued = self.stats.queued + 1

	-- Emit event
	events.emit(events.events.REQUEST_QUEUED, {
		id = id,
		method = request.method,
		priority = request.priority,
		queue_size = #self.queue,
	})

	log.debug("QUEUE", "Request queued", {
		id = id,
		method = request.method,
		priority = request.priority,
		queue_position = #self.queue,
	})

	-- Try to process immediately
	vim.schedule(function()
		self:process_next()
	end)

	return id
end

-- Check if we're rate limited
function Queue:is_rate_limited()
	if not self.config.rate_limit.enabled then
		return false
	end

	local now = vim.loop.now()

	-- Check if we're in a blocked period
	if self.rate_limiter.blocked_until and now < self.rate_limiter.blocked_until then
		return true
	end

	-- Clean up old requests outside the window
	local window_start = now - self.config.rate_limit.window_ms
	local active_requests = {}

	for _, timestamp in ipairs(self.rate_limiter.requests) do
		if timestamp > window_start then
			table.insert(active_requests, timestamp)
		end
	end

	self.rate_limiter.requests = active_requests

	-- Check if we've exceeded the limit
	return #self.rate_limiter.requests >= self.config.rate_limit.max_requests
end

-- Process next request in queue
function Queue:process_next()
	-- Check if we can process more requests
	if vim.tbl_count(self.processing) >= self.config.max_concurrent then
		return
	end

	-- Check if we're rate limited
	if self:is_rate_limited() then
		self.stats.rate_limited = self.stats.rate_limited + 1

		-- Set blocked period
		local now = vim.loop.now()
		self.rate_limiter.blocked_until = now + self.config.rate_limit.retry_after_ms

		-- Schedule retry
		vim.defer_fn(function()
			self:process_next()
		end, self.config.rate_limit.retry_after_ms)

		local config = require("claude-code-ide.config")
		if config.get("debug") then
			notify.warn(
				"Rate limited. Retrying in " .. math.floor(self.config.rate_limit.retry_after_ms / 1000) .. "s",
				{
					title = "Claude Code Queue",
				}
			)
		end

		return
	end

	-- Get next request from queue
	if #self.queue == 0 then
		return
	end

	local entry = table.remove(self.queue, 1)
	entry.status = "processing"
	entry.started_at = vim.loop.now()

	-- Add to processing list
	self.processing[entry.id] = entry

	-- Record request for rate limiting
	table.insert(self.rate_limiter.requests, entry.started_at)

	-- Emit event
	events.emit(events.events.REQUEST_PROCESSING, {
		id = entry.id,
		method = entry.request.method,
		wait_time = entry.started_at - entry.queued_at,
	})

	-- Set up timeout
	local timeout_timer = vim.loop.new_timer()
	entry.timeout_timer = timeout_timer

	timeout_timer:start(
		self.config.timeout_ms,
		0,
		vim.schedule_wrap(function()
			if self.processing[entry.id] then
				self:handle_timeout(entry.id)
			end
		end)
	)

	-- Execute request handler asynchronously
	vim.schedule(function()
		local success, result = pcall(function()
			return entry.request.handler(entry.request.params or {}, {
				id = entry.id,
				on_progress = function(progress)
					self:update_progress(entry.id, progress)
				end,
			})
		end)

		-- Cancel timeout
		if entry.timeout_timer and not entry.timeout_timer:is_closing() then
			entry.timeout_timer:close()
		end
		entry.timeout_timer = nil

		-- Handle result
		if success then
			self:complete_request(entry.id, result)
		else
			self:fail_request(entry.id, result)
		end
	end)

	-- Process next request
	vim.schedule(function()
		self:process_next()
	end)
end

-- Update request progress
function Queue:update_progress(id, progress)
	local entry = self.processing[id]
	if not entry then
		return
	end

	entry.progress = progress

	events.emit(events.events.REQUEST_PROGRESS, {
		id = id,
		progress = progress,
	})
end

-- Complete a request
function Queue:complete_request(id, result)
	local entry = self.processing[id]
	if not entry then
		return
	end

	-- Remove from processing
	self.processing[id] = nil

	-- Update stats
	self.stats.processed = self.stats.processed + 1
	entry.status = "completed"
	entry.completed_at = vim.loop.now()
	entry.duration = entry.completed_at - entry.started_at

	-- Call callback if provided
	if entry.request.callback then
		vim.schedule(function()
			entry.request.callback(nil, result)
		end)
	end

	-- Emit event
	events.emit(events.events.REQUEST_COMPLETED, {
		id = id,
		method = entry.request.method,
		duration = entry.duration,
		result = result,
	})

	log.debug("QUEUE", "Request completed", {
		id = id,
		duration = entry.duration,
	})

	-- Process next request in queue
	vim.schedule(function()
		self:process_next()
	end)
end

-- Fail a request
function Queue:fail_request(id, error)
	local entry = self.processing[id]
	if not entry then
		return
	end

	-- Check if we should retry
	if entry.retries < (entry.request.max_retries or 0) then
		entry.retries = entry.retries + 1
		entry.status = "retrying"

		-- Remove from processing
		self.processing[id] = nil

		-- Re-queue with higher priority
		entry.priority = entry.priority + 1
		table.insert(self.queue, 1, entry)

		log.debug("QUEUE", "Retrying request", {
			id = id,
			retries = entry.retries,
			error = error,
		})

		-- Process next
		vim.defer_fn(function()
			self:process_next()
		end, 1000 * entry.retries) -- Exponential backoff

		return
	end

	-- Remove from processing
	self.processing[id] = nil

	-- Update stats
	self.stats.failed = self.stats.failed + 1
	entry.status = "failed"
	entry.failed_at = vim.loop.now()
	entry.error = error

	-- Call callback if provided
	if entry.request.callback then
		vim.schedule(function()
			entry.request.callback(error, nil)
		end)
	end

	-- Emit event
	events.emit(events.events.REQUEST_FAILED, {
		id = id,
		method = entry.request.method,
		error = error,
		retries = entry.retries,
	})

	local config = require("claude-code-ide.config")
	if config.get("debug") then
		notify.error("Request failed: " .. (entry.request.method or "unknown"), {
			title = "Claude Code Queue",
			timeout = 3000,
		})
	end

	log.error("QUEUE", "Request failed", {
		id = id,
		error = error,
		retries = entry.retries,
	})

	-- Process next request in queue
	vim.schedule(function()
		self:process_next()
	end)
end

-- Handle request timeout
function Queue:handle_timeout(id)
	local entry = self.processing[id]
	if entry and entry.timeout_timer then
		if not entry.timeout_timer:is_closing() then
			entry.timeout_timer:close()
		end
		entry.timeout_timer = nil
	end
	self:fail_request(id, "Request timed out")
end

-- Cancel a request
function Queue:cancel(id)
	-- Check if in queue
	for i, entry in ipairs(self.queue) do
		if entry.id == id then
			table.remove(self.queue, i)

			-- Call callback if provided
			if entry.request.callback then
				vim.schedule(function()
					entry.request.callback("Cancelled", nil)
				end)
			end

			events.emit(events.events.REQUEST_CANCELLED, {
				id = id,
				method = entry.request.method,
			})

			return true
		end
	end

	-- Check if processing
	local entry = self.processing[id]
	if entry then
		-- We can't really cancel an in-progress request,
		-- but we can mark it for cancellation
		entry.cancelled = true
		return true
	end

	return false
end

-- Get queue status
function Queue:get_status()
	return {
		queue_size = #self.queue,
		processing = vim.tbl_count(self.processing),
		max_concurrent = self.config.max_concurrent,
		rate_limited = self:is_rate_limited(),
		stats = vim.deepcopy(self.stats),
	}
end

-- Clear the queue
function Queue:clear()
	local cancelled_count = #self.queue

	-- Cancel all queued requests
	for _, entry in ipairs(self.queue) do
		if entry.request.callback then
			vim.schedule(function()
				entry.request.callback("Queue cleared", nil)
			end)
		end
	end

	self.queue = {}

	events.emit(events.events.QUEUE_CLEARED, {
		cancelled_count = cancelled_count,
	})
end

-- Module functions
local queue_instance = nil

function M.init(config)
	queue_instance = Queue.new(config)
	return queue_instance
end

function M.enqueue(request)
	if not queue_instance then
		queue_instance = Queue.new({})
	end
	return queue_instance:enqueue(request)
end

function M.cancel(id)
	if not queue_instance then
		return false
	end
	return queue_instance:cancel(id)
end

function M.get_status()
	if not queue_instance then
		return {
			queue_size = 0,
			processing = 0,
			max_concurrent = default_config.max_concurrent,
			rate_limited = false,
			stats = {
				queued = 0,
				processed = 0,
				failed = 0,
				rate_limited = 0,
			},
		}
	end
	return queue_instance:get_status()
end

function M.clear()
	if queue_instance then
		queue_instance:clear()
	end
end

-- Export Queue class for testing
M.Queue = Queue

return M
