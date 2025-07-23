-- MCP Tools implementation for claude-code-ide.nvim
-- Implements all tools defined in the MCP specification

local events = require("claude-code-ide.events")
local json = vim.json

local M = {}

-- Tool registry
local tools = {}

-- Create MCP-compliant schema format matching real-world logs
local function create_schema(properties, required)
	local schema = {
		type = "object",
		properties = properties or vim.empty_dict(),
		additionalProperties = false,
		["$schema"] = "http://json-schema.org/draft-07/schema#",
	}

	-- Always include required array for consistency (even if empty)
	schema.required = required or {}

	return schema
end

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

-- openFile tool - matches real-world logs exactly
register_tool(
	"openFile",
	"Open a file in the editor and optionally select a range of text",
	create_schema({
		filePath = {
			type = "string",
			description = "Path to the file to open",
		},
		preview = {
			type = "boolean",
			description = "Whether to open the file in preview mode",
			default = false,
		},
		startText = {
			type = "string",
			description = "Text pattern to find the start of the selection range. Selects from the beginning of this match.",
		},
		endText = {
			type = "string",
			description = "Text pattern to find the end of the selection range. Selects up to the end of this match. If not provided, only the startText match will be selected.",
		},
		selectToEndOfLine = {
			type = "boolean",
			description = "If true, selection will extend to the end of the line containing the endText match.",
			default = false,
		},
		makeFrontmost = {
			type = "boolean",
			description = "Whether to make the file the active editor tab. If false, the file will be opened in the background without changing focus.",
			default = true,
		},
	}, { "filePath", "startText", "endText" }),
	function(args)
		local file_path = args.filePath or ""
		local preview = args.preview or false
		local start_text = args.startText or ""
		local end_text = args.endText or ""
		local make_frontmost = args.makeFrontmost == nil and true or args.makeFrontmost

		-- Open the file
		local cmd = preview and ("pedit " .. vim.fn.fnameescape(file_path))
			or ("edit " .. vim.fn.fnameescape(file_path))
		pcall(vim.cmd, cmd)

		local bufnr = vim.fn.bufnr(file_path)
		if bufnr == -1 then
			return {
				content = {
					{
						type = "text",
						text = "Failed to open file: " .. file_path,
					},
				},
			}
		end

		-- Handle text selection if provided
		if start_text ~= "" then
			-- Search for start text
			local start_pos = vim.fn.searchpos(vim.fn.escape(start_text, "[]\\"), "nw", 0)
			if start_pos[1] > 0 then
				vim.fn.cursor(start_pos[1], start_pos[2])

				if end_text ~= "" then
					-- Search for end text
					local end_pos = vim.fn.searchpos(vim.fn.escape(end_text, "[]\\"), "nW", 0)
					if end_pos[1] > 0 then
						-- Select from start to end
						vim.cmd("normal! v")
						vim.fn.cursor(end_pos[1], end_pos[2] + #end_text - 1)
					end
				else
					-- Select just the start text
					vim.cmd("normal! v")
					vim.fn.cursor(start_pos[1], start_pos[2] + #start_text - 1)
				end
			end
		end

		-- Make frontmost if requested
		if make_frontmost and not preview then
			vim.cmd("normal! zz") -- Center the view
		end

		return {
			content = {
				{
					type = "text",
					text = "Opened file: " .. file_path,
				},
			},
		}
	end
)

-- openDiff tool - matches real-world logs
register_tool(
	"openDiff",
	"Open a git diff for the file",
	create_schema({
		old_file_path = {
			type = "string",
			description = "Path to the file to show diff for. If not provided, uses active editor.",
		},
		new_file_path = {
			type = "string",
			description = "Path to the file to show diff for. If not provided, uses active editor.",
		},
		new_file_contents = {
			type = "string",
			description = "Contents of the new file. If not provided then the current file contents of new_file_path will be used.",
		},
		tab_name = {
			type = "string",
			description = "Path to the file to show diff for. If not provided, uses active editor.",
		},
	}, { "old_file_path", "new_file_path", "new_file_contents", "tab_name" }),
	function(args)
		local ui_diff = require("claude-code-ide.ui.diff")
		local old_path = args.old_file_path
		local new_path = args.new_file_path
		local new_contents = args.new_file_contents
		local tab_name = args.tab_name

		local result = ui_diff.open_diff({
			old_file_path = old_path,
			new_file_path = new_path,
			new_file_contents = new_contents,
			tab_name = tab_name,
		})

		return {
			content = {
				{
					type = "text",
					text = result.message or "Diff opened",
				},
			},
		}
	end
)

-- getDiagnostics tool - matches real-world logs
register_tool(
	"getDiagnostics",
	"Get language diagnostics from VS Code",
	create_schema({
		uri = {
			type = "string",
			description = "Optional file URI to get diagnostics for. If not provided, gets diagnostics for all files.",
		},
	}, {}),
	function(args)
		local uri = args.uri
		local diagnostics = {}

		-- Get diagnostics from all buffers or specific buffer
		if uri then
			-- Convert URI to file path
			local file_path = uri:gsub("^file://", "")
			local bufnr = vim.fn.bufnr(file_path)
			if bufnr ~= -1 then
				local buf_diagnostics = vim.diagnostic.get(bufnr)
				if #buf_diagnostics > 0 then
					table.insert(diagnostics, {
						uri = uri,
						diagnostics = vim.tbl_map(function(diag)
							return {
								message = diag.message,
								severity = ({ "Error", "Warning", "Information", "Hint" })[diag.severity] or "Error",
								range = {
									start = { line = diag.lnum, character = diag.col },
									["end"] = {
										line = diag.end_lnum or diag.lnum,
										character = diag.end_col or diag.col,
									},
								},
								source = diag.source,
								code = diag.code,
							}
						end, buf_diagnostics),
					})
				end
			end
		else
			-- Get diagnostics from all buffers
			for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
				if vim.api.nvim_buf_is_loaded(bufnr) then
					local name = vim.api.nvim_buf_get_name(bufnr)
					if name ~= "" then
						local buf_diagnostics = vim.diagnostic.get(bufnr)
						if #buf_diagnostics > 0 then
							table.insert(diagnostics, {
								uri = "file://" .. name,
								diagnostics = vim.tbl_map(function(diag)
									return {
										message = diag.message,
										severity = ({ "Error", "Warning", "Information", "Hint" })[diag.severity]
											or "Error",
										range = {
											start = { line = diag.lnum, character = diag.col },
											["end"] = {
												line = diag.end_lnum or diag.lnum,
												character = diag.end_col or diag.col,
											},
										},
										source = diag.source,
										code = diag.code,
									}
								end, buf_diagnostics),
							})
						end
					end
				end
			end
		end

		return {
			content = {
				{
					type = "text",
					text = json.encode(diagnostics),
				},
			},
		}
	end
)

-- close_tab tool - matches real-world logs
register_tool(
	"close_tab",
	"",
	create_schema({
		tab_name = {
			type = "string",
		},
	}, { "tab_name" }),
	function(args)
		local tab_name = args.tab_name

		-- Find and close the tab/buffer
		for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
			local name = vim.api.nvim_buf_get_name(bufnr)
			if name:match(tab_name) then
				pcall(vim.cmd, "bdelete " .. bufnr)
				break
			end
		end

		return {
			content = {
				{
					type = "text",
					text = "Closed tab: " .. tab_name,
				},
			},
		}
	end
)

-- closeAllDiffTabs tool - matches real-world logs
register_tool("closeAllDiffTabs", "Close all diff tabs in the editor", create_schema({}, {}), function(args)
	local ui_diff = require("claude-code-ide.ui.diff")
	local count = ui_diff.close_all_diffs()

	return {
		content = {
			{
				type = "text",
				text = "CLOSED_" .. count .. "_DIFF_TABS",
			},
		},
	}
end)

-- getCurrentSelection tool
register_tool(
	"getCurrentSelection",
	"Get the current text selection in the active editor",
	create_schema({}, {}),
	function(args)
		-- Get visual selection
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")

		local start_line = start_pos[2]
		local start_col = start_pos[3]
		local end_line = end_pos[2]
		local end_col = end_pos[3]

		-- Get current buffer info
		local bufnr = vim.api.nvim_get_current_buf()
		local file_path = vim.api.nvim_buf_get_name(bufnr)
		local uri = file_path ~= "" and ("file://" .. file_path) or ""

		-- Extract selected text
		local text = ""
		if start_line > 0 and end_line > 0 then
			local lines = vim.api.nvim_buf_get_text(bufnr, start_line - 1, start_col - 1, end_line - 1, end_col, {})
			text = table.concat(lines, "\n")
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
	end
)

-- getOpenEditors tool
register_tool("getOpenEditors", "Get information about currently open editors", create_schema({}, {}), function(args)
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
register_tool(
	"getWorkspaceFolders",
	"Get all workspace folders currently open in the IDE",
	create_schema({}, {}),
	function(args)
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
	end
)

-- checkDocumentDirty tool - matches real-world logs
register_tool(
	"checkDocumentDirty",
	"Check if a document has unsaved changes (is dirty)",
	create_schema({
		filePath = {
			type = "string",
			description = "Path to the file to check",
		},
	}, { "filePath" }),
	function(args)
		local file_path = args.filePath
		local bufnr = vim.fn.bufnr(file_path)
		local is_dirty = false

		if bufnr ~= -1 then
			is_dirty = vim.bo[bufnr].modified
		end

		return {
			content = {
				{
					type = "text",
					text = json.encode({ isDirty = is_dirty }),
				},
			},
		}
	end
)

-- saveDocument tool - matches real-world logs
register_tool(
	"saveDocument",
	"Save a document with unsaved changes",
	create_schema({
		filePath = {
			type = "string",
			description = "Path to the file to save",
		},
	}, { "filePath" }),
	function(args)
		local file_path = args.filePath
		local bufnr = vim.fn.bufnr(file_path)

		if bufnr ~= -1 then
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("write")
			end)
		end

		return {
			content = {
				{
					type = "text",
					text = "Saved: " .. file_path,
				},
			},
		}
	end
)

-- getLatestSelection tool - matches real-world logs
register_tool(
	"getLatestSelection",
	"Get the most recent text selection (even if not in the active editor)",
	create_schema({}, {}),
	function(args)
		-- This is similar to getCurrentSelection but could potentially track selection history
		-- For now, just return current selection
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")

		local start_line = start_pos[2]
		local start_col = start_pos[3]
		local end_line = end_pos[2]
		local end_col = end_pos[3]

		local bufnr = vim.api.nvim_get_current_buf()
		local file_path = vim.api.nvim_buf_get_name(bufnr)
		local uri = file_path ~= "" and ("file://" .. file_path) or ""

		local text = ""
		if start_line > 0 and end_line > 0 then
			local lines = vim.api.nvim_buf_get_text(bufnr, start_line - 1, start_col - 1, end_line - 1, end_col, {})
			text = table.concat(lines, "\n")
		end

		return {
			content = {
				{
					type = "text",
					text = json.encode({
						text = text,
						filePath = file_path,
						fileUrl = uri,
						selection = {
							start = { line = start_line - 1, character = start_col - 1 },
							["end"] = { line = end_line - 1, character = end_col - 1 },
							isEmpty = text == "",
						},
					}),
				},
			},
		}
	end
)

-- Register checkDocumentDirty tool
register_tool(
	"checkDocumentDirty",
	"Check if a document has unsaved changes (is dirty)",
	create_schema({
		filePath = {
			type = "string",
			description = "Path to the file to check",
		},
	}, { "filePath" }),
	function(args)
		local filepath = vim.fn.expand(args.filePath)
		
		-- Find the buffer for this file
		local bufnr = vim.fn.bufnr(filepath)
		if bufnr == -1 then
			return {
				content = {
					{
						type = "text",
						text = vim.json.encode({
							success = false,
							message = "File is not open in any buffer",
							isDirty = false,
						}),
					},
				},
			}
		end
		
		-- Check if buffer is modified
		local is_modified = vim.bo[bufnr].modified
		
		return {
			content = {
				{
					type = "text",
					text = vim.json.encode({
						success = true,
						isDirty = is_modified,
						filePath = filepath,
						bufferNumber = bufnr,
					}),
				},
			},
		}
	end
)

-- Register saveDocument tool
register_tool(
	"saveDocument",
	"Save a document with unsaved changes",
	create_schema({
		filePath = {
			type = "string",
			description = "Path to the file to save",
		},
	}, { "filePath" }),
	function(args)
		local filepath = vim.fn.expand(args.filePath)
		
		-- Find the buffer for this file
		local bufnr = vim.fn.bufnr(filepath)
		if bufnr == -1 then
			return {
				content = {
					{
						type = "text",
						text = vim.json.encode({
							success = false,
							message = "File is not open in any buffer",
						}),
					},
				},
			}
		end
		
		-- Save the buffer
		local ok, err = pcall(function()
			vim.api.nvim_buf_call(bufnr, function()
				vim.cmd("write")
			end)
		end)
		
		if not ok then
			return {
				content = {
					{
						type = "text",
						text = vim.json.encode({
							success = false,
							message = "Failed to save file: " .. tostring(err),
						}),
					},
				},
			}
		end
		
		return {
			content = {
				{
					type = "text",
					text = vim.json.encode({
						success = true,
						message = "File saved successfully",
						filePath = filepath,
					}),
				},
			},
		}
	end
)

-- Register close_tab tool
register_tool(
	"close_tab",
	"Close an editor tab/buffer",
	create_schema({
		tab_name = {
			type = "string",
			description = "Path or name of the file/buffer to close",
		},
	}, { "tab_name" }),
	function(args)
		local tab_name = args.tab_name
		local closed_count = 0
		
		-- Try to find buffer by exact path match first
		local bufnr = vim.fn.bufnr(vim.fn.expand(tab_name))
		
		-- If not found, try to find by partial name match
		if bufnr == -1 then
			for _, buf in ipairs(vim.api.nvim_list_bufs()) do
				local name = vim.api.nvim_buf_get_name(buf)
				if name:find(tab_name, 1, true) then
					bufnr = buf
					break
				end
			end
		end
		
		if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
			-- Check if buffer has unsaved changes
			if vim.bo[bufnr].modified then
				-- Force close without saving
				vim.api.nvim_buf_delete(bufnr, { force = true })
			else
				vim.api.nvim_buf_delete(bufnr, {})
			end
			closed_count = 1
		end
		
		return {
			content = {
				{
					type = "text",
					text = closed_count > 0 and "TAB_CLOSED" or "TAB_NOT_FOUND",
				},
			},
		}
	end
)

-- Register getLatestSelection tool
register_tool(
	"getLatestSelection",
	"Get the most recent text selection (even if not in the active editor)",
	create_schema({}, {}),
	function(args)
		-- Get the last visual selection marks
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		
		-- Check if there was a visual selection
		if start_pos[2] == 0 or end_pos[2] == 0 then
			return {
				content = {
					{
						type = "text",
						text = vim.json.encode({
							success = false,
							message = "No selection available",
						}),
					},
				},
			}
		end
		
		-- Get the buffer number from the mark
		local bufnr = start_pos[1]
		if bufnr == 0 then
			bufnr = vim.api.nvim_get_current_buf()
		end
		
		-- Get buffer path
		local filepath = vim.api.nvim_buf_get_name(bufnr)
		
		-- Get the selected lines
		local lines = vim.api.nvim_buf_get_lines(bufnr, start_pos[2] - 1, end_pos[2], false)
		
		-- Handle partial line selection
		local selected_text
		if #lines == 1 then
			-- Single line selection
			selected_text = lines[1]:sub(start_pos[3], end_pos[3])
		elseif #lines > 1 then
			-- Multi-line selection
			-- First line from start column to end
			lines[1] = lines[1]:sub(start_pos[3])
			-- Last line from beginning to end column
			lines[#lines] = lines[#lines]:sub(1, end_pos[3])
			selected_text = table.concat(lines, "\n")
		else
			selected_text = ""
		end
		
		return {
			content = {
				{
					type = "text",
					text = vim.json.encode({
						success = true,
						text = selected_text,
						filePath = filepath,
						fileUrl = "file://" .. filepath,
						selection = {
							start = {
								line = start_pos[2] - 1, -- 0-indexed
								character = start_pos[3] - 1,
							},
							["end"] = {
								line = end_pos[2] - 1,
								character = end_pos[3] - 1,
							},
							isEmpty = selected_text == "",
						},
					}),
				},
			},
		}
	end
)

-- Dynamic tool registration for executeCode (requires terminal module)
local function register_execute_code_tool()
	local terminal = require("claude-code-ide.terminal")

	register_tool(
		"executeCode",
		"Execute Lua code in the current Neovim instance.\n\nThe code will be evaluated in Neovim's Lua environment with full access to vim.* APIs.\n\nResults will be returned as strings. Tables and other complex types will be converted using vim.inspect().\n\nAvoid modifying the editor state unless explicitly requested by the user.",
		create_schema({
			code = {
				type = "string",
				description = "The Lua code to be executed in Neovim.",
			},
		}, { "code" }),
		function(args)
			local code = args.code
			if not code or code == "" then
				return {
					content = {
						{
							type = "text",
							text = "No code provided",
						},
					},
				}
			end

			local result = terminal.execute_code(code)
			-- Ensure text is always a string
			local output_text = tostring(result.output or "Code executed")

			return {
				content = {
					{
						type = "text",
						text = output_text,
					},
				},
			}
		end
	)
end

-- List all tools
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
