-- Editor notifications to Claude
-- Sends notifications about editor state changes without tracking state

local M = {}

local log = require("claude-code-ide.log")

-- Send notification to all connected Claude clients
---@param method string Notification method name
---@param params table? Notification parameters
function M.send_notification(method, params)
	log.info("NOTIFICATIONS", "Attempting to send notification", {
		method = method,
		params = params
	})

	-- Get the server module
	local server = require("claude-code-ide.server")
	local current_server = server.get_server()

	if not current_server then
		log.warn("NOTIFICATIONS", "No server instance", { method = method })
		return
	end

	if not current_server.clients then
		log.warn("NOTIFICATIONS", "No clients table", { method = method })
		return
	end

	local client_count = vim.tbl_count(current_server.clients)
	log.info("NOTIFICATIONS", "Connected clients", {
		count = client_count,
		method = method
	})

	-- Create notification message
	local message = {
		jsonrpc = "2.0",
		method = method,
		params = params or vim.empty_dict(),
	}

	local json = vim.json.encode(message)
	log.debug("NOTIFICATIONS", "Notification JSON", {
		json = json,
		method = method
	})

	-- Send to all connected clients
	local websocket = require("claude-code-ide.server.websocket")
	for client_id, client in pairs(current_server.clients) do
		local ok, err = pcall(websocket.send_text, client, json)
		if ok then
			log.info("NOTIFICATIONS", "Sent notification successfully", {
				client_id = client_id,
				method = method,
			})
		else
			log.error("NOTIFICATIONS", "Failed to send notification", {
				client_id = client_id,
				method = method,
				error = err,
			})
		end
	end
end

-- Check if buffer is a real file (safe version for fast events)
local function is_real_file_safe(bufnr, buftype, filetype, filepath)
	-- Skip special buffers
	if buftype ~= "" and buftype ~= "acwrite" then
		return false
	end
	
	-- Skip empty paths
	if filepath == "" then
		return false
	end
	
	-- Skip terminal buffers (check both buftype and file path)
	if buftype == "terminal" or filepath:match("^term://") then
		return false
	end
	
	-- Skip special filetypes
	local special_filetypes = {
		["claude_conversation"] = true,
		["claude_context"] = true,
		["claude_preview"] = true,
		["help"] = true,
		["qf"] = true,
		["terminal"] = true,
		["prompt"] = true,
		[""] = true,
	}
	if special_filetypes[filetype] then
		return false
	end
	
	-- Skip non-file URIs
	if filepath:match("^%w+://") and not filepath:match("^file://") then
		return false
	end
	
	-- Check if it's an actual file on disk
	local stat = vim.loop.fs_stat(filepath)
	return stat and stat.type == "file"
end

-- Check if buffer is a real file (for use outside fast events)
local function is_real_file(bufnr)
	local bo = vim.bo[bufnr]
	local buftype = bo.buftype
	local filetype = bo.filetype
	local filepath = vim.api.nvim_buf_get_name(bufnr)
	return is_real_file_safe(bufnr, buftype, filetype, filepath)
end

-- Notify about file/selection changes
function M.notify_selection_changed(bufnr, filepath, selection)
	-- Use provided buffer or get current (but not in fast events)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	filepath = filepath or vim.api.nvim_buf_get_name(bufnr)

	-- Skip if not a real file
	if not is_real_file(bufnr) then
		log.debug("NOTIFICATIONS", "Skipping non-real file notification", { 
			filepath = filepath,
			bufnr = bufnr 
		})
		return
	end

	-- If selection not provided, get it (only when not in fast events)
	if not selection then
		-- Get current cursor/selection
		local mode = vim.fn.mode()

		if mode == "v" or mode == "V" or mode == "\22" then -- visual modes
			local start_pos = vim.fn.getpos("'<")
			local end_pos = vim.fn.getpos("'>")

			selection = {
				isEmpty = false,
				start = {
					line = start_pos[2] - 1, -- Convert to 0-based
					character = start_pos[3] - 1,
				},
				["end"] = {
					line = end_pos[2] - 1,
					character = end_pos[3] - 1,
				},
			}
		else
			-- No selection, just cursor position
			local cursor = vim.api.nvim_win_get_cursor(0)
			selection = {
				isEmpty = true,
				start = {
					line = cursor[1] - 1, -- Convert to 0-based
					character = cursor[2],
				},
				["end"] = {
					line = cursor[1] - 1,
					character = cursor[2],
				},
			}
		end
	end

	M.send_notification("selection_changed", {
		filePath = filepath,
		selection = selection,
	})
end

-- Notify about diagnostics changes
function M.notify_diagnostics_changed()
	local uris = {}

	-- Get all buffers with diagnostics
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			if filepath ~= "" then
				local diagnostics = vim.diagnostic.get(bufnr)
				if #diagnostics > 0 then
					table.insert(uris, "file://" .. filepath)
				end
			end
		end
	end

	M.send_notification("diagnostics_changed", {
		uris = uris,
	})
