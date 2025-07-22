-- Editor notifications to Claude
-- Sends notifications about editor state changes without tracking state

local M = {}

local log = require("claude-code-ide.log")

-- Send notification to all connected Claude clients
---@param method string Notification method name
---@param params table? Notification parameters
function M.send_notification(method, params)
	-- Get the server module
	local server = require("claude-code-ide.server")
	local current_server = server.get_server()

	if not current_server or not current_server.clients then
		return
	end

	-- Create notification message
	local message = {
		jsonrpc = "2.0",
		method = method,
		params = params or vim.empty_dict(),
	}

	local json = vim.json.encode(message)

	-- Send to all connected clients
	local websocket = require("claude-code-ide.server.websocket")
	for client_id, client in pairs(current_server.clients) do
		local ok, err = pcall(websocket.send_text, client, json)
		if ok then
			log.debug("NOTIFICATIONS", "Sent notification", {
				client_id = client_id,
				method = method,
			})
		else
			log.warn("NOTIFICATIONS", "Failed to send notification", {
				client_id = client_id,
				method = method,
				error = err,
			})
		end
	end
end

-- Notify about file/selection changes
function M.notify_selection_changed()
	local bufnr = vim.api.nvim_get_current_buf()
	local filepath = vim.api.nvim_buf_get_name(bufnr)

	if filepath == "" then
		return
	end

	-- Get current cursor/selection
	local mode = vim.fn.mode()
	local selection

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
	})
end

-- Setup autocmds for notifications
function M.setup()
	local group = vim.api.nvim_create_augroup("ClaudeCodeNotifications", { clear = true })

	-- Notify on file changes
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = group,
		callback = function()
			-- Small delay to ensure buffer is fully loaded
			vim.defer_fn(M.notify_selection_changed, 50)
		end,
		desc = "Notify Claude of active file changes",
	})

	-- Throttled cursor/selection notifications
	local cursor_timer = nil
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
		group = group,
		callback = function()
			if cursor_timer then
				cursor_timer:stop()
			end
			cursor_timer = vim.defer_fn(M.notify_selection_changed, 200)
		end,
		desc = "Notify Claude of selection changes (throttled)",
	})

	-- Diagnostics notifications
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		callback = function()
			vim.defer_fn(M.notify_diagnostics_changed, 500)
		end,
		desc = "Notify Claude of diagnostic changes",
	})

	log.info("NOTIFICATIONS", "Editor notifications initialized")
end

return M
