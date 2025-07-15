-- MCP Tools implementation for claude-code.nvim
-- Implements all tools defined in the MCP specification

local events = require("claude-code.events")

local M = {}

-- Tool registry
local tools = {}

-- Register a tool
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
}, function(args)
	-- Create temporary file for new contents
	local temp_file = vim.fn.tempname()
	vim.fn.writefile(vim.split(args.new_file_contents, "\n"), temp_file)

	-- Open new tab with the specified name
	vim.cmd("tabnew")
	vim.cmd("file " .. vim.fn.fnameescape(args.tab_name))

	-- Open diff view
	vim.cmd("edit " .. vim.fn.fnameescape(args.old_file_path))
	vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(temp_file))

	-- Set buffer name for temp file
	vim.cmd("file " .. vim.fn.fnameescape(args.new_file_path))

	-- Emit diff created event
	events.emit(events.events.DIFF_CREATED, {
		old_file_path = args.old_file_path,
		new_file_path = args.new_file_path,
		tab_name = args.tab_name,
	})

	return {
		content = {
			{
				type = "text",
				text = "Opened diff view: " .. args.old_file_path .. " vs " .. args.new_file_path,
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

	-- Format diagnostics for response
	local formatted = {}
	for _, diag in ipairs(diagnostics) do
		-- Get buffer number and file path
		local bufnr = diag.bufnr
		local file_path = vim.api.nvim_buf_get_name(bufnr)
		local uri = "file://" .. file_path

		-- Convert Neovim severity to LSP severity
		local severity_map = {
			[vim.diagnostic.severity.ERROR] = 1,
			[vim.diagnostic.severity.WARN] = 2,
			[vim.diagnostic.severity.INFO] = 3,
			[vim.diagnostic.severity.HINT] = 4,
		}

		table.insert(formatted, {
			uri = uri,
			severity = severity_map[diag.severity] or 4,
			message = diag.message,
			source = diag.source or "nvim",
			code = diag.code,
			range = {
				start = { line = diag.lnum, character = diag.col or 0 },
				["end"] = { line = diag.end_lnum or diag.lnum, character = diag.end_col or diag.col or 0 },
			},
		})
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
	properties = {},
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

	return {
		content = {
			{
				type = "text",
				text = json.encode({
					text = text,
					range = {
						start = { line = start_line - 1, character = start_col - 1 },
						["end"] = { line = end_line - 1, character = end_col - 1 },
					},
				}),
			},
		},
	}
end)

-- getOpenEditors tool
register_tool("getOpenEditors", "Get open editors", {
	type = "object",
	properties = {},
}, function(args)
	local editors = {}

	-- Get all buffers
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name ~= "" then
				local modified = vim.api.nvim_buf_get_option(bufnr, "modified")
				local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

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
				text = json.encode(editors),
			},
		},
	}
end)

-- getWorkspaceFolders tool
register_tool("getWorkspaceFolders", "Get workspace folders", {
	type = "object",
	properties = {},
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
				text = vim.json.encode(folders),
			},
		},
	}
end)

-- closeAllDiffTabs tool
register_tool("closeAllDiffTabs", "Close all diff view tabs", {
	type = "object",
	properties = {},
	required = {},
}, function(args)
	-- Close all diff windows
	local closed_count = 0

	-- Iterate through all windows
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.bo[buf].filetype
		local diff = vim.wo[win].diff

		-- Check if it's a diff window
		if diff or ft == "diff" then
			-- Close the window
			vim.api.nvim_win_close(win, false)
			closed_count = closed_count + 1
		end
	end

	return {
		content = {
			{
				type = "text",
				text = string.format("Closed %d diff tab(s)", closed_count),
			},
		},
	}
end)

-- List all available tools
function M.list()
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
function M.execute(name, arguments)
	local tool = tools[name]
	if not tool then
		error("Tool not found: " .. name)
	end

	-- Validate required arguments
	if tool.inputSchema.required then
		for _, required in ipairs(tool.inputSchema.required) do
			if arguments[required] == nil then
				error("Missing required parameter: " .. required)
			end
		end
	end

	-- Execute tool handler
	return tool.handler(arguments)
end

-- JSON for encoding responses
local json = vim.json

return M