end

-- Notify that IDE is connected
function M.notify_ide_connected()
	M.send_notification("ide_connected", {
		name = "Neovim",
		version = vim.version().major .. "." .. vim.version().minor .. "." .. vim.version().patch,
		pid = vim.fn.getpid()
	})
end

-- Force notify about a specific file (used when opening terminal)
function M.notify_file_opened(filepath)
	if not filepath or filepath == "" then
		return
	end
	
	-- Create a minimal selection at cursor position
	local selection = {
		isEmpty = true,
		start = { line = 0, character = 0 },
		["end"] = { line = 0, character = 0 },
	}
	
	M.send_notification("selection_changed", {
		filePath = filepath,
		selection = selection,
	})
end

-- Debounce timers
local timers = {
	file_change = nil,
	cursor_move = nil,
	diagnostics = nil,
}

-- Cancel a timer if it exists
local function cancel_timer(timer_name)
	if timers[timer_name] then
		timers[timer_name]:stop()
		timers[timer_name] = nil
	end
end

-- Setup autocmds for notifications
function M.setup()
	local group = vim.api.nvim_create_augroup("ClaudeCodeNotifications", { clear = true })

	-- Notify on file changes with debouncing
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = group,
		callback = function(args)
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			
			-- Capture all buffer properties at once
			local bo = vim.bo[bufnr]
			local buftype = bo.buftype
			local filetype = bo.filetype
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			
			-- Skip if not a real file
			if not is_real_file_safe(bufnr, buftype, filetype, filepath) then
				return
			end
			
			-- Get selection info before deferring (to avoid fast event issues)
			local mode = vim.fn.mode()
			local selection
			if mode == "v" or mode == "V" or mode == "\22" then -- visual modes
				local start_pos = vim.fn.getpos("'<")
				local end_pos = vim.fn.getpos("'>")
				selection = {
					isEmpty = false,
					start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
					["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
				}
			else
				local cursor = vim.api.nvim_win_get_cursor(0)
				selection = {
					isEmpty = true,
					start = { line = cursor[1] - 1, character = cursor[2] },
					["end"] = { line = cursor[1] - 1, character = cursor[2] },
				}
			end
			
			-- Cancel previous timer and set new one
			cancel_timer("file_change")
			timers.file_change = vim.defer_fn(function()
				-- Re-check using captured values
				if is_real_file_safe(bufnr, buftype, filetype, filepath) then
					M.notify_selection_changed(bufnr, filepath, selection)
				end
			end, 100)
		end,
		desc = "Notify Claude of active file changes",
	})

	-- Throttled cursor/selection notifications
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
		group = group,
		callback = function(args)
			local bufnr = args.buf or vim.api.nvim_get_current_buf()
			
			-- Capture all buffer properties at once
			local bo = vim.bo[bufnr]
			local buftype = bo.buftype
			local filetype = bo.filetype
			local filepath = vim.api.nvim_buf_get_name(bufnr)
			
			-- Skip if not a real file
			if not is_real_file_safe(bufnr, buftype, filetype, filepath) then
				return
			end
			
			-- Get selection info before deferring (to avoid fast event issues)
			local mode = vim.fn.mode()
			local selection
			if mode == "v" or mode == "V" or mode == "\22" then -- visual modes
				local start_pos = vim.fn.getpos("'<")
				local end_pos = vim.fn.getpos("'>")
				selection = {
					isEmpty = false,
					start = { line = start_pos[2] - 1, character = start_pos[3] - 1 },
					["end"] = { line = end_pos[2] - 1, character = end_pos[3] - 1 },
				}
			else
				local cursor = vim.api.nvim_win_get_cursor(0)
				selection = {
					isEmpty = true,
					start = { line = cursor[1] - 1, character = cursor[2] },
					["end"] = { line = cursor[1] - 1, character = cursor[2] },
				}
			end
			
			-- Cancel previous timer and set new one with longer delay
			cancel_timer("cursor_move")
			timers.cursor_move = vim.defer_fn(function()
				-- Re-check using captured values
				if is_real_file_safe(bufnr, buftype, filetype, filepath) then
					M.notify_selection_changed(bufnr, filepath, selection)
				end
			end, 300)
		end,
		desc = "Notify Claude of selection changes (throttled)",
	})

	-- Diagnostics notifications with debouncing
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		callback = function()
			-- Cancel previous timer and set new one
			cancel_timer("diagnostics")
			timers.diagnostics = vim.defer_fn(M.notify_diagnostics_changed, 500)
		end,
		desc = "Notify Claude of diagnostic changes",
	})

	log.info("NOTIFICATIONS", "Editor notifications initialized")
end

-- Cleanup function to cancel all timers
function M.cleanup()
	for timer_name, _ in pairs(timers) do
		cancel_timer(timer_name)
	end
	log.info("NOTIFICATIONS", "Editor notifications cleaned up")
end

return M
