-- MCP Tools implementation for claude-code-ide.nvim
-- Implements all tools defined in the MCP specification

local events = require("claude-code-ide.events")
local json = vim.json

local M = {}

-- Tool registry
local tools = {}

-- Register a tool
---@param name string Tool name
---@param description string Tool description
---@param input_schema table JSON Schema for input validation
---@param handler function Tool implementation function
local function register_tool(name, description, input_schema, handler)
	tools[name] = {
		name = name,
		description = description,
		inputSchema = input_schema,
		handler = handler,
	}
end

-- openFile tool
register_tool("openFile", "Open a file in the editor", {
	type = "object",
	properties = {
		filePath = { type = "string" },
		preview = { type = "boolean" },
		startText = { type = "string" },
		endText = { type = "string" },
		makeFrontmost = { type = "boolean" },
	},
	required = { "filePath" },
}, function(args)
	-- Expand file path
	local file_path = vim.fn.expand(args.filePath)

	-- Check if file exists
	if vim.fn.filereadable(file_path) ~= 1 then
		return {
			content = {
				{
					type = "text",
					text = "File not found: " .. file_path,
				},
			},
		}
	end

	-- Open file
	if args.preview then
		vim.cmd("pedit " .. vim.fn.fnameescape(file_path))
	else
		vim.cmd("edit " .. vim.fn.fnameescape(file_path))
	end

	-- Handle text selection if provided
	if args.startText or args.endText then
		vim.schedule(function()
			local start_pos, end_pos

			if args.startText then
				start_pos = vim.fn.searchpos(vim.fn.escape(args.startText, "\\"), "w")
			end

			if args.endText then
				end_pos = vim.fn.searchpos(vim.fn.escape(args.endText, "\\"), "w")
			end

			-- Select text if both positions found
			if start_pos and start_pos[1] > 0 and end_pos and end_pos[1] > 0 then
				vim.fn.setpos("'<", { 0, start_pos[1], start_pos[2], 0 })
				vim.fn.setpos("'>", { 0, end_pos[1], end_pos[2] + #args.endText - 1, 0 })
				vim.cmd("normal! gv")
			end
		end)
	end

	-- Make frontmost if requested
	if args.makeFrontmost ~= false then
		-- Already done by edit command
	end

	-- Emit file opened event
	events.emit(events.events.FILE_OPENED, {
		file_path = file_path,
		preview = args.preview,
		selection = args.startText and {
			start_text = args.startText,
			end_text = args.endText,
		} or nil,
	})

	return {
		content = {
			{
				type = "text",
				text = "Opened file: " .. file_path,
			},
		},
	}
end)

-- openDiff tool
register_tool("openDiff", "Open a diff view", {
	type = "object",
	properties = {
		old_file_path = { type = "string" },
		new_file_path = { type = "string" },
		new_file_contents = { type = "string" },
		tab_name = { type = "string" },
	},
	required = { "old_file_path", "new_file_path", "new_file_contents", "tab_name" },
}, function(args, session)
	local diff_ui = require("claude-code-ide.ui.diff")
	local notify = require("claude-code-ide.ui.notify")
	local async = require("plenary.async")

	-- Store session data
	if session and session.data then
		session.data.pending_diffs = session.data.pending_diffs or {}
		session.data.pending_diffs[args.tab_name] = {
			args = args,
			created_at = vim.loop.now(),
		}
	end

	-- Create a promise to wait for the user's decision
	local tx, rx = async.control.channel.oneshot()

	-- Store the diff window reference
	local diff_window

	-- Show the diff preview
	diff_window = diff_ui.show({
		old_file_path = args.old_file_path,
		new_file_path = args.new_file_path,
		new_file_contents = args.new_file_contents,
		on_accept = function(new_lines)
			-- Don't write to file - Claude will handle that
			if session and session.data and session.data.pending_diffs then
				session.data.pending_diffs[args.tab_name] = nil
			end

			notify.success("Changes accepted for " .. vim.fn.fnamemodify(args.old_file_path, ":t"))

			-- Close the diff window
			if diff_window and diff_window.close then
				vim.schedule(function()
					diff_window.close()
				end)
			end

			-- Send FILE_SAVED to indicate user accepted the changes
			-- Claude will handle the actual file update
			tx({
				content = {
					{
						type = "text",
						text = "FILE_SAVED",
					},
					{
						type = "text",
						text = args.new_file_contents,
					},
				},
			})
		end,
		on_reject = function()
			if session and session.data and session.data.pending_diffs then
				session.data.pending_diffs[args.tab_name] = nil
			end

			notify.info("Changes rejected")

			-- Close the diff window
			if diff_window and diff_window.close then
				vim.schedule(function()
					diff_window.close()
				end)
			end

			-- Send the result
			tx({
				content = {
					{
						type = "text",
						text = "DIFF_REJECTED",
					},
					{
						type = "text",
						text = args.tab_name,
					},
				},
			})
		end,
	})

	-- Emit diff created event
	events.emit(events.events.DIFF_CREATED, {
		old_file_path = args.old_file_path,
		new_file_path = args.new_file_path,
		tab_name = args.tab_name,
	})

	-- Wait for the user's decision
	-- This blocks until the user accepts or rejects
	return rx()
end)

-- close_tab tool
-- This is called by Claude when a diff is rejected or after certain operations
register_tool("close_tab", "Close a tab or cleanup after operations", {
	type = "object",
	properties = {
		tab_name = { type = "string", description = "Name of the tab to close" },
	},
	required = {},
}, function(args, session)
	-- Clean up any pending diffs for this tab
	if session and session.data and session.data.pending_diffs and args.tab_name then
		session.data.pending_diffs[args.tab_name] = nil
	end

	-- For now, we don't actually close any tabs in Neovim
	-- This is mainly for Claude's internal state management
	return {
		content = {
			{
				type = "text",
				text = "Tab closed",
			},
		},
	}
end)

-- getDiagnostics tool
register_tool("getDiagnostics", "Get language diagnostics", {
	type = "object",
	properties = {
		uri = { type = "string" },
	},
	required = {},
}, function(args)
	local diagnostics = {}

	if args.uri then
		-- Convert URI to file path
		local file_path = args.uri:gsub("^file://", "")
		local bufnr = vim.fn.bufnr(file_path)

		if bufnr ~= -1 then
			diagnostics = vim.diagnostic.get(bufnr)
		end
	else
		-- Get all diagnostics
		diagnostics = vim.diagnostic.get()
	end

	-- Group diagnostics by file URI
	local diagnostics_by_uri = {}
	for _, diag in ipairs(diagnostics) do
		-- Get buffer number and file path
		local bufnr = diag.bufnr
		local file_path = vim.api.nvim_buf_get_name(bufnr)
		local uri = "file://" .. file_path

		-- Initialize array for this URI if needed
		if not diagnostics_by_uri[uri] then
			diagnostics_by_uri[uri] = {}
		end

		-- Convert Neovim severity to string names
		local severity_names = {
			[vim.diagnostic.severity.ERROR] = "ERROR",
			[vim.diagnostic.severity.WARN] = "WARN",
			[vim.diagnostic.severity.INFO] = "INFO",
			[vim.diagnostic.severity.HINT] = "HINT",
		}

		table.insert(diagnostics_by_uri[uri], {
			severity = severity_names[diag.severity] or "INFO",
			message = diag.message,
			source = diag.source or "nvim",
			code = diag.code,
			range = {
				start = { line = diag.lnum, character = diag.col or 0 },
				["end"] = { line = diag.end_lnum or diag.lnum, character = diag.end_col or diag.col or 0 },
			},
		})
	end

	-- Convert to array format expected by Claude
	local formatted = {}
	for uri, diags in pairs(diagnostics_by_uri) do
		table.insert(formatted, {
			uri = uri,
			diagnostics = diags,
		})
	end

	-- If a specific URI was requested and has no diagnostics, return empty array for that URI
	if args.uri and #formatted == 0 then
		formatted = { {
			uri = args.uri,
			diagnostics = {},
		} }
	end

	-- Emit diagnostics provided event
	events.emit(events.events.DIAGNOSTICS_PROVIDED, {
		uri = args.uri,
		diagnostics = formatted,
		count = #formatted,
	})

	return {
		content = {
			{
				type = "text",
				text = vim.json.encode(formatted),
			},
		},
	}
end)

-- getCurrentSelection tool
register_tool("getCurrentSelection", "Get current text selection", {
	type = "object",
	properties = vim.empty_dict(),
}, function(args)
	-- Get visual selection or current line
	local mode = vim.fn.mode()
	local lines = {}
	local start_line, start_col, end_line, end_col

	if mode == "v" or mode == "V" or mode == "\22" then
		-- Visual mode - get selection
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		start_line = start_pos[2]
		start_col = start_pos[3]
		end_line = end_pos[2]
		end_col = end_pos[3]

		lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	else
		-- Normal mode - get current line
		local cursor = vim.api.nvim_win_get_cursor(0)
		start_line = cursor[1]
		start_col = 1
		end_line = cursor[1]
		end_col = -1

		lines = { vim.api.nvim_get_current_line() }
	end

	local text = table.concat(lines, "\n")

	-- Get buffer URI if available
	local uri = nil
	if text ~= "" then
		local bufnr = vim.api.nvim_get_current_buf()
		local file_path = vim.api.nvim_buf_get_name(bufnr)
		if file_path ~= "" then
			uri = "file://" .. file_path
		end
	end

	return {
		content = {
			{
				type = "text",
				text = json.encode({
					text = text,
					uri = uri,
					range = text ~= "" and {
						start = { line = start_line - 1, character = start_col - 1 },
						["end"] = { line = end_line - 1, character = end_col - 1 },
					} or nil,
				}),
			},
		},
	}
end)

-- getOpenEditors tool
register_tool("getOpenEditors", "Get open editors", {
	type = "object",
	properties = vim.empty_dict(),
}, function(args)
	local editors = {}

	-- Get all buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name ~= "" then
				local modified = vim.bo[bufnr].modified
				local filetype = vim.bo[bufnr].filetype

				-- Check if buffer is active in any window
				local active = false
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.api.nvim_win_get_buf(win) == bufnr then
						active = true
						break
					end
				end

				table.insert(editors, {
					uri = "file://" .. name,
					name = vim.fn.fnamemodify(name, ":t"),
					language = filetype,
					modified = modified,
					active = active,
				})
			end
		end
	end

	return {
		content = {
			{
				type = "text",
				text = json.encode({ editors = editors }),
			},
		},
	}
end)

-- getWorkspaceFolders tool
register_tool("getWorkspaceFolders", "Get workspace folders", {
	type = "object",
	properties = vim.empty_dict(),
}, function(args)
	local folders = {}

	-- Get current working directory
	local cwd = vim.fn.getcwd()
	table.insert(folders, {
		uri = "file://" .. cwd,
		name = vim.fn.fnamemodify(cwd, ":t"),
	})

	-- TODO: Add support for multiple workspace folders if using project.nvim or similar

	return {
		content = {
			{
				type = "text",
				text = vim.json.encode({ folders = folders }),
			},
		},
	}
end)

-- closeAllDiffTabs tool
register_tool("closeAllDiffTabs", "Close all diff view tabs", {
	type = "object",
	properties = vim.empty_dict(),
	required = {},
}, function(args, session)
	local closed_count = 0

	-- Use session-tracked diff tabs if available
	if session and session.data and session.data.diff_tabs then
		-- Close tabs in reverse order to avoid index issues
		for i = #session.data.diff_tabs, 1, -1 do
			local diff_tab = session.data.diff_tabs[i]
			vim.cmd("tabclose " .. diff_tab.tabnr)
			closed_count = closed_count + 1
		end
		-- Clear the diff tabs list
		session.data.diff_tabs = {}
	else
		-- Fallback: iterate through all tabs
		local current_tab = vim.fn.tabpagenr()

		for tabnr = vim.fn.tabpagenr("$"), 1, -1 do
			-- Switch to tab
			vim.cmd("tabnext " .. tabnr)

			-- Check if any window in this tab has diff mode enabled
			local has_diff = false
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.wo[win].diff then
					has_diff = true
					break
				end
			end

			-- Close tab if it has diff windows
			if has_diff then
				vim.cmd("tabclose")
				closed_count = closed_count + 1
			end
		end

		-- Return to original tab if it still exists
		if vim.fn.tabpagenr("$") >= current_tab then
			vim.cmd("tabnext " .. current_tab)
		end
	end

	return {
		content = {
			{
				type = "text",
				text = closed_count > 0 and string.format("Closed %d diff tabs", closed_count)
					or "No diff tabs to close",
			},
		},
	}
end)

-- executeCode tool (dynamically registered)
local function register_execute_code_tool()
	local terminal = require("claude-code-ide.terminal")
	local tool_def = terminal.create_execute_tool()
	register_tool(tool_def.name, tool_def.description, tool_def.inputSchema, tool_def.handler)
end

-- List all available tools
---@return table[] Array of tool definitions
function M.list()
	-- Register dynamic tools if not already registered
	if not tools.executeCode then
		local ok, _ = pcall(register_execute_code_tool)
		if not ok then
			-- Terminal module might not be available or code execution disabled
		end
	end

	local list = {}
	for name, tool in pairs(tools) do
		table.insert(list, {
			name = tool.name,
			title = tool.name, -- Use name as title for now
			description = tool.description,
			inputSchema = tool.inputSchema,
		})
	end
	return list
end

-- Execute a tool
---@param name string Tool name to execute
---@param arguments table Tool arguments
---@param session? table Optional session object
---@return table|nil Tool execution result
function M.execute(name, arguments, session)
	local tool = tools[name]
	if not tool then
		return nil
	end

	-- Validate required arguments
	if tool.inputSchema.required then
		for _, required in ipairs(tool.inputSchema.required) do
			if arguments[required] == nil then
				-- For file paths, provide empty string as default
				if required == "filePath" then
					arguments[required] = ""
				end
			end
		end
	end

	-- Execute tool handler with session if available
	if session then
		return tool.handler(arguments, session)
	else
		return tool.handler(arguments)
	end
end

return M
